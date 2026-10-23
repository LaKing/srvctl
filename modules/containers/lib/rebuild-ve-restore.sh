#!/bin/bash

## Runs INSIDE the new container, as its root: 'ssh VE bash -s < this', from
## rebuild_ve_restore (libs/rebuildlib.sh). Puts back what
## rebuild-ve-backup.sh collected into /srv/backup (copied over by the host).
##
## Order: users and groups first (the copied files carry their numeric ids),
## packages, files, then the databases, then WordPress core and services.
## WordPress is restored with its OLD wp-config.php and database credentials:
## install-wordpress would create a new database, user and config instead.

set -u
B=/srv/backup

fail() {
    echo "RESTORE-ERROR: $*" >&2
    exit 1
}

[[ -f $B/manifest ]] || fail "no $B/manifest"
kind="$(sed -n 's/^kind=//p' "$B/manifest")"
dbs="$(sed -n 's/^db=//p' "$B/manifest")"
echo "== restore ${HOSTNAME:-$(cat /etc/hostname)}: kind=$kind db=$dbs"

## users and groups with their old ids. An id taken here by another account
## (codepad was 104 on mandrob.nete.hu) gets a new one, and an existing name
## keeps its id: umap/gmap then move the restored files to the id used here.
umap=() gmap=()
while IFS=: read -r name _ gid _
do
    if ! getent group "$name" > /dev/null
    then
        if getent group "$gid" > /dev/null; then groupadd "$name"; else groupadd -g "$gid" "$name"; fi
    fi
    n="$(getent group "$name" | cut -d: -f3)"
    [[ $n == "$gid" ]] || gmap+=("$gid:$n")
done < "$B/group"
while IFS=: read -r name _ uid gid gecos home shell
do
    if ! getent passwd "$name" > /dev/null
    then
        grp="$(awk -F: -v g="$gid" '$3 == g {print $1}' "$B/group")"
        if getent passwd "$uid" > /dev/null
        then useradd -M -g "${grp:-$gid}" -c "$gecos" -d "$home" -s "$shell" "$name"
        else useradd -M -u "$uid" -g "${grp:-$gid}" -c "$gecos" -d "$home" -s "$shell" "$name"
        fi
    fi
    n="$(id -u "$name")"
    [[ $n == "$uid" ]] || umap+=("$uid:$n")
done < "$B/passwd"
while IFS=: read -r name hash _
do
    usermod -p "$hash" "$name"
done < "$B/shadow"

