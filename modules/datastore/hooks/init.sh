#!/bin/bash

##
##   modules/datastore/hooks/init.sh — select the datastore directory.
##
##   Runs at init on enabled hosts. Every host works on its own read-write
##   directory, so the readonly default of hooks/pre-init.sh is cleared here.
##   init_datastore (libs/datalib.sh) then picks the directory, seeds missing
##   json files and exports SC_DATASTORE_DIR.
##

# shellcheck disable=SC2034
SC_DATASTORE_RO_USE=false

init_datastore
