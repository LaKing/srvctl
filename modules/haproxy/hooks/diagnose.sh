#!/bin/bash

##
##   haproxy/hooks/diagnose.sh — placeholder for 'sc diagnose'.
##
##   Currently a deliberate no-op: the stats-socket queries below were
##   disabled but kept as the intended diagnostics (socat is installed by
##   update-install-host.sh for exactly this purpose).
##   FIXME(v4): resurrect as real 'show stat' diagnostics or drop the hook.
##

#msg "HAproxy info"
#echo "show info" | socat unix-connect:/var/run/haproxy.sock stdio
#msg "HAproxy errors"
#echo "show errors" | socat unix-connect:/var/run/haproxy.sock stdio
#msg "HAproxy stat"
#echo "show stat" | socat unix-connect:/var/run/haproxy.stat stdio
#msg "HAproxy sessions"
#echo "show sess" | socat unix-connect:/var/run/haproxy.stat stdio

