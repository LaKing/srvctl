#!/bin/bash

## @@@ regenerate
## @en Write all config files with the current settings.
## &en Get all modules to write and overwrite config files with the actual configurations.
## &en

msg "-- Calling all hooks --"

run_hooks regenerate
