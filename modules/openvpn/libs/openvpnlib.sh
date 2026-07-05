#!/bin/bash

##
##   modules/openvpn/libs/openvpnlib.sh — certificate provisioning for the
##   OpenVPN mesh, on top of the ca module.
##
##   Sourced by load_libs whenever SC_USE_OPENVPN=true; called from
##   hooks/update-install-host.sh. On the root-CA host,
##   init_openvpn_rootca_certificates mints everything locally; every other
##   host runs grab_openvpn_rootca_certificates, which triggers remote
##   minting over ssh and rsyncs its own material from the CA into
##   /etc/openvpn/$NET-{ca,server,client}.{crt,key}.pem.
##
##   WIRE PROTOCOL: init_openvpn_create_ca_certificates is invoked remotely
##   by name ("/bin/srvctl exec-function init_openvpn_create_ca_certificates
##   NET HOST" over ssh, see grab_… below) — its name and argument order are
##   a cross-host contract between hosts that may run different srvctl
##   versions during a rolling upgrade; do not rename or reorder.
##
##   Deprecation candidate for v4 (G8: zerotier replaces the hostnet mesh),
##   but LIVE on production until the migration.
##

## Mint the server and client certificate pair for host $2 in net $1 (runs
## on the CA host; also the remote entry point of the wire protocol above).
function init_openvpn_create_ca_certificates() { #net #sid
    local NET SID
    ## usernet / hostnet / whatevernet
    NET="$1"
    ## root / server / user / whatever
    SID="$2"
    
    msg "init_openvpn_create_ca_certificates $NET $SID"
    
    create_ca_certificate server "$NET" "$SID"
    create_ca_certificate client "$NET" "$SID"
}

## Root-CA host only (self-guarded): initialize the $1 CA, mint the root
## client cert and every cluster host's pairs, then install the CA cert and
## this host's own pairs under /etc/openvpn/.
function init_openvpn_rootca_certificates() { #net
    local NET
    ## usernet / hostnet / whatevernet
    NET="$1"
    
    ## then get the certificates
    if [[ "$SC_ROOTCA_HOST" != "$HOSTNAME" ]]
    then
        return
    fi
    
    msg "init_openvpn_rootca_certificates $NET"
    
    root_CA_init "$NET"
    
    create_ca_certificate client "$NET" root
    
    for S in $(get cluster host_list)
    do
        init_openvpn_create_ca_certificates "$NET" "$S"
    done
    
    cat /etc/srvctl/CA/ca/"$NET".crt.pem > /etc/openvpn/"$NET"-ca.crt.pem
    
    cat /etc/srvctl/CA/"$NET"/server-"$HOSTNAME".key.pem > /etc/openvpn/"$NET"-server.key.pem
    cat /etc/srvctl/CA/"$NET"/server-"$HOSTNAME".crt.pem > /etc/openvpn/"$NET"-server.crt.pem
    
    cat /etc/srvctl/CA/"$NET"/client-"$HOSTNAME".key.pem > /etc/openvpn/"$NET"-client.key.pem
    cat /etc/srvctl/CA/"$NET"/client-"$HOSTNAME".crt.pem > /etc/openvpn/"$NET"-client.crt.pem
    
}

## Non-CA hosts: verify the CA host is reachable, trigger remote minting of
## this host's certs for net $1, then rsync the CA cert and own pairs —
## each only if the local file is missing.
function grab_openvpn_rootca_certificates() { #net

    local NET
    ## usernet / hostnet / whatevernet
    NET="$1"
    
    if [[ "$(ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" hostname 2> /dev/null)" == "$SC_ROOTCA_HOST" ]]
    then

        msg "regenerate openvpn certificate config for $NET - CA is $SC_ROOTCA_HOST"
        local options

        ## client-side $NET/$HOSTNAME expansion is intended (wire protocol,
        ## see file header)
        # shellcheck disable=SC2029
        ssh -n -o ConnectTimeout=1 "$SC_ROOTCA_HOST" "/bin/srvctl exec-function init_openvpn_create_ca_certificates $NET $HOSTNAME"

        ## NOTE: "$options" is passed as a single word below and relies on
        ## run() expanding $* unquoted (lablib.sh) to re-split it into rsync
        ## flags — do not quote it "properly" without changing run().
        options="--no-R --no-implied-dirs -avze ssh"

        ## FIXME(v4): medium — all three blocks below fetch only when the
        ## local file is missing: renewed or expired certs on the CA are
        ## never re-synced, so after expiry the mesh stays down until the
        ## local pem files are deleted by hand.
        if [[ ! -f /etc/openvpn/"$NET"-ca.crt.pem ]]
        then
            msg "Grabbing CA certificates from $SC_ROOTCA_HOST for openvpn $NET"
            run rsync "$options" "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/ca/$NET.crt.pem" /etc/openvpn/"$NET"-ca.crt.pem
        fi
        
        if [[ ! -f /etc/openvpn/"$NET"-server.crt.pem ]] || [[ ! -f /etc/openvpn/"$NET"-server.key.pem ]]
        then
            ## FIXME(v4): smell — message hardcodes "usernet" even when
            ## NET=hostnet (same in the client block below)
            msg "Grabbing usernet $HOSTNAME server certificate from $SC_ROOTCA_HOST for openvpn $NET"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/$NET/server-$HOSTNAME.crt.pem" /etc/openvpn/"$NET"-server.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/$NET/server-$HOSTNAME.key.pem" /etc/openvpn/"$NET"-server.key.pem
        fi
        
        if [[ ! -f /etc/openvpn/"$NET"-client.crt.pem ]] || [[ ! -f /etc/openvpn/"$NET"-client.key.pem ]]
        then
            msg "Grabbing usernet $HOSTNAME client certificate from $SC_ROOTCA_HOST for openvpn"
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/$NET/client-$HOSTNAME.crt.pem" /etc/openvpn/"$NET"-client.crt.pem
            run rsync "$options"  "root@$SC_ROOTCA_HOST:/etc/srvctl/CA/$NET/client-$HOSTNAME.key.pem" /etc/openvpn/"$NET"-client.key.pem
        fi
        
    else
        err "CA $SC_ROOTCA_HOST connection failed!"
    fi
    
}
