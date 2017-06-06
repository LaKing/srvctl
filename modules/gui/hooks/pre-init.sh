#!/bin/bash

# shellcheck disable=SC2034
[[ $SC_COMPANY ]] || SC_COMPANY=$HOSTNAME
# shellcheck disable=SC2034
[[ $SC_COMPANY_DOMAIN ]] || SC_COMPANY_DOMAIN=$HOSTNAME

# shellcheck disable=SC2034
[[ $SC_RESELLER_USER ]] || SC_RESELLER_USER=root
