#!/bin/bash

## diagnose_variables — dump the srvctl-relevant shell variables
## (used by the diagnose command)
function diagnose_variables() {
    ## replacing egrep to grep -E
    ( set -o posix ; set ) | grep -E "DEBUG=|ARG=|CMD=|OPA=|OPAS=|SC_|USER|HOST"
}
