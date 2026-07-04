## /usr/local/share/srvctl/modules/vncproxy/vncproxy-restarter.sh

source /etc/srvctl/host.conf

if nmap -p 5900 --script vnc-info $SC_HOST_IP | grep "VNC Authentication"
then
	echo "OK: nmap -p 5900 --script vnc-info $SC_HOST_IP "
else
	echo "FAIL: nmap -p 5900 --script vnc-info $SC_HOST_IP "
    systemctl restart vncproxy
    systemctl status vncproxy
fi

exit

## /etc/systemd/system/vncproxy-restarter.service

[Unit]
Description=Restart VNC Proxy Service

[Service]
Type=oneshot
ExecStart=/usr/local/share/srvctl/modules/vncproxy/vncproxy-restarter.sh

[Install]
WantedBy=multi-user.target


## /etc/systemd/system/vncproxy-restarter.timer

[Unit]
Description=Timer for VNC Proxy Restarter Service

[Timer]
OnCalendar=*:*:00
Unit=vncproxy-restarter.service

[Install]
WantedBy=timers.target

## --

systemctl daemon-reload

systemctl enable --now vncproxy-restarter.timer

systemctl list-timers | grep vncproxy-restarter