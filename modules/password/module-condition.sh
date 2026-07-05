#! /bin/bash

## password module condition - evaluated in a command substitution at init.
## Pure library module (no host requirements): always enabled.
## Must print exactly "true" so SC_USE_PASSWORD=true lands in modules.conf.

echo true