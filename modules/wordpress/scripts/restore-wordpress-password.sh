#!/bin/bash

###
###        restore-wordpress-password.sh — standalone maintenance script
###
###        Not a srvctl command: no help metadata, no srvctl helpers; run
###        manually inside a wordpress container with the database name as
###        first argument. Re-applies the admin password that
###        install-wordpress saved in /var/www/html/.admin by writing an
###        MD5 hash into the wp_users table (WordPress upgrades legacy MD5
###        hashes to phpass on the next successful login).
###
###        Status: non-functional end to end — the table sanity check
###        always fails (see the high FIXME markers below), so the UPDATE
###        is never reached. The v4 notes fold this into a real command.
###

#### Call with:
## bash /usr/local/share/srvctl/modules/wordpress/scripts/restore-wordpress-password.sh

## FIXME(v4): medium — every failure branch in this script is a bare
## 'exit' right after a successful echo, so it exits 0 on failure and
## callers cannot detect that nothing was restored.
if [[ ! -f /var/www/html/.admin ]]
then
    echo "File for password not found. /var/www/html/.admin"
    exit
fi

PASSWORD_FILE_CONTENT="$(cat /var/www/html/.admin)"
PASSWORD="$(echo -e "${PASSWORD_FILE_CONTENT}" | tr -d '[:space:]')"

## FIXME(v4): low — announces the plaintext password on stdout/logs; HASH
## is dead code and wrong anyway (echo appends a newline before md5sum).
echo "Setting password to $PASSWORD"
HASH="$(echo "$PASSWORD" | md5sum | tr -d ' -')"
echo "$HASH"


## pick mysql root authentication: the mariadb module's dump defaults-file
## when present, an interactive fallback otherwise
SC_MARIADB_DUMP_CONF=/etc/mysqldump.conf
SC_MDA=''

if [[ -f $SC_MARIADB_DUMP_CONF ]]
then
    echo "Found $SC_MARIADB_DUMP_CONF"
    SC_MDA="--defaults-file=$SC_MARIADB_DUMP_CONF"
else
    echo "Mariadb $SC_MARIADB_DUMP_CONF not found"
    ## FIXME(v4): high — "$SC_MDA" is expanded quoted as a single argument
    ## in every mysql call below, so this multi-word fallback becomes one
    ## unknown-option token (and -p would prompt interactively anyway):
    ## without the defaults-file no mysql call can ever succeed.
    SC_MDA="-u root -p"
fi

if /usr/bin/mysql "$SC_MDA" -e status 2> /dev/null
then
    echo ".. mysql connected"
else
    echo "CONNECTION FAILED. /usr/bin/mysql $SC_MDA -e status"
    exit
fi

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

## FIXME(v4): high — the quoted 'show tables' is sent to MySQL as a bare
## string-literal statement, a guaranteed 1064 syntax error: every run
## takes the failure branch here, so the password UPDATE below is
## unreachable and the script can never restore anything.
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

## MD5 on purpose: WordPress rehashes legacy MD5 passwords at next login
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
