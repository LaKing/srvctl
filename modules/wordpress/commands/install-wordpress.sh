#!/bin/bash

## @@@ install-wordpress
## @en Run scripts that install wordpress and it's basic dependencies.
## &en Install the wordpress dependencies.
## &en

root_only

###
###        install-wordpress command
###
###        Runs as root inside a VE container (the module is active in
###        every non-mail.* container); recreate-ve.sh also invokes it
###        over ssh as 'sc install-wordpress' when rebuilding a
###        wordpress-type container. Turns the fresh container into a
###        self-contained WordPress microsite:
###
###          - installs php, php-mysqlnd and the Fedora wordpress RPM
###          - writes the permalink and reverse-proxy-logging apache
###            configs, removes the RPM's /etc/httpd/conf.d/wordpress.conf
###          - downloads the latest upstream WordPress into /var/www/html
###          - creates the <first-hostname-label>_wp database via the
###            mariadb module
###          - generates wp-config.php (fresh DB credentials and salts)
###            plus a one-shot wp-install.php, and runs the headless
###            install: site title $HOSTNAME, user admin, password from
###            get_password
###          - saves that password to /var/www/html/.admin (mode 000, the
###            read contract of scripts/restore-wordpress-password.sh)
###            and enables httpd
###
###        recreate-ve.sh rsyncs /var/www/html/wp-content, wp-config.php
###        and /var/lib/mysql out of the temporary container — these
###        paths are an API and must not move.
###

## FIXME(v4): low — no '[[ $SRVCTL ]] || exit 10' guard: run directly with
## plain bash the srvctl helpers fail as command-not-found, yet the raw
## cat/chown lines still execute, clobbering /etc/httpd/conf.d/* and
## wp-config.php with empty credentials.

## the php version pin (8.0.11) is retired; current Fedora php is installed
sc_install php #-8.0.11
sc_install php-mysqlnd
## the Fedora wordpress RPM mostly pulls in dependencies: its apache config
## is removed below and its tree is shadowed by the upstream zip copied
## over /var/www/html
sc_install wordpress


## mod_rewrite front controller, so WordPress pretty permalinks resolve
msg "Adding wp-permalink configuration to apache"
cat > /etc/httpd/conf.d/wp-permalink.conf << EOF
## srvctl generated
<Directory /var/www/html/>
 <IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase /
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule . /index.php [L]
 </IfModule>
</Directory>
EOF

## TLS is terminated by the host reverse proxy, so log the real client
## address from X-Forwarded-For; note this redefines the stock 'combined'
## LogFormat for the whole apache instance
msg "Set up logging behind a reverse proxy"
cat > /etc/httpd/conf.d/logging-behind-reverse-proxy.conf << EOF
## srvctl generated
        <IfModule log_config_module>

            ### Custom log redefinition
            ## - with extra host header
            # LogFormat "%{X-Forwarded-For}i %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %h %D \"%{Host}i\"" combined
            ## - As close as possible
            LogFormat "%{X-Forwarded-For}i %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined

        </IfModule>
EOF

msg "Disable httpd systemwide wordpress configuration"
if [[ -f /etc/httpd/conf.d/wordpress.conf ]]
then
    rm -fr /etc/httpd/conf.d/wordpress.conf
fi

## webroot; also the base path baked into wp-install.php below
dir=/var/www/html
## database name: first hostname label + '_wp' (add_mariadb_db re-sanitizes
## this and reassigns the global — see below)
db_name=$(echo "$HOSTNAME" | cut -f1 -d"." )'_wp'

