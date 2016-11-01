#!/bin/bash

[[ ! $SC_ROOT == true ]] readonly SC_LOG_DIR=$SC_HOME/.srvct/log

# shellcheck disable=SC2034
SC_COMPANY=$HOSTNAME
# shellcheck disable=SC2034
SC_COMPANY_DOMAIN=$HOSTNAME
# shellcheck disable=SC2034
SC_ROOT_USERNAME='root'
