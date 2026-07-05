#!/bin/bash

## @en List container status parameters

## VE-side status command (counterpart of containers' host-side status,
## which wins dispatch on hosts): prints this container's hostname,
## logged-in users (w) and disk usage of /home, /srv and /var. Read-only,
## no auth gate — every VE user may run it; also reached via the 'sc ?'
## alias.

## FIXME(v4): missing the standard "[[ $SRVCTL ]] || exit 10" guard —
## executing this file directly runs w/du outside srvctl.
## FIXME(v4): help metadata has only the hint line, none of the mandatory
## multi-line help lines (ampersand-en markers), so 'sc help status'
## renders an empty help body.
## FIXME(v4): hint wording nearly duplicates containers' "List container
## statuses"; when SC_USE_CONTAINERS leaks true inside a VE (update-install
## escape hatch) that command silently shadows this one.

msg "$HOSTNAME running."
msg "connected users:"
w
msg "Disk usage:"
## FIXME(v4): for non-root callers du exits 1 on unreadable subdirs; as the
## script's last command that makes run_command's exif report "'status'
## failed" and srvctl exit 1 despite full output (sizes undercounted too).
du -hs /home
du -hs /srv
du -hs /var

