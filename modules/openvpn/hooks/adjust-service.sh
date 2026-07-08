#!/bin/bash

##
##   modules/openvpn/hooks/adjust-service.sh — fans the "openvpn" service
##   name out to the per-tunnel systemd template instances.
##
##   Fired by "run_hook adjust-service" from modules/srvctl/command.sh when
##   the dispatched command is a service operation (sc openvpn <op> /
##   sc <op> openvpn). A single openvpn.service does not exist — each host
##   runs one hostnet server plus one client tunnel per peer — so this hook
##   derives the instance names from the conf file paths and calls
##   service_action (modules/srvctl/libs/adjust-servicelib.sh) on each; an
##   empty $op means "journalctl since yesterday" there. Both unit layouts
##   are handled: the legacy single openvpn@.service template and the split
##   openvpn-server@/openvpn-client@ pair (Fedora 28 and up). After handling
##   it returns 0 so the generic service command does not double-handle.
##
##   Deprecation candidate for v4 (G8: zerotier replaces the hostnet mesh),
##   but LIVE on production until the migration.
##

# shellcheck disable=SC2154
## service and op are defined by the caller (modules/srvctl/command.sh).

## WP-E.2.b: this hook calls service_action DIRECTLY (then returns 0), so it
## runs BEFORE the command.sh shorthand gate — and service_action itself still
## trusts plain uid 0. Without its own guard, `sudo srvctl.sh openvpn stop`
## would mutate the host VPN tunnels for a non-root caller. Mutating the host
## OpenVPN units is host-infrastructure control -> root only; reads (status /
## empty op = journalctl) stay open.
if [[ $service == openvpn ]] && [[ -n "$op" ]] && [[ "$op" != status ]]
then
    root_only
fi


## legacy layout: single openvpn@.service template (pre Fedora 28)
if [[ -f "/usr/lib/systemd/system/openvpn@.service" ]]
then
    if [[ $service == openvpn ]]
    then
        msg "openvpn $op"
        ## FIXME(v4): low — glob without nullglob: with no matching conf the
        ## loop runs once on the literal pattern and calls service_action on
        ## a nonexistent unit name (same for the two loops below).
        ## must have conf
        for c in /etc/openvpn/*.conf
        do
            ## instance name = path minus "/etc/openvpn/" and ".conf"
            s="${c:13: -5}"
            msg "$s"
            service_action "openvpn@$s" "$op"
        done
        return 0
    fi
fi

## split layout: openvpn-server@ / openvpn-client@ (Fedora 28 and up)
if [[ -f "/usr/lib/systemd/system/openvpn-client@.service" ]] && [[ -f "/usr/lib/systemd/system/openvpn-server@.service" ]]
then
    if [[ $service == openvpn ]]
    then
        msg "openvpn/server's $op"
        ## must have conf
        for c in /etc/openvpn/server/*.conf
        do
            ## instance name = path minus "/etc/openvpn/server/" and ".conf"
            s="${c:20: -5}"
            msg "$s"
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
