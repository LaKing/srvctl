#!/bin/bash

if $SC_USE_GLUSTER
then
    gluster_configure srvctl-storage /var/srvctl3/storage
fi

cat > /usr/lib/systemd/system/static-server.service << EOF
[Unit]
Description=srvctl static server
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/static/server.js
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

cd "$SC_INSTALL_DIR/modules/static/"

#npm install

npm install -g finalhandler
npm install -g serve-static

mkdir -p /var/srvctl3/storage/static

run systemctl enable static-server.service
run systemctl start static-server.service
run systemctl status static-server.service --no-pager
