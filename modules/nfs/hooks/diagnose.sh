#!/bin/bash


msg "-- NFS host shares --"
for host in $(get cluster host_list)
do
    if run timeout 1 ping -c 1 -W 1 "$host"
    then
        run showmount -e "$host"
    else
        err "Ping of $host failed"
    fi
done

return 0
