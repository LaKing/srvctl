#!/bin/bash

## Runs INSIDE the old container, as its root: 'ssh VE bash -s < this', from
## rebuild_ve_backup (libs/rebuildlib.sh). Collects what rebuild-ve-restore.sh
## puts back on the fresh rootfs, into /srv/backup:
##
##   manifest       kind=wordpress|php|static, os=, db=<databases>
##   files/, paths  the restored trees, copied with cp -a --parents so the
##                  in-container numeric owners survive (the host copies them on
##                  with cp -a, the new container's first start uid-shifts them);
##                  paths lists them, the restore copies path by path
##   db/<name>.sql  one logical dump per database; db/grants.sql the accounts;
##                  db/root.hash the old root@localhost password hash, if any
##   mongo.archive.gz      mongodump of a MongoDB, if any: kept, never restored
##                  (Fedora ships no MongoDB server)
##   passwd group shadow   the uid 1000..59999 users and groups
##   reference/     packages, enabled units, php.ini, rpm-owned httpd configs,
##                  modified-configs.txt (every changed rpm config file), the old
##                  root database credentials: for reading, never restored
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
cp -a /etc/php.ini /root/.my.cnf /etc/mysqldump.conf "$B/reference/" 2>/dev/null

## database: every user database as its own dump, plus the accounts
dbs=''
## a datadir left behind after the server package was removed (seen on r2:
## severnaya-samoyed.hu) cannot be dumped and serves nothing: noted, kept in exrootfs
dbserver=false
for bin in /usr/libexec/mariadbd /usr/libexec/mysqld /usr/sbin/mariadbd /usr/sbin/mysqld
do
    [[ -x $bin ]] && dbserver=true
done
if [[ -d /var/lib/mysql/mysql ]] && ! $dbserver
then
    echo "== /var/lib/mysql exists but no database server is installed: not dumped, the files stay in exrootfs"
    echo "nodbserver=/var/lib/mysql" >> "$B/manifest"
fi
if [[ -d /var/lib/mysql/mysql ]] && $dbserver
then
    for unit in mariadb mysqld mysql
    do
        systemctl start "$unit" 2>/dev/null && break
    done
    my=()
    [[ -f /etc/mysqldump.conf ]] && my=(--defaults-file=/etc/mysqldump.conf)

    ## Root password set but not saved anywhere srvctl knows (seen on bp):
    ## restart without privilege checks, socket only. The documented MariaDB
    ## lost-root-password procedure; Fedora's mariadb.service passes
    ## MYSQLD_OPTS. Harmless here, the old container is stopped after backup.
    if ! mysql "${my[@]}" -e 'select 1' > /dev/null 2>&1
    then
        echo "== root has no database access: restarting $unit with --skip-grant-tables --skip-networking"
        systemctl stop "$unit"
        systemctl set-environment MYSQLD_OPTS="--skip-grant-tables --skip-networking"
        systemctl start "$unit"
        systemctl unset-environment MYSQLD_OPTS
        for _ in {1..30}
        do
            mysql "${my[@]}" -e 'select 1' > /dev/null 2>&1 && break
            sleep 1
        done
    fi
    mysql "${my[@]}" -e 'select 1' > /dev/null || fail "cannot connect to the database as root"

    ## '#'-names are datadir directories that SHOW DATABASES lists (#rocksdb of
    ## MyRocks, #mysql50#...), not databases (seen on bp: gwrinsulation.com)
    dbs="$(mysql "${my[@]}" -N -e 'show databases' | grep -vxE 'mysql|information_schema|performance_schema|sys|#.*' | tr '\n' ' ')"
    ## System tables older than the server (mysql_upgrade never ran, seen on bp:
    ## mysql.proc from 10.2 under 10.4) make --routines/--events fail. Such a
    ## server cannot run its routines or events either, so the dump is retried
    ## without them rather than upgrading the old datadir.
    ## A database whose tables this server cannot open (1146 or 1932, e.g. InnoDB files
    ## copied in owned by root, seen on r2: eana.hu) is skipped: no application
    ## can be using it. Its files stay in exrootfs.
    dumped=''
    for db in $dbs
    do
        if ! mysqldump "${my[@]}" --single-transaction --routines --events --triggers --databases "$db" > "$B/db/$db.sql" 2> "$B/db/$db.err"
        then
            if grep -qE "doesn't exist( in engine)? \((1146|1932)\)" "$B/db/$db.err"
            then
                echo "== $db: SKIPPED, its tables cannot be opened on the old server either: $(grep -m1 -o "Table '[^']*'" "$B/db/$db.err")"
                echo "brokendb=$db" >> "$B/manifest"
                rm -f "$B/db/$db.sql" "$B/db/$db.err"
                continue
            fi
            grep -qE 'mysql\.(proc|event)|mysql_upgrade' "$B/db/$db.err" || { cat "$B/db/$db.err" >&2; fail "dump of $db failed"; }
            echo "== $db: system tables older than the server, dumping without routines and events (they could not run here either)"
            mysqldump "${my[@]}" --single-transaction --triggers --databases "$db" > "$B/db/$db.sql" || fail "dump of $db failed"
            echo "noroutines=$db" >> "$B/manifest"
        fi
        rm -f "$B/db/$db.err"
        dumped+="$db "
    done
    dbs="$dumped"

    ## SHOW GRANTS carries the password hash. It is refused while grant tables
    ## are skipped, so all of them run in ONE session after FLUSH PRIVILEGES,
    ## which loads the tables but keeps that session's full access. Always
    ## flushed: a rerun finds the server still in that mode, root then gets in
    ## at once, and a normal root may flush anyway.
    ## sql_mode='' lets GRANT create the account on the new server
    ## (NO_AUTO_CREATE_USER is in its default mode).
    ## root@localhost is the new server's own (socket) account: its old password
    ## goes to root.hash and is added as an alternative by the restore. Other
    ## root accounts (127.0.0.1, ::1) are carried over like any other.
    accounts="$(mysql "${my[@]}" -N -e "select user, host from mysql.user where user not in ('', 'mysql', 'mariadb.sys', 'PUBLIC')")"
    grants=''
    if [[ -n $accounts ]]
    then
        grants="$(
            {
                echo "FLUSH PRIVILEGES;"
                while read -r u h
                do
                    echo "SHOW GRANTS FOR '$u'@'$h';"
                done <<< "$accounts"
            } | mysql "${my[@]}" -N
        )" || fail "grants export failed"
    fi
    rootre="TO [\`']root[\`']@[\`']localhost[\`']"
    grep -E "$rootre" <<< "$grants" | grep -oE "PASSWORD '\*[0-9A-F]{40}'" | head -n 1 | cut -d"'" -f2 > "$B/db/root.hash"
    grants="$(grep -vE "$rootre" <<< "$grants")"
    {
        echo "SET SESSION sql_mode='';"
        [[ -n $grants ]] && printf '%s;\n' "${grants//$'\n'/$';\n'}"
    } > "$B/db/grants.sql"
