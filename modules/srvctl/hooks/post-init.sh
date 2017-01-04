#!/bin/bash

mkdir -p "$SC_LOG_DIR"

## make constants
readonly SC_LOG_DIR
readonly SC_LOG="$SC_LOG_DIR/srvctl.log"

## log commands
echo "$NOW [$SC_USER@$HOSTNAME $(pwd)]# $0 $*" >> "$SC_LOG"

