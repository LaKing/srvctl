#!/bin/bash

function regenerate_named_conf() {
    
    if [[ $SC_DNS_SERVER == 'master' ]] || [[ $SC_DNS_SERVER == 'slave' ]]
    then
        msg "regenerate_named_conf $SC_DNS_SERVER $SC_COMPANY_DOMAIN"
        namedcfg "$SC_DNS_SERVER"
    else
        err "this is not a DNS server"
    fi
    
}
