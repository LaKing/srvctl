#!/bin/bash

##
##   haproxy/hooks/regenerate.sh — rebuild the proxy on 'sc regenerate'.
##
##   Runs via run_hook regenerate from the containers regenerate command,
##   and hourly through /etc/cron.hourly/srvctl-regenerate.sh (which sets
##   ARG='#cron.hourly' so regenerate_haproxy_conf skips the reload).
##
##   Refreshes certificates first (certificates module hook), then
##   re-renders /etc/haproxy/haproxy.cfg and reloads the service
##   (libs/proxylib.sh).
##

run_hook regenerate_certificates

regenerate_haproxy_conf
