#!/bin/bash

readonly SC_COMPANY
readonly SC_COMPANY_DOMAIN

SC_RESELLER_USER=$(get user "$SC_USER" reseller)

readonly SC_RESELLER_USER
export SC_RESELLER_USER
