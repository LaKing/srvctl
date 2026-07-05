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
##   requests/renews and deploys Let's Encrypt certificates for all eligible
##   container domains (regenerate_letsencrypt in libs/letsencryptlib.sh,
##   which drives letsencrypt.js).
##

regenerate_letsencrypt
