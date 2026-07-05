#!/bin/bash

##
##   modules/mariadb/hooks/init.sh — pick up the mysql credentials file.
##
##   Runs on every srvctl invocation (init hook) when the mariadb module
##   is enabled. When /etc/mysqldump.conf exists — the mysql [client]
##   defaults file holding the root password, used mainly in containers —
##   point SC_MARIADB_DUMP_CONF at it for the library functions.
##

## MYSQL / MARIADB conf file that stores the mysql root password - in containers

## FIXME(v4): low — redundant: libs/mariadblib.sh defaults
## SC_MARIADB_DUMP_CONF to the same path whenever it is unset,
## so this hook can be dropped in v4.
if [[ -f /etc/mysqldump.conf ]]
then
    ## not unused, used later
    # shellcheck disable=SC2034
    SC_MARIADB_DUMP_CONF=/etc/mysqldump.conf
fi
