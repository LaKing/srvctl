#!/bin/bash
## authfixture: OWNER_ONLY class — root + resource owner.
[[ $SRVCTL ]] || exit 4
owner_only container "$ARG"
run action-owner
