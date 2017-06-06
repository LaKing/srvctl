#!/bin/bash

## @@@ regenerate
## @en Write all config files with the current settings.
## &en Get all modules to write and overwrite config files with the actual configurations.
## &en

root_only

msg "-- Calling all hooks --"

run_hook regenerate
