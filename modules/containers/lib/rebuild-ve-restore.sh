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

## users and groups with their old ids; an existing name or id is kept as is
while IFS=: read -r name _ gid _
do
    getent group "$name" > /dev/null || getent group "$gid" > /dev/null || groupadd -g "$gid" "$name"
done < "$B/group"
while IFS=: read -r name _ uid gid gecos home shell
do
    getent passwd "$name" > /dev/null || getent passwd "$uid" > /dev/null || useradd -M -u "$uid" -g "$gid" -c "$gecos" -d "$home" -s "$shell" "$name"
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
cp -a "$B"/repos/*.repo /etc/yum.repos.d/ 2> /dev/null
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
