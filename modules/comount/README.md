# comount

Comounts share a managed host directory between containers. The path argument
is the path inside each container. The host stores the actual files beneath
`/var/srvctl3/comount/as-codepad` or `/var/srvctl3/comount/as-root`, followed by
that full path; host `/srv` remains reserved for containers.

```bash
srvctl add-codepad-comount-to-containers /srv/mycomount \
    container1.d250.hu container2.d250.hu

srvctl add-root-comount-to-containers /srv/adminshare \
    container1.d250.hu container2.d250.hu

srvctl get container container1.d250.hu comount-mycomount
srvctl test-comount mycomount container1.d250.hu
srvctl remove-comount mycomount container1.d250.hu
```

| Command account | Container path | Actual host storage |
| --- | --- | --- |
| codepad | `/srv/mycomount` | `/var/srvctl3/comount/as-codepad/srv/mycomount` |
| root | `/srv/adminshare` | `/var/srvctl3/comount/as-root/srv/adminshare` |

The add commands create the source directory if missing, or reuse its existing
contents. They validate every target first, then assign source files to the
selected numeric backing UID/GID and grant owner read/write access (and directory traversal).
They do not import or move files from a host directory matching the argument.

The path basename is the host-unique comount identifier. For example,
`/opt/projects/assets` is named `assets` and appears at `/opt/projects/assets`
in every target. Each container can share multiple comounts. Reusing a registered
identifier with a different path or account is rejected, as are overlapping
source directories. The account is fixed for each comount; codepad and root
commands select separate storage trees, not two views of the same data.

Independent `comount-NAME` datastore fields store the managed source path.
The account and destination are derived from that path during regeneration.
Sourced functions and the `regenerate`/`update-install-host` hooks generate:

- An ID-mapped host mount at `/srv/CONTAINER/comount/NAME`.
- `/srv/CONTAINER/binds/comount-NAME.binds`, attaching it at the container path.
- A corresponding mount unit and `comount-NAME.conf` container-service drop-in.

The intermediate mount is another view of the source, not a copy. It maps the
backing UID and GID to the selected account's allocated IDs in each
container. Root shares map host `0:0` to each container's root IDs; codepad shares
use stable numeric backing IDs `804:804` and read each container codepad UID/GID
from its passwd file. Codepad shares also map host `0:0` to each container's
root IDs, allowing root to access the share and create directories and files.
Root-created files remain root-owned across containers; normal file permissions
determine codepad access to them. No host codepad account is required. Root
shares map root only and do not require codepad accounts.

Mounts follow container stop/restart jobs and stop when no active unit needs
them. Unchanged configuration does not restart containers; changed configuration
restarts targets that were already running. Stopped containers remain stopped.
The datastore UID allocation and rootfs passwd file support offline setup;
rootfs ownership must match the allocated UID offset.

`remove-comount NAME CONTAINER` removes only that membership and its generated
files. Source files and other memberships remain. Clearing a `comount-NAME`
field directly is also reconciled by regeneration. Ownership is assigned only
by add commands. `test-comount NAME CONTAINER` creates, reads, appends to and
removes a temporary directory and file as root, and also as codepad for codepad
shares, in a running target.
After updating an existing codepad-only mapping, run `srvctl regenerate` on the
host. It replaces changed mounts, restarting affected running containers without
reassigning source ownership. Re-running an add command explicitly reassigns
source ownership to the selected account, including previously root-owned files.

The `diagnose` hook reports named mounts using normal srvctl output and systemd
status. Failed application retains datastore intent for inspection and retry.

Paths must be simple absolute paths. Symlinked sources or destinations,
nonempty container destinations, conflicting binds, source submounts and
`local.nspawn` overrides are rejected. Previous configurations with arbitrary
host sources are not migrated automatically: detach those memberships and
arrange their data in the new storage tree before using the new add commands.
Remove an older unnamed manual mount before using `/srv/CONTAINER/comount/NAME`.

The original codepad mapping was verified on XFS with Linux 6.8.9,
util-linux 2.40.2 and systemd 255. The filesystem UID/GID comes first in
`X-mount.idmap`, followed by the visible target host ID; nspawn's newer
`owneridmap` is not required.

Run `bash modules/comount/selftest/comount.test.sh` for isolated tests using
temporary host paths and mocked srvctl/OS helpers. These include both account
mappings, storage creation, full destination paths, lifecycle behavior, conflicts
and failure propagation; they do not mount filesystems or start real containers.
