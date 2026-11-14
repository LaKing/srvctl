#!/bin/bash

##
##   modules/datastore/hooks/update-install-host.sh — host install step.
##
##   Runs during update-install on the host: (re)writes, enables and
##   restarts the datastore-server.service http daemon (port 1030) via
##   install_datastoreserver (libs/httpserverlib.sh).
##

install_datastoreserver
