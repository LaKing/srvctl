#! /bin/bash

##
##   modules/ntp/module-condition.sh — module activation test.
##
##   Sourced in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" to enable the module. Ntp is unconditionally enabled
##   (host, container, root and user alike); the result is cached as
##   SC_USE_NTP in modules.conf. Harmless in practice: the module's only
##   hook is update-install-host, which core fires on hosts only. Until
##   3.2.0.8 this sourced the containers module condition (host-only).
##

echo true
