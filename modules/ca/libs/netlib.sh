#!/bin/bash

##
##   modules/ca/libs/netlib.sh — CA replication across the cluster.
##
##   Provides ca_sync, called from hooks/regenerate.sh. On the CA host
##   (SC_ROOTCA_HOST == HOSTNAME) it only prints a notice; on every other
##   host it mirrors the CA host's /etc/srvctl/CA directory into the local
##   /etc/srvctl via rsync over ssh, as root.
##

## FIXME(v4): design-level security issue — ca_sync replicates the ENTIRE CA
## tree (root CA private keys, every host/user private key, passwordless
## .p12 bundles) to every non-CA host on each regenerate; compromise of any
## cluster host is compromise of the whole PKI. v4 should distribute public
## material only, with per-host key delivery.
function ca_sync() {
    if [[ $SC_ROOTCA_HOST ]]
    then
        if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
        then
            msg "This is the CA server"
        else
            ## reachability probe: the remote hostname must echo back our
            ## configured value.
            ## FIXME(v4): short-name vs FQDN mismatch makes this comparison
            ## fail, silently skipping the sync with a false "could not be
            ## reached" error.
            if [[ "$(ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]]
            then
                ## single-string argument relies on run word-splitting it.
                ## FIXME(v4): path hardcodes /etc/srvctl/CA — a customized
                ## SC_ROOTCA_DIR is never replicated.
                run "rsync -aze ssh $SC_ROOTCA_HOST:/etc/srvctl/CA /etc/srvctl"
            else
                err "The CA server $SC_ROOTCA_HOST could not be reached!"
            fi
        fi
    else
        ## ("definded" typo is part of the frozen v3 output surface)
        err "No CA server definded in configs"
    fi
}
