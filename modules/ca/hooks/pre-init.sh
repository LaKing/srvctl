#!/bin/bash

##
##   modules/ca/hooks/pre-init.sh — CA configuration defaults.
##
##   Runs on every srvctl invocation, after /etc/srvctl/*.conf has been
##   sourced, so site config (e.g. ca.conf) wins and these lines only fill
##   in unset values: the CA state directory, the designated CA host
##   (default: this host) and the openssl subject prefix used for every CA
##   and leaf certificate. Promoted to readonly in hooks/post-init.sh.
##

# shellcheck disable=SC2034
[[ $SC_ROOTCA_DIR ]] || SC_ROOTCA_DIR=/etc/srvctl/CA
# shellcheck disable=SC2034
[[ $SC_ROOTCA_HOST ]] || SC_ROOTCA_HOST=$HOSTNAME
# shellcheck disable=SC2034
[[ $SC_ROOTCA_SUBJ ]] || SC_ROOTCA_SUBJ="/C=HU/ST=Hungary/L=Budapest/O=SRVCTL-CA"

