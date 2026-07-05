#!/bin/bash
## modules/gui/hooks/update-install-host.sh - install hook for the srvctl-gui
## web daemon. Sourced by run_hooks update-install-host from `sc update-install`.
##
## DORMANT: the entire body is wrapped in "if false", so this hook does
## nothing. It documents the intended install steps: replace the srvctl2-era
## unit file, place TLS material in /etc/srvctl-gui, write the
## srvctl-gui.service unit (node server.js as root), install the npm globals
## the server requires, enable+start the service, and open tcp port 250.
## The daemon only runs on hosts with leftover srvctl2-era setup.

## FIXME(v4): high - hook disabled with "if false" for the whole v3 line: the
## module can never be deployed from this codebase, yet SC_USE_GUI=true on
## every host keeps libs/spec.sh loading and make_commands_spec running on
## every update-install. Decide revive-or-retire (cockpit replaces it in v4).
if false
then

## TODO this is just temporary for upgrading from srvctl2
rm -fr /usr/lib/systemd/system/srvctl-gui.service

mkdir -p /etc/srvctl-gui
install_service_hostcertificate /etc/srvctl-gui


cat > /etc/systemd/system/srvctl-gui.service << EOF
[Unit]
Description=srvctl-gui server.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/gui/server.js
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

run systemctl daemon-reload

run dnf -y install gcc-c++

cd "$SC_INSTALL_DIR/modules/gui/" || return

#npm install

run npm install -g node-pty
run npm install -g express
run npm install -g socket.io
run npm install -g ssh2

run npm install -g angular
run npm install -g bootstrap
run npm install -g angular-ui-bootstrap
run npm install -g angular-sanitize

run systemctl enable srvctl-gui.service
run systemctl start srvctl-gui.service
run systemctl status srvctl-gui.service --no-pager

firewalld_add_service srvctl-gui tcp 250

fi