#!/bin/bash

function scan_host_keys() {
    local C="$1"
    local ip="$2"
    local res_ip=''
    local res_ve=''
    
    if [[ -z $C ]] || [[ -z $ip ]]
    then
        return 67
    fi
    
    res_ip="$(ssh-keyscan -t rsa -H "$ip" 2>/dev/null)"
    res_ve="$(ssh-keyscan -t rsa -H "$C" 2>/dev/null)"
    
    if [ ! -z "$res_ip" ] && [ ! -z "$res_ve" ]
    then
        mkdir -p "$SRV/$C/etc/srvctl/"
        echo "## srvctl scanned host-key $NOW IP $ip VE $C" > "$SRV/$_C/etc/srvctl/host-key"
        echo "$res_ip" >> "$SRV/$C/etc/srvctl/host-key"
        echo "$res_ve" >> "$SRV/$C/etc/srvctl/host-key"
        put container "$C" host-key-ip "'$res_ip'"
        put container "$C" host-key-ve "'$res_ve'"
        
    else
        err "ssh-keyscan returned with no result."
    fi
}
