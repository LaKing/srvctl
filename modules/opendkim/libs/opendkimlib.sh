#!/bin/bash

##
##   modules/opendkim/libs/opendkimlib.sh — regenerate DKIM material.
##
##   Sourced by load_libs while the opendkim module is enabled. Provides
##   regenerate_opendkim (called from hooks/regenerate.sh): runs the
##   opendkim.js generator (via opendkim_main), which populates
##   $SC_DATASTORE_DIR/opendkim with per-domain private keys plus the
##   TrustedHosts/KeyTable/SigningTable files; if that folder differs
##   from the runtime copy it is mirrored to /var/opendkim (the location
##   referenced by /etc/opendkim.conf), ownership and permissions are
##   fixed and opendkim.service is restarted — otherwise the service is
##   only started if it is found inactive.
##

function regenerate_opendkim {

    msg "regenerate opendkim"

    ## The datastore copy is the cross-host source of truth (on clusters
    ## it may live on the shared gluster datastore); mode 000 keeps the
    ## private keys readable by root only.
    mkdir -p "$SC_DATASTORE_DIR/opendkim"
    chmod 000 "$SC_DATASTORE_DIR/opendkim"
    mkdir -p /var/opendkim

    ## Generate keys and tables into the datastore (aborts srvctl on
    ## failure), then sync the runtime copy only when something changed.
    opendkim_main
    if ! diff -rq /var/opendkim "$SC_DATASTORE_DIR/opendkim" > /dev/null
    then
        ## Runtime copy is stale: replace it wholesale, then set the
        ## permissions opendkim expects — owner opendkim:opendkim,
        ## directories 750, key and table files 640.
        msg "Updating $HOSTNAME opendkim runtime configuration"
        rm -fr /var/opendkim
        cp -R "$SC_DATASTORE_DIR/opendkim" /var
        chown -R opendkim:opendkim /var/opendkim
        chmod -R 750 /var/opendkim
        ## FIXME(v4): low — unquoted glob: when no per-domain key
        ## directories exist yet (fresh cluster) the literal pattern is
        ## passed to chmod, which prints an error; harmless noise only.
        chmod 640 /var/opendkim/*/*
        chmod 640 /var/opendkim/KeyTable
        chmod 640 /var/opendkim/SigningTable
        chmod 640 /var/opendkim/TrustedHosts

        restart_opendkim
    else
        if systemctl is-active opendkim.service > /dev/null
        then
            msg "Configuration for opendkim is up-to-date, opendkim.service running"
        else
            msg "Configuration for opendkim is up-to-date."
            err "opendkim.service is not running!"
            run systemctl start opendkim
            run systemctl enable opendkim
            run systemctl status opendkim --no-pager
        fi
    fi
}
