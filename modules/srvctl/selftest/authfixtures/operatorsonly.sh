#!/bin/bash
## authfixture: OPERATORS_ONLY class — root + operator.
[[ $SRVCTL ]] || exit 4
operators_only
run action-operators
