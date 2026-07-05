#! /bin/bash

## modules/backup/module-condition.sh
## Module condition for the backup module, evaluated at init; the value
## echoed on stdout is cached in modules.conf as SC_USE_BACKUP.
## Always emits "true": the module is unconditionally enabled.

echo true
