#!/bin/bash

function load_certificate_folder_files {
    local certdir
    certdir="$1"
    
    for cert in "$certdir"/*.pem
    do
        if check_pem "$cert"
        then
            if [[ -f "$cert" ]]
            then
                cp -u "$cert" /var/haproxy/
            fi
        fi
    done
}


function regenerate_haproxy_conf {
    ## static ve-host-certificiates with priority from etc
    ## container certificates from gluster share
    
    local sccert_dir
    
    mkdir -p "$SC_DATASTORE_DIR/cert"
    mkdir -p "$SC_DATASTORE_DIR/pki-validation"
    
    msg "Regenerate haproxy configs."
    ## the haproxy certificates will be loaded from /var/haproxy
    mkdir -p /var/haproxy
    ## we may have server-wide wildcard certificates
    mkdir -p /etc/srvctl/cert
    
    
    load_certificate_folder_files /var/srvctl3/datastore/cert
    
    for sccert_dir in /etc/srvctl/cert/*
    do
        load_certificate_folder_files "$sccert_dir"
    done
    
    
    
    rm -fr /var/haproxy/ca-bundle.pem
    #run rsync -a "$SC_DATASTORE_RO_DIR/cert" /var/haproxy
    
    haproxycfg
    #restart_haproxy
    ## better reload
    if [[ $ARG == "#cron.hourly" ]]
    then
    	msg "Skipping reload for automatic regeneration #cron.hourly"
    else
    	reload_haproxy
    fi
}

