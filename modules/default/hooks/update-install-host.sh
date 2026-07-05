#!/bin/bash

##
##   modules/default/hooks/update-install-host.sh — default page server unit.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install'
##   (modules/srvctl/commands/update-install.sh). Writes the systemd unit
##   /etc/systemd/system/default-server.service, which runs server.js as
##   user nobody: a catch-all Node.js daemon on port 1282 answering every
##   request with HTTP 404 and the branded page /var/www/html/404.html.
##   haproxy's default_backend is localhost:1282, so any request whose
##   Host matches no hosted site lands here. The branding module's hook
##   (alphabetically earlier in the update-install-host phase) must
##   already have written /var/www/html/404.html.
##

## The heredoc is unquoted on purpose: $SC_INSTALL_DIR is expanded at
## generation time, baking the srvctl install path into ExecStart.
## FIXME(v4): Restart=always with no RestartSec — if server.js crashes at
## startup (e.g. 404.html missing), systemd restart-loops into permanent
## 'failed' state within about a second.
## FIXME(v4): nothing ever stops, disables or removes this unit when the
## module or srvctl itself is removed; it outlives its source.
cat > /etc/systemd/system/default-server.service << EOF
[Unit]
Description=srvctl default page server
After=network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/default/server.js
User=nobody
Group=nobody
Restart=always

[Install]
WantedBy=multi-user.target
EOF

run systemctl daemon-reload

## FIXME(v4): failures of enable/start are silently swallowed — 'run'
## skips its eyif warning for any command whose first word is systemctl
## (lablib.sh); a broken unit install produces no error in the update log.
run systemctl enable default-server.service
## FIXME(v4): 'start' (not 'restart') — after a srvctl code update an
## already-running daemon keeps executing the old server.js until reboot.
run systemctl start default-server.service
run systemctl status default-server.service --no-pager
