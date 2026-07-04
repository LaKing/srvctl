#!/bin/bash

echo "Set 8.8.8.8 as DNS server globally."

echo "DNS=8.8.8.8" > /etc/systemd/resolved.conf

run systemctl restart systemd-resolved
run systemctl status systemd-resolved  --no-pager -n 30