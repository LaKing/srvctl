# nfs — v3 fact sheet (commit 988c38c)

## Purpose
Cluster-internal NFS sharing of each host's `/srv` (container rootfs tree) over the OpenVPN mesh (`10.15.x.y`). Every cluster host exports `/srv` and mounts every cluster host's `/srv` under `/var/srvctl3/nfs/<host>/srv`, so that other modules (notably `usersonhost`) can reach containers that live on remote hosts. Four files total; no commands, no conf templates.

## Activation
`modules/nfs/module-condition.sh:3` simply sources `modules/containers/module-condition.sh`, so nfs is enabled exactly when the containers module is: HOSTNAME not `localhost.localdomain`, not running inside a container (`systemd-detect-virt -c` not nspawn/lxc), and either the host appears in `/etc/srvctl/hosts.json` (with `$SC_HOSTNET` set or `/etc/srvctl/data` present), or `CMD == update-install` with an `$ARG`. Conditions are evaluated in a command-substitution subshell (`commonlib.sh:436`), so the `readonly SC_VIRT` inside the sourced containers condition does not leak. There is no independent opt-out for NFS: every cluster host gets the export and the mounts.

## Commands
-

(No `commands/` directory; the module is hook-and-lib only.)

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/update-install-host.sh` | `run_hook update-install-host` during `sc update-install` on a host | `msg "Install NFS"`; writes `/etc/exports` via `nfs_generate_exports`; opens firewalld services `nfs`, `mountd`, `rpc-bind` (`firewalld_add_service`); runs `nfs_mount`; then `add_service rpcbind` and `add_service nfs-server` (enable + restart + status, symlink into `/etc/srvctl/system/`) |
| `hooks/regenerate.sh` | `run_hook regenerate` — fired by `sc regenerate` (containers/commands/regenerate.sh:30) and inside `add-ve.sh:38`, `add-ve-user.sh:37`, `add-network-ve.sh:47` | Calls `nfs_mount` (re-mounts all cluster hosts; see bugs re: no already-mounted check) |
| `hooks/diagnose.sh` | `run_hook diagnose` during `sc diagnose` | Prints `-- NFS host shares --`; for each host in `get cluster host_list`: pings the host by name (timeout 1); on success runs `showmount -e "$host"` (no timeout), else `err "Ping of $host failed"`; ends with explicit `return 0` so the hook chain's `exif` (commonlib.sh:104) never aborts srvctl |

## Libs
`libs/nfslib.sh` (sourced by `load_libs` whenever `SC_USE_NFS=true`):

| function | behavior | external users |
|---|---|---|
| `nfs_generate_exports` (nfslib.sh:3-10) | Overwrites `/etc/exports` with a 2-line file: `## $SRVCTL generated` + `/srv 10.15.0.0/255.255.0.0(rw,no_root_squash)`. Does not run `exportfs -r` itself (relies on the later `nfs-server` restart) | only `hooks/update-install-host.sh:5` |
| `nfs_mount` (nfslib.sh:12-35) | For each host in `get cluster host_list`: reads `hostnet` from datastore, pings `10.15.<hostnet>.1` (timeout 1); if OK, `showmount -e <host>` (timeout 1); if OK, `mkdir -p /var/srvctl3/nfs/<host>/srv` (timeout 1) then `mount 10.15.<hostnet>.1:/srv /var/srvctl3/nfs/<host>/srv`. Errors are non-fatal (`err`) | `hooks/regenerate.sh:3`, `hooks/update-install-host.sh:11`; the resulting mount path is consumed by `modules/usersonhost/main.js:249` |

No other module calls these functions directly; the **path contract** `/var/srvctl3/nfs/<host>/srv` is the cross-module interface.

## Config & templates
- (no `conf/` directory)

Generated config: `/etc/exports` (written wholesale by `nfs_generate_exports`, nfslib.sh:5-8).

## State touched
- Host files: `/etc/exports` (overwritten); `/etc/firewalld/services/*.xml` only if service defs were missing (via `firewalld_add_service`); `/etc/srvctl/system/rpcbind.service` and `/etc/srvctl/system/nfs-server.service` symlinks (via `add_service`, modules/srvctl/libs/systemdlib.sh:9-10).
- Directories/mounts: `/var/srvctl3/nfs/<host>/srv` created and NFS-mounted for every cluster host (including the local host). Mounts are runtime-only — no fstab/automount/systemd mount units; they exist only after a `regenerate`/`update-install` run.
- systemd units: `firewalld.service` started; `rpcbind.service`, `nfs-server.service` enabled + restarted.
- firewalld: permanent services `nfs`, `mountd`, `rpc-bind` added to the default zone (+ `firewall-cmd --reload` inside firewalldlib).
- Datastore keys read: `cluster host_list` (nfslib.sh:17, diagnose.sh:5), `host <name> hostnet` (nfslib.sh:19). Nothing written.
- Network: NFS/mountd/rpcbind traffic over the OpenVPN mesh `10.15.<hostnet>.1`; exports `/srv` rw to `10.15.0.0/16`.

