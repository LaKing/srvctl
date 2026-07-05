#!/bin/bash

##
##   modules/postfix/diagnose.sh — postfix/amavis diagnostics (dead file).
##
##   Intended for 'sc diagnose': show the certificate chain served on the
##   SMTPS port and the amavisd service status. Never executed: hook
##   dispatch (run_hooks in commonlib.sh) only sources hooks/<name>.sh,
##   and this file sits at the module root instead of hooks/.
##

## FIXME(v4): medium — misplaced hook, 'sc diagnose' never runs it; note
## that if moved into hooks/ as-is, the s_client call below would hang
## waiting on stdin (needs </dev/null).
run openssl s_client -showcerts -connect localhost:465

run systemctl status amavisd.service  --no-pager -n 30