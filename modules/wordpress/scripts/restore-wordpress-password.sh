#!/bin/bash

#### Call with:
## bash /usr/local/share/srvctl/modules/wordpress/scripts/restore-wordpress-password.sh

if [[ ! -f /var/www/html/.admin ]]
then
	echo "File for password not found. /var/www/html/.admin"
  	exit
fi

PASSWORD_FILE_CONTENT="$(cat /var/www/html/.admin)"
PASSWORD="$(echo -e "${PASSWORD_FILE_CONTENT}" | tr -d '[:space:]')"

echo "Setting password to $PASSWORD"
HASH="$(echo $PASSWORD | md5sum | tr -d ' -')"
echo $HASH


SC_MARIADB_DUMP_CONF=/etc/mysqldump.conf
SC_MDA=''

#function check_mariadb_connection {


    if [[ -f $SC_MARIADB_DUMP_CONF ]]
    then
        echo "Found $SC_MARIADB_DUMP_CONF"
        SC_MDA="--defaults-file=$SC_MARIADB_DUMP_CONF"
    else
        echo "Mariadb $SC_MARIADB_DUMP_CONF not found"
        SC_MDA="-u root -p"
    fi
    
    if /usr/bin/mysql "$SC_MDA" -e status 2> /dev/null
    then
        echo ".. mysql connected"
    else
        echo "CONNECTION FAILED. /usr/bin/mysql $SC_MDA -e status"
        exit
    fi

#}

echo "/usr/bin/mysql $SC_MDA -e show databases;"

if /usr/bin/mysql "$SC_MDA" -e 'show databases;'
then
    echo "OK"
else
    echo "COMMAND FAILED"
    exit
fi

if [[ ! $1 ]]
then
	echo "Use The database name as first argument."
    exit
fi

if /usr/bin/mysql "$SC_MDA" -e "use $1; 'show tables';"
then
    echo "OK"
else
    echo "COMMAND FAILED"
    exit
fi

if /usr/bin/mysql "$SC_MDA" -e "use $1; select * from wp_users;"
then
    echo "OK"
else
    echo "COMMAND FAILED"
    exit
fi

echo "/usr/bin/mysql $SC_MDA -e use $1; update wp_users set user_pass= MD5('$PASSWORD') where user_nicename = 'admin'"

if /usr/bin/mysql "$SC_MDA" -e "use $1; update wp_users set user_pass= MD5('$PASSWORD') where user_nicename = 'admin'"
then
    echo "OK - HASH changed. New password: $PASSWORD"
else
    echo "COMMAND FAILED"
    exit
fi

if /usr/bin/mysql "$SC_MDA" -e "use $1; select * from wp_users;"
then
    echo "OK"
else
    echo "COMMAND FAILED"
    exit
fi