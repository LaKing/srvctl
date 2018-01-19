#!/bin/bash

## @@@ wp-install
## @en Run scripts that install wordpress and it's basic dependencies.
## &en Install the wordpress dependencies.
## &en

root_only

run dnf -y install wordpress
run dnf -y install mariadb-server

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

run systemctl enable mariadb
run systemctl restart mariadb
run systemctl status mariadb --no-pager

run systemctl enable httpd
run systemctl restart httpd
run systemctl status httpd --no-pager
