#!/bin/bash

##
##   containers/execstartpost.sh — ExecStartPost of srvctl-nspawn@.service.
##
##   NOT a srvctl hook: systemd runs it as 'execstartpost.sh %i' outside
##   the srvctl environment, right after the container starts. Applies
##   the optional per-container /srv/$C/ethernet.sh (rendered from the
##   datastore by create_nspawn_container_config), starts
##   lib/open-mapped-ports.sh for the Port= lines, then reports the
##   machine's IP address to the journal. Must end with exit 0 — a
##   non-zero status here would fail the whole unit start.
##

## this script can run outside of srvctl! It will get invoked over systemd units
# shellcheck disable=SC2034
C="$1"

echo "[execstartpost] $C"

if [[ ! -d /srv/"$C" ]]
then
    echo "Machine folder not found."
    exit 14
fi

if [[ -f /srv/"$C"/ethernet.sh ]]
then
	echo "[execstartpost] Calling /srv/$C/ethernet.sh"
    /bin/bash /srv/"$C"/ethernet.sh
fi

## the forwarded ports opened in the container's own firewalld too, in the background:
## its firewalld is not up yet (lib/open-mapped-ports.sh)
if grep -q '^Port=' /srv/"$C"/"$C".nspawn 2> /dev/null
then
    systemd-run -q --no-block --collect --unit="srvctl-ports-$C" /bin/bash "$(dirname "$0")/lib/open-mapped-ports.sh" "$C"
fi

## give the container's networkd a moment to acquire an address
sleep 3

ip="$(machinectl status "$C"| head -n 8 | grep Address |  sed 's/^.*: //')"

## journal-only report; the datastore 'put container ip' write that used
## to live here is intentionally disabled
if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
    echo "[execstartpost] IP for $C is $ip"
else
    echo "[execstartpost] No IP address for $C (result $ip)"
fi

exit 0