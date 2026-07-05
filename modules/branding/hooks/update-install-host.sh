#!/bin/bash

##
##   modules/branding/hooks/update-install-host.sh — branded error pages.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install'
##   (modules/srvctl/commands/update-install.sh). For each status code
##   below, setup_varwwwhtml_error (libs/update-install-lib.sh) writes a
##   branded <code>.html page and a raw <code>.http response into
##   /var/www/html on the host. haproxy.js emits an 'errorfile' line for
##   every <code>.http file it finds there, so the codes written here
##   determine which errors haproxy serves branded (408, 414 and 501 are
##   generated but currently not wired up in haproxy.js).
##

msg "Writing Error files in /var/www/html"

setup_varwwwhtml_error 400 "Bad request"
setup_varwwwhtml_error 403 "Forbidden"
setup_varwwwhtml_error 404 "Not found."

setup_varwwwhtml_error 408 "Request timeout"
setup_varwwwhtml_error 414 "Request URI too long!"
setup_varwwwhtml_error 500 "An internal server error occurred. Please try again later."
setup_varwwwhtml_error 501 "This method may not be used."
setup_varwwwhtml_error 502 "Bad Gateway"
setup_varwwwhtml_error 503 "The service is not available. Please try again later."
setup_varwwwhtml_error 504 "Gateway timeout error"
