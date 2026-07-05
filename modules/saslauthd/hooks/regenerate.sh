#!/bin/bash

## Regenerate hook: fired by the regenerate pipeline (add-ve, add-ve-user,
## add-network-ve, add-codepad, the regenerate command, ...). Restarts the
## host saslauthd.service via the module lib so SMTP AUTH picks up changes.

## FIXME(v4): restarts saslauthd on every regenerate even though nothing in
## its config is domain-dependent — momentary SMTP AUTH outage for all mail
## users on each container operation.
restart_saslauthd
