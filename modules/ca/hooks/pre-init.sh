#!/bin/bash

# shellcheck disable=SC2034
[[ $SC_ROOTCA_DIR ]] || SC_ROOTCA_DIR=/etc/srvctl/CA
# shellcheck disable=SC2034
[[ $SC_ROOTCA_HOST ]] || SC_ROOTCA_HOST=$HOSTNAME
# shellcheck disable=SC2034
[[ $SC_ROOTCA_SUBJ ]] || SC_ROOTCA_SUBJ="/C=HU/ST=Hungary/L=Budapest/O=SRVCTL-CA"