## Dependencies
- Core helpers: `msg`, `err` (lablib.sh:23,87), `run` (lablib.sh:93 — echoes command, executes unquoted `$*`, `eyif`-warns on nonzero except exit 3), `eyif` (lablib.sh:148).
- Datastore module: `get` (modules/datastore/libs/bashlib.sh:20) → node `main.js`; `cluster host_list` = all keys of hosts.json (modules/datastore/lib.js:1014-1019, no self-exclusion).
- firewalld module: `firewalld_add_service` (modules/firewalld/libs/firewalldlib.sh:3).
- srvctl module: `add_service` (modules/srvctl/libs/systemdlib.sh:3; a duplicate definition exists in fedoralib.sh:33 — systemdlib's wins, sourced later alphabetically).
- openvpn module: assumed operational (mesh IPs `10.15.<hostnet>.1` must be reachable).
- containers module: condition file reused; `/srv` layout comes from it.
- External binaries: `ping`, `timeout`, `showmount`, `mount` (mount.nfs), `mkdir`, `systemctl`, `firewall-cmd`, plus kernel NFS server. **`nfs-utils` is never installed by srvctl** (no reference anywhere in the repo).

## Bugs & smells
- **medium** nfslib.sh:17-27 — `nfs_mount` iterates all of `cluster host_list` with no `$host == $HOSTNAME` skip, so each host NFS-loopback-mounts its own `/srv` at `/var/srvctl3/nfs/$HOSTNAME/srv`. Consumers never use that path for the local host (`modules/usersonhost/main.js:248-250` only uses it when `host !== HOSTNAME`); loopback NFS mounts are deadlock-prone under memory pressure and add a useless failure surface.
- **medium** nfslib.sh:27 — no already-mounted check before `mount`. `regenerate` fires on every `sc regenerate`, `add-ve`, `add-ve-user`, `add-network-ve`; each run re-mounts the same target, stacking duplicate NFS mounts (or emitting a spurious `eyif "command ... returned with an error"` on mount versions that refuse), so long-lived hosts accumulate stacked mounts / noisy errors.
- **medium** hooks/update-install-host.sh:3-14 — "Install NFS" never installs the `nfs-utils` package (grep of the whole repo finds no `nfs-utils`); on a minimal Fedora host `showmount`/`mount.nfs` are missing, every mount check fails, and `add_service nfs-server` ends in `err "No such service - nfs-server"` (systemdlib.sh:33) — the export in `/etc/exports` is written but never served.
- **low** hooks/update-install-host.sh:11-14 — `nfs_mount` runs before `rpcbind`/`nfs-server` are enabled/started, so on first bootstrap the `showmount` probes (including to self) fail and print `Could not mount ...` errors; mounts only materialize on a later regenerate.
- **low** hooks/diagnose.sh:9 — `run showmount -e "$host"` has no `timeout` (unlike nfslib.sh:24); a host that answers ping but filters RPC stalls `sc diagnose` for the full RPC timeout per host.
- **low** hooks/diagnose.sh:7 — diagnose pings `$host` by DNS name (public route) while actual NFS traffic uses `10.15.$hs.1` (nfslib.sh:21,27); the diagnostic can pass on a path NFS does not use, or report failure when the VPN path is fine.
- **low** nfslib.sh:5 — `cat > /etc/exports` clobbers the whole file, silently destroying any admin-maintained export lines on the host.
- **low** nfslib.sh:17 — loop variable `host` is not `local` (only `hs` is); hooks are sourced into the main shell, so `nfs_mount` overwrites a global `host` that other sourced hook/lib code in the same run also uses.
- smell (security) nfslib.sh:7 — `/srv` exported `rw,no_root_squash` to the entire `10.15.0.0/16`; any compromised cluster member gets root-equivalent write access to every other host's `/srv`.
- smell nfslib.sh:26 — `mkdir -p` result is ignored; if a stale NFS mount makes it hang (timeout → 124), the code still mounts on top of the stale mount (accidental self-healing, not a checked path).
- smell nfslib.sh:29 — error text says "Could not mount" but the failed step is the `showmount` probe; misleading during diagnosis.
- smell hooks/regenerate.sh — never re-generates `/etc/exports`; only `update-install` restores it if lost/edited.
- smell — mounts are not persistent (no fstab/automount); after reboot remote container shares are absent until something runs the regenerate hook.

## Polish risks
- Mount-path contract `/var/srvctl3/nfs/<host>/srv` (nfslib.sh:26-27) — hard-coded consumer at modules/usersonhost/main.js:249; any rewrite must keep the exact path scheme.
- `/etc/exports` content (nfslib.sh:6-7): header line `## $SRVCTL generated` (SRVCTL = `srvctl-<version>`, srvctl.sh:103) and export line `/srv 10.15.0.0/255.255.0.0(rw,no_root_squash)` — netmask form, options, no fsid; peers depend on `/srv` being the export root (mount source is `10.15.<hostnet>.1:/srv`, nfslib.sh:27).
- VPN address scheme `10.15.<hostnet>.1` for both reachability probe and mount source (nfslib.sh:21,27); `hostnet` comes from datastore key `host <name> hostnet` (nfslib.sh:19).
- firewalld service names exactly `nfs`, `mountd`, `rpc-bind` (update-install-host.sh:7-9).
- systemd units `rpcbind.service`, `nfs-server.service` enabled + restarted, and symlinked into `/etc/srvctl/system/` via `add_service` (update-install-host.sh:13-14).
- Hook filenames/lifecycle points: `update-install-host.sh`, `regenerate.sh`, `diagnose.sh` — regenerate is invoked from add-ve/add-ve-user/add-network-ve flows, so nfs_mount must stay cheap and non-fatal there.
- Non-fatal error handling: all failures in `nfs_mount` go through `err` and never abort (nfslib.sh:29,32); `diagnose.sh:15` ends with explicit `return 0` — because `run_hook` wraps each sourced hook in `exif` (commonlib.sh:104), a rewrite that lets a nonzero status escape a hook would abort the whole srvctl run.
- Output strings logged to `$SC_LOG` via `err`: `Could not mount $host 10.15.$hs.1` (nfslib.sh:29), `Could not ping $host on 10.15.$hs.1` (nfslib.sh:32), `Ping of $host failed` (diagnose.sh:11); msg strings `Install NFS` (update-install-host.sh:3), `nfs mount` (nfslib.sh:14), `openvpn connection check to $host ($hs)` (nfslib.sh:20), `mount check on  $host ($hs)` — note the double space (nfslib.sh:23), `-- NFS host shares --` (diagnose.sh:4).
- 1-second probe timeouts (`timeout 1 ping -c 1 -W 1`, `timeout 1 showmount`) bound regenerate latency per host (nfslib.sh:21,24,26); raising them slows every add-ve on clusters with dead hosts.
- Activation must remain identical to the containers module (module-condition.sh:3), including the `update-install`+ARG bootstrap path.

## v4 notes
- The whole module is ~60 lines; in v4 this collapses into a `cluster-share` concern: an .mjs "mesh mounts" service that reads hosts.json once, computes desired mounts, diffs against `/proc/self/mountinfo`, and mounts/umounts idempotently (fixes stacking and removes the need to shell out per host). Stale-host cleanup (hosts removed from cluster) falls out for free from the diff.
- Replace runtime `mount` calls with generated systemd `.mount`/`.automount` units (or `x-systemd.automount` fstab entries) so remote shares survive reboot and hung servers don't block regenerate; regenerate then just re-emits units.
- `get cluster host_list` + `get host X hostnet` cost one `node` process each (datastore/bashlib.sh) — in v4 read the datastore once in-process.
- Ping/showmount probing duplicates openvpn-mesh health checks (openvpn and gluster modules do the same host_list loop pattern, e.g. glusterlib.sh:55, openvpnlib.sh:33); one shared "peer reachability" helper should serve all three.
- Skip self-host; consider `root_squash` + per-container exports or an `fsid`, and installing `nfs-utils` explicitly in the install hook.
- diagnose should probe the same path as production traffic (VPN IP, with timeout) and could compare expected vs actual mounts.
- Duplicate `add_service` definitions (srvctl/libs/fedoralib.sh:33 vs systemdlib.sh:3) is a core-level cleanup this module currently depends on load-order to resolve.
