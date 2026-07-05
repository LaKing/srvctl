#! /bin/bash

##
##   modules/postfix/module-condition.sh — module enable test.
##
##   Evaluated in a subshell by test_srvctl_modules (commonlib.sh); must
##   print "true" to enable the module. Delegates to the containers module
##   condition, so postfix is active exactly when containers is
##   (container-capable host listed in /etc/srvctl/hosts.json, or an
##   update-install run with an argument) — and therefore never inside a
##   container. Result cached as SC_USE_POSTFIX in modules.conf.
##
##   The module runs Postfix on farm hosts as the SMTP/SMTPS relay hub
##   (with amavisd-new and spamassassin as content filter) and writes the
##   relay-oriented main.cf into container rootfs trees.
##

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"