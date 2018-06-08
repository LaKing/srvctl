#!/bin/bash

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

run systemctl enable default-server.service
run systemctl start default-server.service
run systemctl status default-server.service --no-pager
