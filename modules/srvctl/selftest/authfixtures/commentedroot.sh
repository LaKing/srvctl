#!/bin/bash
## authfixture: commented marker must NOT count as a guard call.
## @en Commented root marker fixture.
##root_only
[[ $SRVCTL ]] || exit 4
run action-commented-root
