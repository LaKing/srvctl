#!/bin/bash

##
##   modules/datastore/hooks/update-install-host.sh — host install step.
##
##   Runs during update-install on the host. Configures the srvctl-data
##   gluster volume when gluster is in use, then (re)writes, enables and
##   starts the datastore-server.service http daemon (port 1030) via
##   install_datastoreserver (libs/httpserverlib.sh).
##

if $SC_USE_GLUSTER
then
    gluster_configure srvctl-data "$SC_DATASTORE_RW_DIR"
fi

install_datastoreserver
