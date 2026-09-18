#!/bin/bash

##
##   letsencrypt/hooks/regenerate_certificates.sh
##
##   Custom-named hook (not part of the pre-/post- lifecycle): sourced via
##   'run_hook regenerate_certificates' from the haproxy module (its
##   regenerate hook and the http-redirect / https-redirect commands) and
##   the named module (override-in-address). The certificates module ships
##   a hook with the same name; run_hook sources both in module order.
##
##   Ensures the acme-server.service challenge responder is running, then
##   runs letsencrypt.js (regenerate_letsencrypt in libs/letsencryptlib.sh):
##   DNS-01 wildcard issuance on the DNS primary, pull and handover of
##   wildcards on serving hosts, and http-01 for all other eligible domains.
##

regenerate_letsencrypt
