#!/bin/bash

###
###        backupdb module condition
###
###        Sourced at init; must output exactly "true" to enable the module.
###        The result is cached as SC_USE_BACKUPDB in modules.conf.
###

## FIXME(v4): unconditionally true - the module and its lib load on every machine, even ones with no databases
echo true
