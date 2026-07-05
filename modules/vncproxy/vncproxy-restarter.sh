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

# shellcheck disable=SC1091 ## runtime-file
source /etc/srvctl/host.conf

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
