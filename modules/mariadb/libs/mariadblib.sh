#!/bin/bash

###
###        MariaDB related client-functions
###
###        Library helpers to install and secure a MariaDB/MySQL server,
###        create per-site databases with saved credentials, and dump all
###        databases — primarily meant to run inside containers. The module
###        ships no commands; consumers are the wordpress module
###        (setup_mariadb, add_mariadb_db) and the backupdb module
###        (backup_mariadb).
###
###        Globals contract (read by callers, must not become local):
###          SC_MDA        mysql root-auth arguments, set by
###                        check_mariadb_connection, used by every function
###          dbd db_name db_usr db_pwd
###                        set by add_mariadb_db, read by wordpress
###                        install-wordpress.sh
###          BACKUP_POINT  set by backup_mariadb, read by backupdb
###
###        Files written at runtime: /etc/mysqldump.conf (mysql [client]
###        defaults with the root password) and /etc/mariadb-<db>.conf
###        (dbf:/usr:/pwd: lines). Both formats are re-read elsewhere
###        (mysqldump --defaults-file, wordpress restore script) and must
###        stay byte-compatible.
###

## this file may be sourced from other modules #backupdb
## (by absolute path from modules/backupdb/libs/backupdblib.sh,
## so the file path itself is an API)
if ! [[ $SC_MARIADB_DUMP_CONF ]]
then
    SC_MARIADB_DUMP_CONF=/etc/mysqldump.conf
fi

## Install mariadb-server and enable+restart the service. Relies on
## sc_install/add_service from the srvctl module (Fedora-only helpers).
function setup_mariadb {
    ## Main purpose of this function is to set up mysql
    msg "Setup mariadb"

    ## TODO connection check
    sc_install mariadb-server
    add_service mariadb
}

## Determine how to authenticate to mysql as root and verify connectivity.
## Sets global SC_MDA to --defaults-file=$SC_MARIADB_DUMP_CONF when that
## file exists, otherwise to '-u root' (passwordless/socket auth), then
## runs a test query. On failure the whole srvctl process terminates.
function check_mariadb_connection {

    if [[ -f $SC_MARIADB_DUMP_CONF ]]
    then
        msg "Found $SC_MARIADB_DUMP_CONF"
        SC_MDA="--defaults-file=$SC_MARIADB_DUMP_CONF"
    else
        msg "Mariadb $SC_MARIADB_DUMP_CONF not found"
        SC_MDA="-u root"
    fi

    if run "/usr/bin/mysql $SC_MDA -e status" 2> /dev/null
    then
        msg ".. mysql connected"
    else
        err "CONNECTION FAILED. /usr/bin/mysql $SC_MDA -e status"
        ## FIXME(v4): high — bare 'exit' exits with the status of err, which
        ## is 0: automated callers (backupdb backups) see success although
        ## no backup was made. Making it nonzero is a behavior change.
        exit
    fi
}


