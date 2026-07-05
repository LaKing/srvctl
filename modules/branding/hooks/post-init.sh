#!/bin/bash

##
##   modules/branding/hooks/post-init.sh — freeze and publish identity.
##
##   Runs on every srvctl invocation via 'run_hook post-init' (init.sh).
##   Marks the company identity variables readonly and exports them so
##   child processes (the node.js scripts of datastore, haproxy, named,
##   letsencrypt, ...) can read them from the environment.
##   SC_RESELLER_USER (defaulted in pre-init.sh) is not exported here —
##   see the FIXME(v4) note in hooks/pre-init.sh.
##

readonly SC_COMPANY
readonly SC_COMPANY_DOMAIN

export SC_COMPANY
export SC_COMPANY_DOMAIN
