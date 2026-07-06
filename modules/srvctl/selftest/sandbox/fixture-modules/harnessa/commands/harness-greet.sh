#!/bin/bash
## @@@ harness-greet NAME
## @en Greet someone (harness fixture).
## &en Prints a friendly greeting to NAME.
## &en A second help line, to cover multi-line layout.
[[ $SRVCTL ]] || exit 10

echo "hello $ARG"