## Dump every database (except information_schema and performance_schema)
## into /root/mariadb-dump/<timestamp>/<db>.sql, wiping the previous dump
## generation first. Sets global BACKUP_POINT for the backupdb module,
## whose file backup then archives the directory.
function backup_mariadb() {

    check_mariadb_connection

    log "Creating backup of Mysql/Mariadb databases with mysql $SC_MDA"

    ## FIXME(v4): medium — the previous dump generation is destroyed before
    ## the new dumps are produced; if a mysqldump below fails, zero or
    ## partial dumps remain for the outer file-backup to archive.
    rm -fr /root/mariadb-dump/* 2> /dev/null

    BACKUP_POINT="/root/mariadb-dump/$(date +%Y_%m_%d__%H_%M_%S)"
    mkdir -p "$BACKUP_POINT"

    msg "databases:"
    # shellcheck disable=SC2086
    echo "show databases" | mysql $SC_MDA

    ## create backup for each database
    ## FIXME(v4): low — 'grep -v Database' strips the header line but also
    ## skips any database whose name contains "Database"; the unquoted
    ## expansion word-splits exotic names.
    # shellcheck disable=SC2086
    for i in $(echo "show databases" | mysql $SC_MDA | grep -v Database); do
        if [[ "$i" != "information_schema" ]] && [[ "$i" != "performance_schema" ]]
        then
            nur "mysqldump $SC_MDA --databases $i > $BACKUP_POINT/$i.sql"
            # shellcheck disable=SC2086
            mysqldump $SC_MDA --databases "$i" > "$BACKUP_POINT/$i.sql"
            ## FIXME(v4): low — exif without a message prints an empty error
            ## line when a dump fails (exit code is preserved).
            exif
        fi
    done


    msg "All databases have a backup in $BACKUP_POINT"
}

## PROCEDURE Add new database
## Create database $1 (default: $HOSTNAME) with a same-named user and a
## generated password, and save the credentials to /etc/mariadb-<db>.conf.
## Idempotent: when that conf file already exists, only re-reads the saved
## password and returns without touching MySQL. Leaves globals dbd,
## db_name, db_usr, db_pwd for the caller (wordpress).
function add_mariadb_db {

    local query f

    check_mariadb_connection

    ## input $dbd database-definition - basically the database name.
    ## $SC_MDA MariaDB / MysqlDatabase - Argument

    if [[ -z "$1" ]]
    then
        dbd="$HOSTNAME"
    else
        dbd="$1"
    fi

    ## name derivation is a compatibility contract — existing production
    ## databases, users and conf files depend on it staying identical
    dbd=$(echo "$dbd" | tr '.' '_' | tr '-' '_')

    ## FIXME(v4): medium — 15-char user truncation: two sites whose
    ## sanitized names share the first 15 chars collide, and the GRANT
    ## below then resets the first site's user password.
    db_usr="${dbd:0:15}"
    db_name="${dbd:0:63}"

    if [[ -f /etc/mariadb-$db_name.conf ]]
    then
        db_pass="$(grep 'pwd:' /etc/mariadb-"$db_name".conf )"
        db_pwd="${db_pass:4}"
        ntc "Mariadb conf found for $db_name. ($db_pwd)"
        return
    fi

    db_pwd="$(get_password)"
    msg "Adding DB $dbd"

    ## FIXME(v4): low — SQL assembled by string interpolation; names not
    ## covered by the sanitizer above pass straight into the query
    ## (root-local, so impact is breakage rather than privilege).
    query="CREATE DATABASE IF NOT EXISTS $db_name;"
    ntc "mysql $SC_MDA -e $query"
    # shellcheck disable=SC2086
    mysql $SC_MDA -e "$query"
    exif 'ERROR in mariadb query.'

    query="GRANT ALL ON $db_name.* TO '$db_usr'@'localhost' IDENTIFIED BY '$db_pwd'; flush privileges;"
    ntc "mysql $SC_MDA -e $query"
    # shellcheck disable=SC2086
    mysql $SC_MDA -e "$query"
    exif 'ERROR in mariadb query.'

    ## save these params to etc
    ## FIXME(v4): medium — credential file is created with the default umask
    ## (0644 for root): the plaintext password is world-readable inside the
    ## container, and it is also echoed to the terminal above and below.
    f="/etc/mariadb-$db_name.conf"
    echo "dbf:$db_name" > "$f"
    echo "usr:$db_usr" >> "$f"
    echo "pwd:$db_pwd" >> "$f"

    msg "Added MariaDB database $db_name user: $db_usr password: $db_pwd - saved in /etc/mariadb-$db_name.conf"
}

## Secure a fresh MariaDB server: if $SC_MARIADB_DUMP_CONF already exists,
## just display it; otherwise delete anonymous and remote-root users, drop
## the test database, set a generated root password and append [client]
## credentials to $SC_MARIADB_DUMP_CONF for later mysql/mysqldump calls.
## No callers in the repo (kept for manual/historic use).
function secure_mariadb {

    check_mariadb_connection

    if [ -f "$SC_MARIADB_DUMP_CONF" ]
    then
        msg "mysql dump file found $SC_MARIADB_DUMP_CONF"
        cat "$SC_MARIADB_DUMP_CONF"
    else

        msg "Secure mariadb with a root password with mysql $SC_MDA"

        password="$(get_password)"

        ## FIXME(v4): medium — on MariaDB >= 10.4 (Fedora ships 10.5+)
        ## mysql.user is a non-updatable view: these DELETEs and the UPDATE
        ## below fail, the results here are unchecked, so a modern server
        ## is never actually secured.
        # shellcheck disable=SC2086
        mysql $SC_MDA -e "DELETE FROM mysql.user WHERE User='';"
        # shellcheck disable=SC2086
        mysql $SC_MDA -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
        # shellcheck disable=SC2086
        mysql $SC_MDA -e "DROP DATABASE IF EXISTS test;"

        query="UPDATE mysql.user SET Password=PASSWORD('$password') WHERE User='root'; flush privileges;"


        # shellcheck disable=SC2086
        if mysql $SC_MDA -e "$query"
        then
            ## FIXME(v4): low — root DB password logged in plaintext to SC_LOG
            log "Set database root password to: $password"

            ## set up backup params
            ## FIXME(v4): medium — conf file created with the default umask
            ## (world-readable 0644): plaintext root password exposed.
            {
                echo '[client]'
                echo 'user=root'
                # shellcheck disable=SC2154
                echo "password=$password"
            } >> "$SC_MARIADB_DUMP_CONF"

        else
            err "CONNECTION FAILED. Could not set mariadb password, ..."
        fi
    fi

}

## Run a single query ($1) as root, or open an interactive root mysql
## shell when called without arguments. No callers in the repo.
function mysql_root {
    check_mariadb_connection
    if [[ $1 ]]
    then
        # shellcheck disable=SC2086
        mysql $SC_MDA -e "$1"
    else
        # shellcheck disable=SC2086
        mysql $SC_MDA
    fi
}

## end of library — sourced file, keep this explicit top-level return
return
