#! /bin/bash

## modules/ssh/module-condition.sh
## Module condition for the ssh module, evaluated at init in a subshell
## by test_srvctl_modules (commonlib.sh); the value echoed on stdout is
## cached in modules.conf as SC_USE_SSH. Unconditionally true: the ssh
## module is enabled on every install (host or container, root or
## user), although everything meaningful in it is gated behind
## host-only hooks.

echo true
