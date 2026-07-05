#!/bin/bash

##
##   modules/dns/hooks/update-install-host.sh — force Google DNS on the host.
##
##   Runs via 'run_hooks update-install-host' near the end of
##   'sc update-install' (modules/srvctl/commands/update-install.sh).
##   Overwrites /etc/systemd/resolved.conf with a single DNS=8.8.8.8
##   line, then restarts systemd-resolved and prints its status.
##

echo "Set 8.8.8.8 as DNS server globally."

## FIXME(v4): high — this writes "DNS=8.8.8.8" with no [Resolve] section
## header; systemd's parser ignores assignments outside a section, so the
## advertised change never takes effect while the stock resolved.conf is
## destroyed on every update-install on every host. v4 should write a
## proper drop-in (/etc/systemd/resolved.conf.d/srvctl.conf with a
## [Resolve] header) or drop/merge this with the named module, whose
## local DNS server this hook actively bypasses.
echo "DNS=8.8.8.8" > /etc/systemd/resolved.conf

run systemctl restart systemd-resolved
run systemctl status systemd-resolved  --no-pager -n 30
