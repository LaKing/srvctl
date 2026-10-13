#!/bin/bash
## Renamed to checkpoint.sh; kept so existing calls keep working.
echo "push.sh is now checkpoint.sh" >&2
exec /bin/bash "$(dirname "${BASH_SOURCE[0]}")/checkpoint.sh" "$@"
