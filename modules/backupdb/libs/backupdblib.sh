#!/bin/bash

###
###        backupdb - dump local databases to /root
###
###        Provides the single library function backupdb(), meant to run
###        inside the machine that owns the data (host or container),
###        invoked as: sc exec-function backupdb (root-only dispatch).
###        The module ships no commands and no hooks; besides this lib its
###        only payload is the vendored mongo-tools binaries under bin/.
###
###        MariaDB branch: if /var/lib/mysql and /usr/bin/mysql exist,
###        sources the mariadb module's lib and calls backup_mariadb, which
###        dumps every database to /root/mariadb-dump/<timestamp>/<db>.sql
###        and exits the whole process on mysqldump failure (in that case
###        the mongodb branch below never runs).
###
###        MongoDB branch: if /var/lib/mongodb exists, wipes the previous
###        dump under /root/mongodb-dump and dumps the local mongod into a
###        fresh /root/mongodb-dump/<timestamp> directory via the vendored
###        mongodump binary.
###

function backupdb() {

    if [[ -d /var/lib/mysql ]] && [[ -f /usr/bin/mysql ]]
    then
        ntc "mariadb @ $HOSTNAME"
        ## sourced by absolute path on purpose: works even when SC_USE_MARIADB=false
        # shellcheck source=/usr/local/share/srvctl/modules/mariadb/libs/mariadblib.sh
        # shellcheck disable=SC1091 ## cross-module
        source "$SC_INSTALL_DIR"/modules/mariadb/libs/mariadblib.sh
        backup_mariadb
    fi

    ## FIXME(v4): detection keys only on /var/lib/mongodb (Fedora datadir); mongodb.org RPM installs use /var/lib/mongo and are silently never backed up
    if [[ -d /var/lib/mongodb ]]
    then
        ntc "mongodb @ $HOSTNAME"

        ##
        ##  The current mongodb build is bugged - https://bugzilla.redhat.com/show_bug.cgi?id=1537510
        ##
        ##  Failed: error dumping metadata: error running `listIndexes`. Collection: `admin.system.version` Err: Unknown element kind (0x13)
        ##
        ##  Because of that Fedora build bug, the vendored mongo-tools
        ##  binary under modules/backupdb/bin is used instead of the
        ##  system mongo-tools package.
        ##

        ## FIXME(v4): the previous dump is deleted before the new one is attempted; if mongodump fails, zero backups remain
        rm -fr /root/mongodb-dump/*
        local out_path
        out_path="/root/mongodb-dump/$(date +%Y_%m_%d__%H_%M_%S)"
        mkdir -p "$out_path"
        ## FIXME(v4): vendored mongo-tools r3.6.0 (2017, x86_64-only) is used even when a current /usr/bin/mongodump exists; incompatible with mongod 4.2+
        ## FIXME(v4): mongodump exit status is never checked (no exif/eyif); a failed or partial dump is indistinguishable from success
        "$SC_INSTALL_DIR"/modules/backupdb/bin/mongodump --out "$out_path"

    fi
}
