#!/bin/bash

function diagnose_variables() {
    ## replacing egrep to grep -E
    ( set -o posix ; set ) | grep -E "DEBUG=|ARG=|CMD=|OPA=|OPAS=|SC_|USER|HOST"
}
