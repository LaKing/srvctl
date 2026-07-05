#!/bin/bash

##
##   modules/ca/hooks/post-init.sh — locks the CA settings.
##
##   Runs on every srvctl invocation, after libs are loaded; promotes the
##   values defaulted in hooks/pre-init.sh to readonly so nothing can
##   reassign them later. Runs before containers/hooks/post-init.sh
##   (alphabetical module order), which then exports SC_ROOTCA_HOST.
##

# shellcheck disable=SC2034
readonly SC_ROOTCA_HOST
# shellcheck disable=SC2034
readonly SC_ROOTCA_SUBJ
# shellcheck disable=SC2034
readonly SC_ROOTCA_DIR