msg "Downloading and installing latest wordpress from source"
wd=/root
## FIXME(v4): medium — 'run' prints its colored banner on stdout, so the
## banner bytes are prepended inside latest.zip (unzip tolerates them as
## junk); and a curl failure neither warns nor aborts, so the script
## continues and reports success over an empty webroot.
run curl https://wordpress.org/latest.zip > "$wd"/latest.zip
## FIXME(v4): low — unzip without -o: leftovers of an aborted earlier run
## make unzip prompt for overwrite with stdout redirected into the log
## (appears to hang on a tty, EOF errors otherwise).
run unzip "$wd"/latest.zip -d "$wd" >> "$wd"/unzip.log
## overlay the upstream tree onto the webroot, then clean up the transients
run cp -u -f -r "$wd"/wordpress/* /var/www/html
run rm -rf "$wd"/latest.zip
run rm -rf "$wd"/wordpress
run rm -rf "$wd"/unzip.log
run chown -R apache:apache /var/www/html

## mariadb module: install/enable mariadb, then create database + user and
## save the credentials to /etc/mariadb-<db>.conf
setup_mariadb
## FIXME(v4): low — implicit cross-module contract: add_mariadb_db
## reassigns this caller's global db_name to the sanitized value ('.'/'-'
## become '_') and sets the db_usr/db_pwd globals consumed by wp-config
## below; hyphenated hostnames only work because of that reassignment.
add_mariadb_db "$db_name"

msg "Wordpress using Mariadb DB_NAME $db_name"

## sets the global $randomstr — one 32-char [a-zA-Z0-9] string per call,
## consumed by the wp-config keys and salts below
function get_randomstr {
    randomstr=$( < /dev/urandom  tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
}


## generate wp-config.php (path rsync'd by recreate-ve.sh)
{
    echo "<?php"
    echo "// srvctl wordpress wp-config"
    echo "define('DB_NAME', '$db_name');"
    ## from add_mariadb_db
    # shellcheck disable=SC2154
    echo "define('DB_USER', '$db_usr');"
    ## from add_mariadb_db
    # shellcheck disable=SC2154
    echo "define('DB_PASSWORD', '$db_pwd');"
    echo "define('DB_HOST', 'localhost');"
    echo "define('DB_CHARSET', 'utf8');"
    echo "define('DB_COLLATE', '');"
    echo ""

    ## random keys and salts
    get_randomstr
    echo "define('AUTH_KEY',         '$randomstr');"
    get_randomstr
    echo "define('SECURE_AUTH_KEY',  '$randomstr');"
    get_randomstr
    echo "define('LOGGED_IN_KEY',    '$randomstr');"
    get_randomstr
    echo "define('NONCE_KEY',        '$randomstr');"
    get_randomstr
    echo "define('AUTH_SALT',        '$randomstr');"
    get_randomstr
    echo "define('SECURE_AUTH_SALT', '$randomstr');"
    get_randomstr
    echo "define('LOGGED_IN_SALT',   '$randomstr');"
    get_randomstr
    echo "define('NONCE_SALT',       '$randomstr');"

    echo ""
    echo '$'"table_prefix  = 'wp_';"
    echo ""

    echo "define('WPLANG', '');"
    echo "define('WP_DEBUG', false);"
    echo ""

    ## FIXME(v4): medium — FORCE_SSL_ADMIN with no X-Forwarded-Proto
    ## handling: behind the TLS-terminating proxy the backend sees plain
    ## http, so /wp-admin over https can redirect-loop (see the WP_SITEURL
    ## marker below).
    echo "define('FORCE_SSL_ADMIN', true);"
    echo ""

    echo "if ( !defined('ABSPATH') ) define('ABSPATH', dirname(__FILE__) . '/');"
    echo "require_once(ABSPATH . 'wp-settings.php');"
    echo ""


} > /var/www/html/wp-config.php

## create an installer to install without web dialog
password="$(get_password)"

{
    echo "<?php"
    echo "// srvctl wordpress wp-install"
    ## FIXME(v4): medium — $URI is defined nowhere in the repo, so
    ## WP_SITEURL becomes http://$HOSTNAME/ (scheme http) while wp-config
    ## forces SSL for /wp-admin and the final message advertises https;
    ## front-end links get generated as http.
    echo "define('WP_SITEURL', 'http://$HOSTNAME/$URI');"
    echo "define('WP_INSTALLING',true);"
    echo "require_once('$dir/wp-config.php');"
    echo "require_once('$dir/wp-settings.php');"
    echo "require_once('$dir/wp-admin/includes/upgrade.php');"
    ## FIXME(v4): low — wp-includes/wp-db.php is a deprecated stub since
    ## WordPress 6.1, scheduled for removal upstream.
    echo "require_once('$dir/wp-includes/wp-db.php');"
    ## headless install: blog title $HOSTNAME, user admin, email
    ## root@localhost, public, empty deprecated arg, generated password
    echo "wp_install('$HOSTNAME','admin','root@localhost',1,'','$password');"

} > "$dir"/wp-install.php

msg "Running wp-install.php script"
if php -f "$dir"/wp-install.php
then
    msg "OK"
else
    ## FIXME(v4): low — reports only php's bare numeric exit code, and the
    ## script continues to the success message regardless.
    err $?
fi


## persist the admin password for scripts/restore-wordpress-password.sh
## (a mode-000 .admin file in the webroot is that script's read contract)
echo "$password" > "$dir/.admin"
chmod 000 "$dir/.admin"

## drop the distro default page so index.php serves /
rm -fr "$dir"/index.html

## operators copy the admin password from this line — format is an interface
msg "Wordpress @ https://$HOSTNAME/wp-admin admin:$password"


## enable + restart httpd, symlink the unit into /etc/srvctl/system
add_service httpd

## FIXME(v4): medium — wp-install.php (plaintext admin password in PHP
## source) is never deleted from the webroot, and this recursive chown
## hands .admin and wp-config.php to the apache uid after the chmod 000
## above (the owner can simply re-chmod): DB and admin credentials remain
## exposed to the web workload.
chown -R apache:apache /var/www/html
