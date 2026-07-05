#!/bin/bash

##
##   certificates/hooks/regenerate_certificates.sh
##
##   Custom-named hook (not part of the pre-/post- lifecycle): sourced via
##   'run_hook regenerate_certificates' from the haproxy module (its
##   regenerate hook and the http-redirect / https-redirect commands) and
##   the named module (override-in-address). The letsencrypt module also
##   ships a hook with this name — the filename is API, do not rename.
##
##   Fans admin-installed wildcard certificates from /etc/srvctl/cert/*/
##   out to matching containers in $SC_DATASTORE_DIR/cert/ (wildcardcertlib).
##

apply_wildcard_certificates
