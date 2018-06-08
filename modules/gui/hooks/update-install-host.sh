#!/bin/bash

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

cd "$SC_INSTALL_DIR/modules/gui/"

#npm install

run npm install -g pty.js --unsafe-perm
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
