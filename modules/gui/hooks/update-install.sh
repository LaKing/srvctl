#!/bin/bash

cat > /usr/lib/systemd/system/srvctl-gui.service << EOF
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

systemctl daemon-reload

dnf -y install gcc-c++

cd "$SC_INSTALL_DIR/modules/gui/"

#npm install

npm install -g pty.js
npm install -g express
npm install -g socket.io
npm install -g ssh2

npm install -g angular
npm install -g bootstrap
npm install -g angular-ui-bootstrap
npm install -g angular-sanitize

run systemctl enable srvctl-gui.service
run systemctl start srvctl-gui.service
run systemctl status srvctl-gui.service --no-pager

firewalld_add_service srvctl-gui tcp 250