## packages: the web stack, plus every package the old container had that
## still exists (phpMyAdmin, git, ...; dnf5 skips retired names like
## php-mcrypt, and with --skip-broken whatever would conflict).
## tar: the WordPress core download; the base image has none
pkgs=(httpd mod_ssl tar)
[[ $kind != static ]] && pkgs+=(php php-fpm php-mysqlnd php-gd php-xml php-mbstring php-intl php-zip php-opcache)
[[ -n ${dbs// /} ]] && pkgs+=(mariadb-server)
mapfile -t oldpkgs < <(grep -v '^gpg-pubkey$' "$B/reference/packages.txt")
## the old third-party repositories first, so their packages (MongoDB) resolve
## Fedora's own ones are not: the base image has them for its release, and an
## old fedora-modular.repo nobody owned has no repository for the new one
## (seen on r2: chernobyl.d250.hu, Fedora 35)
for f in "$B"/repos/*.repo
do
    [[ -f $f ]] && ! grep -q 'fedoraproject\.org' "$f" && cp -a "$f" /etc/yum.repos.d/
done
cp -a "$B"/repos/keys/* /etc/pki/rpm-gpg/ 2> /dev/null
[[ -s $B/repos/rpm-keys.asc ]] && rpm --import "$B/repos/rpm-keys.asc"
ver="$(sed -n 's/^VERSION_ID=//p' /etc/os-release)"
for r in free nonfree
do
    grep -qx "rpmfusion-$r-release" "$B/reference/packages.txt" || continue
    dnf -y install "https://mirrors.rpmfusion.org/$r/fedora/rpmfusion-$r-release-$ver.noarch.rpm" || fail "rpmfusion-$r-release failed"
done
## no i686: names only in the list, so 32-bit libraries come as dependencies of
## dependencies, and their older builds in 'fedora' conflict with the x86_64
## ones from 'updates' (mesa-dri-drivers, seen on r2: audreyshome.hu)
## the base image already has Fedora's node (nodejs22-bin, for srvctl):
## nodesource's 'nodejs' would conflict with it on /usr/bin/node, so the old
## container gets Fedora's build of the same line instead (seen on r2:
## vendeglatosmunkak.hu, nodesource 22.x)
excl=('*.i686')
rpm -qf /usr/bin/node > /dev/null 2>&1 && excl+=('nodejs')
dnf -y install --skip-unavailable --skip-broken "${excl[@]/#/--exclude=}" "${pkgs[@]}" "${oldpkgs[@]}" || fail "package install failed"

## files over the fresh tree, owners and modes as they were. Path by path, so
## only the saved trees themselves get their old attributes, never / or /var.
[[ -f $B/paths ]] || fail "no $B/paths: backup made by an older rebuild-ve, roll back and rebuild"
while read -r p
do
    cp -a --reflink=auto "$B/files$p" "$(dirname "$p")/" || fail "restore of $p failed"
done < "$B/paths"
for m in "${umap[@]}"
do
    echo "== files of uid ${m%%:*} follow their account to uid ${m#*:}"
    while read -r p; do chown -R -h --from="${m%%:*}" "${m#*:}" "$p"; done < "$B/paths"
done
for m in "${gmap[@]}"
do
    echo "== files of gid ${m%%:*} follow their group to gid ${m#*:}"
    while read -r p; do chown -R -h --from=":${m%%:*}" ":${m#*:}" "$p"; done < "$B/paths"
done

## a locally changed httpd.conf: taken over when the new httpd accepts it
if [[ -f $B/reference/httpd.conf.changed ]]
then
    cp -a /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.rebuild-default
    cp "$B/reference/httpd.conf.changed" /etc/httpd/conf/httpd.conf
    if httpd -t > /dev/null 2>&1
    then echo "== the old, locally changed httpd.conf is in use (new default: httpd.conf.rebuild-default)"
    else
        cp -a /etc/httpd/conf/httpd.conf.rebuild-default /etc/httpd/conf/httpd.conf
        echo "== WARNING: the old httpd.conf is not accepted by this httpd, the default stays: diff $B/reference/httpd.conf.changed"
    fi
fi

## databases: dumps carry CREATE DATABASE; grants recreate the accounts. A
## rerun imports again: the dumps drop and recreate their tables.
if [[ -n ${dbs// /} ]]
then
    sql="$(command -v mariadb || command -v mysql)"
    systemctl enable --now mariadb || fail "mariadb does not start"
    ## innodb_strict_mode=0: tables the old server accepted, but whose rows
    ## overflow in strict mode (408 varchar columns of a gallery plugin, seen on
    ## r2: konok.hu, ERROR 1118), are created with a warning, as they were there.
    for db in $dbs
    do
        { echo "SET SESSION innodb_strict_mode=0;"; cat "$B/db/$db.sql"; } | "$sql" || fail "import of $db failed"
    done
    "$sql" < "$B/db/grants.sql" || fail "grants import failed"
    ## old apps log in as root with its old password: keep that as an
    ## alternative, socket access for root stays
    if [[ -s $B/db/root.hash ]]
    then
        "$sql" -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING '$(cat "$B/db/root.hash")'" || fail "root password restore failed"
    fi
    "$sql" -e 'flush privileges'
fi

## WordPress: fresh core (wp-admin, wp-includes, root files) over the old
## site; wp-content and wp-config.php stay. New files get the owner of
## wp-content, so updates from the dashboard keep working as before.
if [[ $kind == wordpress ]]
then
    t="$(mktemp -d)"
    curl -fsSL https://wordpress.org/latest.tar.gz | tar xz -C "$t" || fail "wordpress download failed"
    rm -rf /var/www/html/wp-admin /var/www/html/wp-includes
    cp -a "$t"/wordpress/wp-admin "$t"/wordpress/wp-includes "$t"/wordpress/*.* /var/www/html/ || fail "wordpress core copy failed"
    chown -R --reference=/var/www/html/wp-content /var/www/html/wp-admin /var/www/html/wp-includes
    for f in "$t"/wordpress/*.*
    do
        chown --reference=/var/www/html/wp-content "/var/www/html/${f##*/}"
    done
    rm -rf "$t"
fi

## Dovecot 2.4 (Fedora 42 on) reads ~/mail and serves no POP3 by default; the
## 2.3 of the old containers read ~/Maildir, where postfix delivers
## (home_mailbox), and served POP3 (seen on r2: mail.mobilflower.hu)
if [[ -d /etc/dovecot/conf.d ]] && compgen -G '/home/*/Maildir' > /dev/null && doveconf -n 2> /dev/null | grep -qx 'mail_path = ~/mail'
then
    printf '%s\n' '## srvctl rebuild-ve: mailboxes and protocols as the old Dovecot 2.3 served them' \
        'mail_path = ~/Maildir' 'protocols {' '  pop3 = yes' '}' > /etc/dovecot/conf.d/90-srvctl-rebuild.conf
    doveconf -n > /dev/null || fail "dovecot does not accept conf.d/90-srvctl-rebuild.conf"
    echo "== dovecot: ~/Maildir and POP3, as before"
fi

## services the old container had enabled, where the unit exists here.
## NetworkManager would fight the srvctl-managed networkd setup.
while read -r u
do
    case "$u" in *@* | NetworkManager* | srvctl*) continue ;; esac
    systemctl cat "$u" > /dev/null 2>&1 && systemctl enable "$u" 2> /dev/null || echo "== not enabled, no such unit here: $u"
done < "$B/reference/units.txt"

## MongoDB, when its server came back with the old repository: before the
## local units, which are its usual clients
if grep -q '^mongo=dumped' "$B/manifest"
then
    ## an old server that does not install here (4.4 from the el8 repository,
    ## seen on r2: konyvesjatek.hu): the dump goes into the 7.0 series used
    ## elsewhere on the hosts; mongorestore reads dumps of older servers
    if ! command -v mongod > /dev/null
    then
        ## the old one stays on disk, switched off: nothing here installs from it
        grep -l 'repo.mongodb.org' /etc/yum.repos.d/*.repo 2> /dev/null | xargs -r sed -i 's/^enabled=1/enabled=0/'
        printf '%s\n' '[mongodb-org-7.0]' 'name=MongoDB Repository' 'baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/' \
            'gpgcheck=1' 'enabled=1' 'gpgkey=https://pgp.mongodb.com/server-7.0.asc' > /etc/yum.repos.d/mongodb-org-7.0.repo
        dnf -y install mongodb-org mongodb-database-tools && echo "== MongoDB server upgraded to the 7.0 series"
    fi
    if command -v mongod > /dev/null && command -v mongorestore > /dev/null
    then
        systemctl enable --now mongod || fail "mongod does not start"
        ## mongod takes a while to accept connections after systemd says started
        restored=false
        for _ in $(seq 30)
        do
            mongorestore --quiet --drop --gzip --archive="$B/mongo.archive.gz" 2> "$B/mongo.err" && { restored=true; break; }
            sleep 2
        done
        $restored || { cat "$B/mongo.err" >&2; fail "mongorestore failed"; }
        rm -f "$B/mongo.err"
        echo "== MongoDB restored"
    else
        echo "== NOTE: MongoDB was in use and is NOT restored (no server package here): dump in $B/mongo.archive.gz, data in exrootfs"
    fi
fi

## the local units (a Node app) came back with their tree: started now, the
## check tests them like httpd
# shellcheck disable=SC2013 # a space-separated list of unit names
for u in $(sed -n 's/^localunits=//p' "$B/manifest")
do
    ## setcap refuses a symlink, and /usr/bin/node is one here (alternatives ->
    ## node-22): a drop-in repeats the unit's ExecStartPre= lines with the real
    ## file (project.service of codepad-project, seen on r2: chernobyl.d250.hu)
    f="$(readlink -f "/etc/systemd/system/$u")"
    if [[ -f $f ]] && grep -q '^ExecStartPre=.*setcap' "$f"
    then
        mkdir -p "/etc/systemd/system/$u.d"
        {
            printf '%s\n' '## srvctl rebuild-ve: setcap on the real file, not the symlink' '[Service]' 'ExecStartPre='
            sed -n 's/^ExecStartPre=//p' "$f" | while read -r l
            do
                p="${l##* }"
                [[ $l == *setcap* && -L $p ]] && l="${l% *} $(readlink -f "$p")"
                printf 'ExecStartPre=%s\n' "$l"
            done
        } > "/etc/systemd/system/$u.d/srvctl-rebuild.conf"
    fi
    systemctl daemon-reload
    ## enabled only through the wants link: the unit name is unknown until linked
    systemctl cat "$u" > /dev/null 2>&1 || systemctl link "$(readlink "/etc/systemd/system/multi-user.target.wants/$u")"
    systemctl enable --now "$u" || fail "$u does not start"
done

[[ $kind != static ]] && { systemctl enable --now php-fpm || fail "php-fpm does not start"; }
## a local app may serve 80/443 itself with httpd disabled (seen on r2:
## api-test-flatchooser.carco.hu): httpd then stays as it was
if grep -qx httpd.service "$B/reference/units.txt" || ! grep -q '^localunits=.' "$B/manifest"
then
    systemctl enable httpd
    systemctl restart httpd || fail "httpd does not start"
else
    systemctl disable --now httpd 2> /dev/null
    echo "== httpd left disabled, as in the old container: a local app serves the site"
fi

## the WordPress database schema upgrade, as the dashboard would run it
if [[ $kind == wordpress ]]
then
    curl -s -o /dev/null -w '== wp upgrade.php: HTTP %{http_code}\n' -H "Host: ${HOSTNAME:-$(cat /etc/hostname)}" 'http://127.0.0.1/wp-admin/upgrade.php?step=1'
fi

chmod 700 "$B"
echo "== restore of ${HOSTNAME:-$(cat /etc/hostname)} done"
