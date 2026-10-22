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
echo "== restore $(hostname): kind=$kind db=$dbs"

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
dnf -y install --skip-unavailable --skip-broken "${pkgs[@]}" "${oldpkgs[@]}" || fail "package install failed"

## files over the fresh tree, owners and modes as they were. Path by path, so
## only the saved trees themselves get their old attributes, never / or /var.
[[ -f $B/paths ]] || fail "no $B/paths: backup made by an older rebuild-ve, roll back and rebuild"
while read -r p
do
    cp -a --reflink=auto "$B/files$p" "$(dirname "$p")/" || fail "restore of $p failed"
done < "$B/paths"

## databases: dumps carry CREATE DATABASE; grants recreate the accounts. A
## rerun imports again: the dumps drop and recreate their tables.
if [[ -n ${dbs// /} ]]
then
    sql="$(command -v mariadb || command -v mysql)"
    systemctl enable --now mariadb || fail "mariadb does not start"
    for db in $dbs
    do
        "$sql" < "$B/db/$db.sql" || fail "import of $db failed"
    done
    "$sql" < "$B/db/grants.sql" || fail "grants import failed"
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

[[ $kind != static ]] && { systemctl enable --now php-fpm || fail "php-fpm does not start"; }
systemctl enable httpd
systemctl restart httpd || fail "httpd does not start"

## the WordPress database schema upgrade, as the dashboard would run it
if [[ $kind == wordpress ]]
then
    curl -s -o /dev/null -w '== wp upgrade.php: HTTP %{http_code}\n' -H "Host: $(hostname)" 'http://127.0.0.1/wp-admin/upgrade.php?step=1'
fi

grep -q '^mongo=dumped' "$B/manifest" && echo "== NOTE: MongoDB was in use and is NOT restored (no Fedora package): dump in $B/mongo.archive.gz, data in exrootfs"
chmod 700 "$B"
echo "== restore of $(hostname) done"
