#!/bin/bash

##
##   modules/branding/hooks/pre-init.sh — company identity defaults.
##
##   Runs on every srvctl invocation via 'run_hook pre-init' (init.sh),
##   after /etc/srvctl/*.conf (including branding.conf) has been sourced.
##   Provides fallback values only: variables already set by site config
##   are left untouched. hooks/post-init.sh later marks SC_COMPANY and
##   SC_COMPANY_DOMAIN readonly and exports them.
##

## assigned here, consumed by other modules after libs are loaded
# shellcheck disable=SC2034
[[ $SC_COMPANY ]] || SC_COMPANY=$HOSTNAME
# shellcheck disable=SC2034
[[ $SC_COMPANY_DOMAIN ]] || SC_COMPANY_DOMAIN=$HOSTNAME

## FIXME(v4): SC_RESELLER_USER is defaulted here but never exported
## (post-init.sh exports only the SC_COMPANY variables), so its sole
## consumer modules/datastore/main.mjs reads process.env.SC_RESELLER_USER
## as undefined — dead plumbing until it is exported or removed.
# shellcheck disable=SC2034
[[ $SC_RESELLER_USER ]] || SC_RESELLER_USER=root
