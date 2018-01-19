#!/bin/bash
msg "HAproxy info"
echo "show info" | socat unix-connect:/var/run/haproxy.sock stdio
msg "HAproxy errors"
echo "show errors" | socat unix-connect:/var/run/haproxy.sock stdio
msg "HAproxy stat"
echo "show stat" | socat unix-connect:/var/run/haproxy.stat stdio
msg "HAproxy sessions"
echo "show sess" | socat unix-connect:/var/run/haproxy.stat stdio


