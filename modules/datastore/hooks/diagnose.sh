#!/bin/bash

##
##   modules/datastore/hooks/diagnose.sh — diagnose output.
##
##   Runs for the diagnose command; prints the static cluster host table
##   /etc/srvctl/hosts.json (the seed source of the datastore hosts data).
##

msg "-- hosts.json --"
cat /etc/srvctl/hosts.json
