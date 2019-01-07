#!/bin/bash

## @@@ install-wordpress
## @en Run scripts that install wordpress and it's basic dependencies.
## &en Install the wordpress dependencies.
## &en

root_only

sc_install wordpress
sc_install php

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

if [[ -f /etc/httpd/conf.d/wordpress.conf ]]
then
    rm -fr /etc/httpd/conf.d/wordpress.conf
fi

dir=/var/www/html
db_name=$(echo "$HOSTNAME" | cut -f1 -d"." )'_wp'


wd=/root
run curl https://wordpress.org/latest.zip > "$wd"/latest.zip
run unzip "$wd"/latest.zip -d "$wd" >> "$wd"/unzip.log
run cp -u -f -r "$wd"/wordpress/* /var/www/html
run rm -rf "$wd"/latest.zip
run rm -rf "$wd"/wordpress
run rm -rf "$wd"/unzip.log
run chown -R apache:apache /var/www/html

setup_mariadb
add_mariadb_db "$db_name"

msg "Wordpress using Mariadb DB_NAME $db_name"

function  get_randomstr {
    randomstr=$( < /dev/urandom  tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
}


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
    
    ## random key's and salt's
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
    echo "define('WP_SITEURL', 'http://$HOSTNAME/$URI');"
    echo "define('WP_INSTALLING',true);"
    #echo "define('ABSPATH','/var/www/html/"$URI"/');"
    echo "require_once('$dir/wp-config.php');"
    echo "require_once('$dir/wp-settings.php');"
    echo "require_once('$dir/wp-admin/includes/upgrade.php');"
    echo "require_once('$dir/wp-includes/wp-db.php');"
    echo "wp_install('$HOSTNAME','admin','root@localhost',1,'','$password');"
    
} > "$dir"/wp-install.php

php -f "$dir"/wp-install.php

echo "$password" > "$dir/.admin"
chmod 000 "$dir/.admin"

rm -fr "$dir"/index.html

msg "Wordpress instance installed. https://$HOSTNAME/wp-admin admin:$password"


add_service httpd
