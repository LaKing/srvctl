#! /bin/bash

##
##   haproxy/module-condition.sh — module enable test.
##
##   Evaluated in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" to enable the module. Delegates to the containers module
##   condition, so haproxy is active exactly when containers is
##   (container-capable host listed in /var/srvctl3/host/hosts.json, or an
##   update-install run with an argument). Result cached as SC_USE_HAPROXY
##   in modules.conf.
##
##   The module runs HAProxy as the farm's HTTP/HTTPS reverse proxy:
##   haproxy.js renders /etc/haproxy/haproxy.cfg from the datastore,
##   libs/ load certificates into /var/haproxy and reload the service,
##   and the two redirect commands store per-container rules.
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
