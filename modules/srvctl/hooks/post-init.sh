#!/bin/bash

mkdir -p "$SC_LOG_DIR"

## make constants
readonly SC_LOG_DIR
readonly SC_LOG="$SC_LOG_DIR/srvctl.log"
readonly SC_COMPANY
readonly SC_COMPANY_DOMAIN

[ "$CMD" == "?" ] && CMD=status
[ "$CMD" == "+" ] && CMD=start
[ "$CMD" == "-" ] && CMD=stop
[ "$CMD" == "!" ] && CMD=restart

[ "$ARG" == "?" ] && ARG=status
[ "$ARG" == "+" ] && ARG=start
[ "$ARG" == "-" ] && ARG=stop
[ "$ARG" == "!" ] && ARG=restart

## log commands
echo "$NOW [$SC_USER@$HOSTNAME $(pwd)]# $0 $*" >> "$SC_LOG"

