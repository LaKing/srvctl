#!/bin/bash


msg "-- NFS host shares --"
for host in $(cfg system host_list)
do
    run showmount -e "$host"
done
