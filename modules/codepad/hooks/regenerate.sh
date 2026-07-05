#!/bin/bash

##
##   codepad regenerate hook — sourced by run_hook regenerate (from
##   'sc regenerate', add-ve, add-ve-user, add-codepad). Republishes all
##   users' credential files (.hash/.password/.ip) from the datastore
##   into /var/srvctl3/share/containers/<C>/users/<u>/ via access.js,
##   so the in-container codepad server can authenticate srvctl users.
##

configure_codepad_access
