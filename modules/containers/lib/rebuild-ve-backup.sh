#!/bin/bash

## Runs INSIDE the old container, as its root: 'ssh VE bash -s < this', from
## rebuild_ve_backup (libs/rebuildlib.sh). Collects what rebuild-ve-restore.sh
## puts back on the fresh rootfs, into /srv/backup:
##
##   manifest       kind=wordpress|php|static, os=, db=<databases>
##   files/         the restored trees, copied with cp -a so the in-container
##                  numeric owners survive (the host copies them on with cp -a,
##                  and the new container's first start uid-shifts them)
##   db/<name>.sql  one logical dump per database; db/grants.sql the accounts
##   passwd group shadow   the uid 1000..59999 users and groups
##   reference/     packages, enabled units, php.ini, rpm-owned httpd configs:
##                  for reading, never restored
##
## Must work on every release since Fedora 26 (bash 4.4, MariaDB 10.1+).
## Logical dumps, not the datadir: MariaDB 10.x files cannot simply be opened
## by the 11.x of the new rootfs.

set -u
umask 077
B=/srv/backup

fail() {
    echo "BACKUP-ERROR: $*" >&2
    exit 1
}

## a failed earlier attempt: keep it aside, never mix two backups
[[ -e $B ]] && { mv "$B" "$B.prev-$(date +%s)" || fail "cannot move the previous $B aside"; }
mkdir -p "$B/files" "$B/db" "$B/reference" || fail "cannot create $B"

kind=static
[[ -x /usr/bin/php ]] && kind=php
[[ -f /var/www/html/wp-config.php ]] && kind=wordpress
# shellcheck disable=SC1091
source /etc/os-release
printf 'kind=%s\nos=%s %s\n' "$kind" "$ID" "$VERSION_ID" > "$B/manifest"

rpm -qa --qf '%{NAME}\n' | sort > "$B/reference/packages.txt"
systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' > "$B/reference/units.txt"
cp -a /etc/php.ini "$B/reference/" 2>/dev/null

## database: every user database as its own dump, plus the accounts
dbs=''
if [[ -d /var/lib/mysql/mysql ]]
then
    for unit in mariadb mysqld mysql
    do
        systemctl start "$unit" 2>/dev/null && break
    done
    my=()
    [[ -f /etc/mysqldump.conf ]] && my=(--defaults-file=/etc/mysqldump.conf)
    mysql "${my[@]}" -e 'select 1' > /dev/null || fail "cannot connect to the database as root"

    dbs="$(mysql "${my[@]}" -N -e 'show databases' | grep -vxE 'mysql|information_schema|performance_schema|sys' | tr '\n' ' ')"
    for db in $dbs
    do
        mysqldump "${my[@]}" --single-transaction --routines --events --triggers --databases "$db" > "$B/db/$db.sql" || fail "dump of $db failed"
    done

    ## SHOW GRANTS carries the password hash. sql_mode='' lets GRANT create the
    ## account on the new server (NO_AUTO_CREATE_USER is in its default mode).
    {
        echo "SET SESSION sql_mode='';"
        mysql "${my[@]}" -N -e "select user, host from mysql.user where user not in ('root', '', 'mysql', 'mariadb.sys', 'PUBLIC')" |
            while read -r u h
            do
                mysql "${my[@]}" -N -e "show grants for '$u'@'$h'" | sed 's/$/;/'
            done
    } > "$B/db/grants.sql" || fail "grants export failed"
fi
echo "db=$dbs" >> "$B/manifest"

## users and groups of the site owners
awk -F: '$3 >= 1000 && $3 < 60000' /etc/passwd > "$B/passwd"
awk -F: '$3 >= 1000 && $3 < 60000' /etc/group > "$B/group"
cut -d: -f1 "$B/passwd" | while read -r u
do
    grep "^$u:" /etc/shadow
done > "$B/shadow"

## files: the web root, homes, crontabs, the db client configs and the httpd
## configs that no package owns (site vhosts, srvctl's wordpress confs)
paths=(/var/www/html /home /var/spool/cron /root/.my.cnf /etc/mysqldump.conf /etc/mariadb-*.conf)
for f in /etc/httpd/conf.d/*.conf
do
    if rpm -qf "$f" > /dev/null 2>&1
    then cp -a "$f" "$B/reference/"
    else paths+=("$f")
    fi
done
for p in "${paths[@]}"
do
    [[ -e $p ]] || continue
    mkdir -p "$B/files$(dirname "$p")"
    cp -a --reflink=auto "$p" "$B/files$(dirname "$p")/" || fail "copy of $p failed"
done

echo "== backup of $(hostname) done: $(tr '\n' ' ' < "$B/manifest")"
du -sh "$B" 2>/dev/null
