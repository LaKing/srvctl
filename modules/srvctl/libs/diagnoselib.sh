#!/bin/bash

function diagnose_variables() {
    ( set -o posix ; set ) | egrep "DEBUG=|ARG=|CMD=|OPA=|OPAS=|SC_|USER|HOST"
}
