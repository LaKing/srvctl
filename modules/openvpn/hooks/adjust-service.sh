#!/bin/bash

# shellcheck disable=SC2154
## service and op are defined.


## fedora 27 introduced a change in openvpn service files
#if [[ $service == openvpn ]] && [[ ! -z "$op" ]] && [[ -f "/usr/lib/systemd/system/openvpn@.service" ]] && $SC_ROOT
if [[ -f "/usr/lib/systemd/system/openvpn@.service" ]]
then
    if [[ $service == openvpn ]] && [[ ! -z "$op" ]] && $SC_ROOT
    then
        msg "openvpn $op"
        ## must have conf
        for c in /etc/openvpn/*.conf
        do
            s="${c:13: -5}"
            msg "$s"
            service_action "openvpn@$s" "$op"
        done
        return 0
    fi
fi

if [[ -f "/usr/lib/systemd/system/openvpn-client@.service" ]] && [[ -f "/usr/lib/systemd/system/openvpn-server@.service" ]]
then
    if [[ $service == openvpn ]] && [[ ! -z "$op" ]] && $SC_ROOT
    then
        msg "openvpn/server's $op"
        ## must have conf
        for c in /etc/openvpn/server/*.conf
        do
            s="${c:20: -5}"
            msg "$s"
            #service_action "openvpn${s:7:7}@$s" "$op"
            service_action "openvpn-server@$s" "$op"
        done
        
        msg "openvpn/client's $op"
        ## must have conf
        for c in /etc/openvpn/client/*.conf
        do
            s="${c:20: -5}"
            msg "$s"
            service_action "openvpn-client@$s" "$op"
        done
        
        return 0
    fi
fi