fi
echo "db=$dbs" >> "$B/manifest"

## MongoDB: dumped for the owner. mongodump retries until mongod answers.
if [[ -d /var/lib/mongo || -d /var/lib/mongodb ]] && command -v mongodump > /dev/null
then
    systemctl start mongod 2> /dev/null
    dumped=false
    for _ in {1..30}
    do
        mongodump --quiet --gzip --archive="$B/mongo.archive.gz" 2> "$B/mongo.err" && { dumped=true; break; }
        sleep 2
    done
    $dumped || { cat "$B/mongo.err" >&2; fail "mongodump failed"; }
    rm -f "$B/mongo.err"
    echo "mongo=dumped" >> "$B/manifest"
fi

## users and groups of the site owners
awk -F: '$3 >= 1000 && $3 < 60000' /etc/passwd > "$B/passwd"
awk -F: '$3 >= 1000 && $3 < 60000' /etc/group > "$B/group"
cut -d: -f1 "$B/passwd" | while read -r u
do
    grep "^$u:" /etc/shadow
done > "$B/shadow"

## files: the web root, homes, crontabs, the per-site db configs, the httpd
## configs that no package owns (site vhosts, srvctl's wordpress confs) and
## the rpm configs changed here in httpd conf.d and phpMyAdmin (an opened
## phpMyAdmin.conf, a config.inc.php). Other changed rpm configs (sshd_config,
## php.ini, srvctl's postfix) are only listed: old ones can break new services.
## Parent dirs are made with the source's mode and owner (umask 077 ones once
## reached / and /var through a whole-tree restore and broke every service).
## Not cp --parents: coreutils 9.3 (Fedora 39) fails it with "preserving
## permissions for .../var/www: No such file or directory" after a full copy.
paths=(/var/www/html /home /var/spool/cron /etc/mariadb-*.conf)
rpm -Va 2> /dev/null | awk '$2 == "c" && $1 ~ /5/ {print $3}' > "$B/reference/modified-configs.txt"
for f in /etc/httpd/conf.d/*.conf /etc/phpMyAdmin/*
do
    [[ -f $f ]] || continue
    if ! rpm -qf "$f" > /dev/null 2>&1 || grep -qxF "$f" "$B/reference/modified-configs.txt"
    then paths+=("$f")
    else cp -a "$f" "$B/reference/"
    fi
done
mkparents() { ## /abs/path/leaf: mirror its parent dirs under $B/files
    local d='' part
    local -a parts
    IFS=/ read -ra parts <<< "${1#/}"
    for part in "${parts[@]:0:${#parts[@]}-1}"
    do
        d+="/$part"
        [[ -d $B/files$d ]] && continue
        mkdir "$B/files$d" && chmod --reference="$d" "$B/files$d" && chown --reference="$d" "$B/files$d" || return 1
    done
}
for p in "${paths[@]}"
do
    [[ -e $p ]] || continue
    mkparents "$p" || fail "parent dirs of $p failed"
    cp -a --reflink=auto "$p" "$B/files$(dirname "$p")/" || fail "copy of $p failed"
    echo "$p" >> "$B/paths"
done

echo "== backup of ${HOSTNAME:-$(cat /etc/hostname)} done: $(tr '\n' ' ' < "$B/manifest")"
du -sh "$B" 2>/dev/null
