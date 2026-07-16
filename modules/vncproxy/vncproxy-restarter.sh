## /usr/local/share/srvctl/modules/vncproxy/vncproxy-restarter.sh

## Watchdog for the vncproxy service, meant to run every minute via the
## hand-installed vncproxy-restarter.timer (unit texts documented below,
## after the exit). Probes port 5900 with nmap; if the "VNC Authentication"
## banner is missing, restarts the service.
## FIXME(v4): no shebang — direct execution as a systemd ExecStart fails
## with 'Exec format error'; it only runs via an interpreter (bash FILE).
## FIXME(v4): nmap is not installed by dnf.sh; with the timer active and
## nmap missing (or the proxy momentarily busy) the FAIL branch restarts
## vncproxy every minute, killing all live VNC sessions.
# shellcheck shell=bash

## The projection moves to /var/srvctl3/host on the first root srvctl run
## after a code deploy; until then (and after a code rollback) only the
## legacy /etc/srvctl copy exists. A missing file here must not trigger the
## FAIL branch below (it restarts vncproxy, killing live sessions).
# shellcheck disable=SC1091 ## runtime-files
source /var/srvctl3/host/host.conf 2>/dev/null || source /etc/srvctl/host.conf || exit 0

## Without a host address there is nothing to probe: restarting vncproxy
## cannot help (start.sh refuses with 78), it only spams the journal once a
## minute. Skip the probe instead of taking the FAIL branch.
if [[ -z ${SC_HOST_IP:-} ]]
then
    echo "SKIP: host projection lacks SC_HOST_IP; not probing vncproxy"
    exit 0
fi

if nmap -p 5900 --script vnc-info "$SC_HOST_IP" | grep "VNC Authentication"
then
    echo "OK: nmap -p 5900 --script vnc-info $SC_HOST_IP "
else
    echo "FAIL: nmap -p 5900 --script vnc-info $SC_HOST_IP "
    systemctl restart vncproxy
    systemctl status vncproxy
fi

exit

## Manual installation notes — everything below the exit above is
## documentation only and is never executed.

## /etc/systemd/system/vncproxy-restarter.service
#
# [Unit]
# Description=Restart VNC Proxy Service
#
# [Service]
# Type=oneshot
# ExecStart=/usr/local/share/srvctl/modules/vncproxy/vncproxy-restarter.sh
#
# [Install]
# WantedBy=multi-user.target

## /etc/systemd/system/vncproxy-restarter.timer
#
# [Unit]
# Description=Timer for VNC Proxy Restarter Service
#
# [Timer]
# OnCalendar=*:*:00
# Unit=vncproxy-restarter.service
#
# [Install]
# WantedBy=timers.target

## --
#
# systemctl daemon-reload
#
# systemctl enable --now vncproxy-restarter.timer
#
# systemctl list-timers | grep vncproxy-restarter
