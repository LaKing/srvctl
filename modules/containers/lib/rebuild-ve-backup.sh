#!/bin/bash

## Runs INSIDE the old container, as its root: 'ssh VE bash -s < this', from
## rebuild_ve_backup (libs/rebuildlib.sh). Collects what rebuild-ve-restore.sh
## puts back on the fresh rootfs, into /srv/backup:
##
##   manifest       kind=wordpress|php|static, os=, db=<databases>, localunits=, node=<major>, nodessl=
##   files/, paths  the restored trees, copied with cp -a --parents so the
##                  in-container numeric owners survive (the host copies them on
##                  with cp -a, the new container's first start uid-shifts them);
##                  paths lists them, the restore copies path by path
##   db/<name>.sql  one logical dump per database; db/grants.sql the accounts;
##                  db/root.hash the old root@localhost password hash, if any
##   mongo.archive.gz      mongodump of a MongoDB, if any: restored when the
##                  server comes back from a third-party repository (Fedora has none)
##   repos/         hand-made dnf repository files and their keys
##   passwd group shadow   the uid 1000..59999 users and groups, and the local units' ones
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

## local units the snapshot let through (target in /srv/<dir> or /home): the
## unit links themselves and the whole /srv/<dir> they point into. Stopped
## before anything is saved, so the dumps and files are one moment of the app
## (a job board taking payments, seen on r2: vendeglatosmunkak.hu); here and
## not in the snapshot, because a resumed backup boots the old container again.
## A unit file old srvctl wrote into /etc/systemd/system (project.service of a
## codepad-project, seen on r2: chernobyl.d250.hu) counts when its working
## directory is in /srv or /home; its User=, PIDFile= directory and OnFailure=
## units come along (codepad, /var/codepad-project, notify.service).
localunits=()
localpaths=()
localusers=()
for w in /etc/systemd/system/multi-user.target.wants/*
do
    t="$(readlink "$w")" || continue
    wd=''
    case "$t" in
        ## /srv/<C>/rootfs/...: a packaged unit linked with its host path by old srvctl
        /srv/*/rootfs/*) continue ;;
        /srv/?*/* | /home/?*/*) ;;
        /etc/systemd/system/*)
            [[ -f $t && ! -L $t ]] || continue
            wd="$(sed -n 's/^WorkingDirectory=//p' "$t" | head -n 1)"
            [[ $wd == /srv/?* || $wd == /home/?* ]] || continue
            ;;
        *) continue ;;
    esac
    u="${w##*/}" && localunits+=("$u") && localpaths+=("$w")
    [[ -e /etc/systemd/system/$u || -L /etc/systemd/system/$u ]] && localpaths+=("/etc/systemd/system/$u")
    for d in "$t" "$wd"
    do
        [[ $d == /srv/?* ]] && d="${d#/srv/}" && localpaths+=("/srv/${d%%/*}")
    done
    [[ -f $t ]] || continue
    usr="$(sed -n 's/^User=//p' "$t" | head -n 1)"
    [[ -n $usr && $usr != root ]] && localusers+=("$usr")
    pid="$(sed -n 's/^PIDFile=//p' "$t" | head -n 1 | tr -s /)"
    [[ $pid == /var/?*/* && $pid != /var/run/* ]] && localpaths+=("$(dirname "$pid")")
    # shellcheck disable=SC2013 # OnFailure= takes space-separated unit names
    for o in $(sed -n 's/^OnFailure=//p' "$t")
    do
        [[ -f /etc/systemd/system/$o && ! -L /etc/systemd/system/$o ]] && localpaths+=("/etc/systemd/system/$o")
    done
done
echo "localunits=${localunits[*]}" >> "$B/manifest"
## the old node's major and OpenSSL: the restore keeps their behaviour on a newer node
command -v node > /dev/null && node -p '"node=" + process.versions.node.split(".")[0] + "\nnodessl=" + process.versions.openssl' >> "$B/manifest"
((${#localunits[@]})) && { systemctl stop "${localunits[@]}" || fail "local units do not stop: ${localunits[*]}"; }

rpm -qa --qf '%{NAME}\n' | sort > "$B/reference/packages.txt"
## third-party dnf repositories set up by hand (MongoDB's, seen on r2:
## audreyshome.hu) with their local keys: without them the old package list
## cannot be installed. rpm-owned ones (rpmfusion) come back through their
## release package in the restore.
mkdir -p "$B/repos/keys"
## keys imported straight into the rpm database have no file (zerotier's,
## seen on r2: vendeglatosmunkak.hu); without them dnf drops the whole transaction
rpm -q gpg-pubkey > /dev/null 2>&1 && rpm -q gpg-pubkey --qf '%{DESCRIPTION}\n' > "$B/repos/rpm-keys.asc"
for f in /etc/yum.repos.d/*.repo /etc/pki/rpm-gpg/*
do
    [[ -f $f ]] || continue
    rpm -qf "$f" > /dev/null 2>&1 && continue
    ## Fedora's own repositories nobody owned (fedora-modular.repo on Fedora 35) are not carried
    case "$f" in *.repo) grep -q 'fedoraproject\.org' "$f" || cp -a "$f" "$B/repos/" ;; *) cp -a "$f" "$B/repos/keys/" ;; esac
done
systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' > "$B/reference/units.txt"
cp -a /etc/php.ini /root/.my.cnf /etc/mysqldump.conf "$B/reference/" 2>/dev/null
## a locally changed httpd.conf (a moved DocumentRoot) is offered to the restore,
## which takes it only if the new httpd accepts it
rpm -Vf /etc/httpd/conf/httpd.conf 2> /dev/null | grep -qE '^..5.* /etc/httpd/conf/httpd.conf$' && cp -a /etc/httpd/conf/httpd.conf "$B/reference/httpd.conf.changed"

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
    ## server cannot run its routines or events either (it may also have disabled
    ## the event scheduler, 1577, seen on r2: konok.hu), so the dump is retried
    ## without them rather than upgrading the old datadir.
    ## Tables this server cannot open (InnoDB files copied in owned by root:
    ## 1146/1932, seen on r2 eana.hu; a lost tablespace: 1030/194, seen on
    ## mosolygoalmapecs.hu, a Wordfence scratch table) are probed first. All
    ## broken: the database is skipped, no application can be using it. Some
    ## broken: dumped without them. Their files stay in exrootfs either way.
    dumped=''
    for db in $dbs
    do
        mapfile -t tables < <(mysql "${my[@]}" -N -e "select table_name from information_schema.tables where table_schema='$db' and table_type='BASE TABLE'")
        skip=()
        for t in "${tables[@]}"
        do
            mysql "${my[@]}" -e "select 1 from \`$db\`.\`$t\` limit 0" > /dev/null 2>&1 || skip+=("$t")
        done
        if ((${#skip[@]} > 0 && ${#skip[@]} == ${#tables[@]}))
        then
            echo "== $db: SKIPPED, none of its ${#tables[@]} tables can be opened on the old server either"
            echo "brokendb=$db" >> "$B/manifest"
            continue
        fi
        ignore=()
        for t in "${skip[@]}"
        do
            echo "== $db.$t: SKIPPED, the old server cannot open this table either"
            echo "brokentable=$db.$t" >> "$B/manifest"
            ignore+=("--ignore-table=$db.$t")
        done
        if ! mysqldump "${my[@]}" --single-transaction --routines --events --triggers "${ignore[@]}" --databases "$db" > "$B/db/$db.sql" 2> "$B/db/$db.err"
        then
            grep -qE 'mysql\.(proc|event)|mysql_upgrade|event scheduler is disabled' "$B/db/$db.err" || { cat "$B/db/$db.err" >&2; fail "dump of $db failed"; }
            echo "== $db: system tables older than the server, dumping without routines and events (they could not run here either)"
            mysqldump "${my[@]}" --single-transaction --triggers "${ignore[@]}" --databases "$db" > "$B/db/$db.sql" || fail "dump of $db failed"
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
    ## for its socket settings: the restore keeps those on the new server
    [[ -f /etc/mongod.conf ]] && cp -a /etc/mongod.conf "$B/reference/"
fi

## users and groups of the site owners
## plus the accounts the local units run as (codepad, uid 804 or 104), with their primary groups
awk -F: -v extra=" ${localusers[*]} " '($3 >= 1000 && $3 < 60000) || index(extra, " " $1 " ")' /etc/passwd > "$B/passwd"
awk -F: 'NR == FNR {g[$4] = 1; next} ($3 >= 1000 && $3 < 60000) || ($3 in g)' "$B/passwd" /etc/group > "$B/group"
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
## All of /var/www, not only html: a docroot can be elsewhere in it, through a
## symlink (/var/www/laravel -> html, seen on r2: app.printmagus.com).
paths=(/var/www /home /var/spool/cron /etc/mariadb-*.conf)
paths+=("${localpaths[@]}")
## The rest of /srv too: data and copies kept there by hand stayed behind in exrootfs
## (seen on r2: eana.hu /srv/uploads, flatchooser.carco.hu /srv/flatchooser).
## Not this backup, nor those of earlier attempts.
for p in /srv/*
do
    [[ -e $p && $p != "$B" && $p != "$B".prev-* && " ${paths[*]} " != *" $p "* ]] && paths+=("$p")
done
va="$(rpm -Va 2> /dev/null)"
awk '$2 == "c" && $1 ~ /5/ {print $3}' <<< "$va" > "$B/reference/modified-configs.txt"
## packaged httpd confs deleted by hand: welcome.conf gone is what lets a bare
## docroot list its files (seen on bp: mirror.d250.hu); the new tree brings it back
awk '$1 == "missing" && $NF ~ /^\/etc\/httpd\/conf\.d\/[^/]+\.conf$/ {print $NF}' <<< "$va" > "$B/reference/removed-httpd-confs.txt"
for f in /etc/httpd/conf.d/*.conf /etc/phpMyAdmin/*
do
    [[ -f $f ]] || continue
    if ! rpm -qf "$f" > /dev/null 2>&1 || grep -qxF "$f" "$B/reference/modified-configs.txt"
    then paths+=("$f")
    else cp -a "$f" "$B/reference/"
    fi
done
## What those confs point at: a hand-made tree under /etc/httpd, and AuthUserFile and
## friends anywhere. Without them every login answers 500 "Could not open password
## file" (seen on r2: konok.hu /etc/httpd/catalog-passwords). An unowned dir goes whole.
## Not conf.modules.d: an old module conf can name a module the new httpd lacks.
while read -r f
do
    [[ $f == /etc/httpd/conf.modules.d/* || " ${paths[*]} " == *" $f "* ]] && continue
    for p in "${paths[@]}"; do [[ $f == "$p"/* ]] && continue 2; done
    rpm -qf "$f" > /dev/null 2>&1 || paths+=("$f")
done < <(find /etc/httpd -mindepth 1 \( -type d -o -type f \) 2> /dev/null | sort
    grep -rhoiE '^\s*Auth(DBM)?(User|Group)File\s+"?/[^" ]+' /etc/httpd 2> /dev/null | awk '{gsub(/"/, "", $2); print $2}' | grep -vE '^/(var/www|home|srv)/' | sort -u)
## mail: the base image brings srvctl's main.cf, but a master.cf opened by hand
## (submission and submissions, seen on r2: mail.colorsound.hu) and hand-made
## lookup tables are the container's own. The .db files are rebuilt by postmap.
for f in /etc/postfix/*
do
    [[ -f $f && $f != /etc/postfix/main.cf* && $f != *.db && $f != *.lmdb && $f != *.bak ]] || continue
    if ! rpm -qf "$f" > /dev/null 2>&1 || grep -qxF "$f" "$B/reference/modified-configs.txt"
    then paths+=("$f")
    fi
done
## the protocols the old dovecot served (2.4 serves no POP3 by default)
command -v doveconf > /dev/null && doveconf -h protocols > "$B/reference/dovecot-protocols.txt" 2> /dev/null
## main.cf settings added by hand (virtual_alias_maps, seen on r2: mail.instant-fogas.com)
command -v postconf > /dev/null && postconf -n > "$B/reference/postconf-n.txt" 2> /dev/null
## the TLS pairs mail clients accepted once: a fresh self-signed one asks every client again
for f in /etc/pki/dovecot/certs/dovecot.pem /etc/pki/dovecot/private/dovecot.pem /etc/pki/tls/certs/postfix.pem /etc/pki/tls/private/postfix.key
do
    [[ -f $f ]] && paths+=("$f")
done
## the zerotier node identity and its networks: a new identity waits for authorization again
[[ -d /var/lib/zerotier-one ]] && paths+=(/var/lib/zerotier-one)
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
