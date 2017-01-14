#!/bin/bash

## special services
if [[ $service == openvpn ]] && [[ ! -z "$op" ]] && [[ -f "/usr/lib/systemd/system/openvpn@.service" ]] && $IS_ROOT
then
    msg "openvpn $op"
    ## must have conf
    for c in /etc/openvpn/*.conf
    do
        local s="${c:13: -5}"
        msg "$s"
        service_action "openvpn@$s" "$op"
    done
    return 0
fi
