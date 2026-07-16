#!/bin/bash

##
##   modules/datastore/hooks/diagnose.sh — diagnose output.
##
##   Runs for the diagnose command; prints the generated cluster host table
##   /var/srvctl3/host/hosts.json (the seed source of the datastore hosts data).
##

msg "-- hosts.json --"
cat /var/srvctl3/host/hosts.json
