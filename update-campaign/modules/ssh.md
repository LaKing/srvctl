# ssh — v3 fact sheet (commit 988c38c)

## Purpose
Manages SSH plumbing for the container farm: generates per-cluster ssh client config drop-ins (`/etc/ssh/ssh_config.d/srvctl-chosts.conf`, `srvctl-containers.conf`), scans and caches host keys of cluster hosts and containers into `known_hosts` files, distributes user public keys into per-container share directories (consumed by `sshd_authorization.sh` via `AuthorizedKeysCommand`), and installs a common `sshd_config` on the host and into container rootfs images. The heavy lifting is done by `ssh.js` (Node), wrapped by the bash function `ssh_main`.

## Activation
`module-condition.sh` is unconditional: `echo true` (modules/ssh/module-condition.sh:3). The module is always enabled (`SC_USE_SSH=true`) on every install, host or container, root or user.

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| - | - | The module has no `commands/` directory. (The related `fix-sshd` command lives in `modules/srvctl/commands/fix-sshd.sh`, not here.) | - |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/regenerate.sh` | `regenerate` hook (run by `containers` module commands: `regenerate`, `add-ve`, `add-ve-user`, `add-network-ve`; `codepad add-codepad`) | Calls `regenerate_ssh_config`: deletes `/var/srvctl3/share/containers/*/users/*/authorized_keys`, then runs `ssh_main` (full ssh.js pass: ssh_config drop-ins, host-key scan, known_hosts, user key copies). |
| `hooks/update-install-host.sh` | `update-install-host` (from `srvctl update-install HOSTNAME`, host only) | `mkrootfs_sshd_config /` (installs module sshd_config to the host's `/etc/ssh/sshd_config`), then `update_install_ssh_config` (mkdirs, `ssh_main`, installs sshd_config *again*, imports root authorized_keys into `/var/srvctl3/share/common/authorized_keys`, fixes perms, enables/restarts sshd). |

## Libs
| file | functions | used by |
|---|---|---|
| `libs/sshlib.sh` | `ssh_main` — runs `/bin/node $SC_INSTALL_DIR/modules/ssh/ssh.js $*` with `export SC_ROOTCA_HOST`, aborts srvctl via `exif` on failure | only within this module (both hooks) |
| `libs/bashlib.sh` | `regenerate_ssh_config`, `update_install_ssh_config`, `update_container_sshd_config` (writes module sshd_config into a given rootfs; appears unused anywhere) | this module's hooks; `update_container_sshd_config` has no callers |
| `libs/mkrootfslib.sh` | `mkrootfs_sshd_config ROOTFS` — copies module `sshd_config` into `$1/etc/ssh/sshd_config` if one exists; `err` + return otherwise | this module's update-install-host hook. NOTE: the `containers` module has its own `mkrootfs_root_ssh` (modules/containers/libs/mkrootfslib.sh:6) that *also* copies this module's `sshd_config` into new rootfs images — duplication across modules. |
| `libs/userlib.sh` | dead: `return` at line 2 skips the whole file. Contains legacy `create_user_ssh` kept "as a reference" (replaced by nodejs in usersonhost module). | none |
| `ssh.js` | `ssh_config()`, `scan_host_keys()`, `make_host_keys()`, `user_keys()` — all executed unconditionally on every invocation; `CMD`/argv is read but never used | invoked only via `ssh_main` |

## Config & templates
| file | installed to |
|---|---|
| `sshd_config` (OpenSSH 7.x-era template; `PermitRootLogin yes`, `PasswordAuthentication no`, `AuthorizedKeysCommand /usr/bin/bash /usr/local/share/srvctl/modules/ssh/sshd_authorization.sh %u`, `AuthorizedKeysCommandUser root`) | host `/etc/ssh/sshd_config` (bashlib.sh:35 and via `mkrootfs_sshd_config /`); every container rootfs `etc/ssh/sshd_config` (modules/containers/libs/mkrootfslib.sh:28 and mkrootfs_{fedora,debian,ubuntu,arch}.sh) |
| `sshd_authorization.sh` | not copied; executed in place by sshd (`AuthorizedKeysCommand`). Emits, separated by `###` lines: `/var/srvctl3/share/common/authorized_keys`; `/var/srvctl3/gluster/srvctl-data/users/$1/*.pub` and `/var/srvctl3/datastore/users/$1/*.pub`; `/var/srvctl3/share/containers/$HOSTNAME/users/*/*.pub`. Always exits 0. |
| (no `conf/` directory) | - |

## State touched
- `/etc/ssh/sshd_config` (host and every container rootfs — overwritten wholesale)
- `/etc/ssh/ssh_config.d/srvctl-chosts.conf`, `/etc/ssh/ssh_config.d/srvctl-containers.conf` (ssh.js:168,183)
- `/var/srvctl3/ssh/known_hosts` (ssh.js:274; chmod 644, bashlib.sh:53) and `/var/srvctl3/share/common/known_hosts` (ssh.js:262; bind-mounted RO into containers via datastore/lib.js:614)
- `/var/srvctl3/share/common/authorized_keys` (imported from `/etc/srvctl/data/authorized_keys` or `/root/.ssh/authorized_keys`, chmod 644; also read by sshpiperd, modules/sshpiperd/workingdir.go:176)
- `/var/srvctl3/share/containers/<C>/users/<U>/<U>-*.pub|*.hash` (copies of datastore user keys, ssh.js:110; per-container dir bind-mounted RO into container via datastore/lib.js:613)
- `$SC_DATASTORE_DIR/users/<U>/` (mkdir side effect, ssh.js:88-91); `$SC_DATASTORE_RW_DIR/users` (bashlib.sh:56)
- Datastore JSON: rewrites `$SC_DATASTORE_DIR/hosts.json` and `containers.json` adding `host_key` fields (ssh.js:197,203)
- `/srv/<C>/host_key` cache file per container (ssh.js:207,220)
- systemd: `systemctl enable/restart/status sshd` (bashlib.sh:58-60)
- network: `ssh-keyscan -t rsa -T 1 <host|container>` against every host and container in the cluster datastore (ssh.js:218,233)

## Dependencies
- Core bash helpers: `msg`, `err`, `run`, `exif` (lablib.sh), `run_hook`/`load_libs` (commonlib.sh); env `SRVCTL`, `SC_INSTALL_DIR`, `SC_HOSTNET` (guard in bashlib.sh:13), `SC_DATASTORE_DIR`, `SC_DATASTORE_RW_DIR`, `SC_ROOTCA_HOST` (exported for ssh.js but never read there)
- Node side: `modules/datastore/lib.js` (hosts/users/resellers/containers), `lablib.js` (`msg` used; `ntc`, `err`, `get`, `run`, `rok`, `exec_function` imported but unused)
- Other modules assumed: `datastore` (pre-init sets SC_DATASTORE_* and provides lib.js), `containers` (creates `/var/srvctl3/share/containers` and `/var/srvctl3/share/common` in its update-install-host hook, which runs before ssh's because SC_MODULES ordering is alphabetical; triggers the `regenerate` hook), `usersonhost` (creates `users/<u>/id_ecdsa.pub` etc. in the datastore; `add-publickey` adds `<user>-$NOW.pub`), `sshpiperd` (consumes `share/common/authorized_keys`)
- External binaries: `/bin/node`, `ssh-keyscan`, `sshd`/`systemctl`, `/usr/bin/bash`

## Bugs & smells
- **high** ssh.js:106 — `files[i].split(".")[1] === "pub"` only matches filenames with exactly one dot. Keys created by `sc add-publickey` are named `<user>-$NOW.pub` where `NOW=$(date +%Y.%m.%d-%H:%M:%S)` (init.sh:60, modules/usersonhost/commands/add-publickey.sh:19), e.g. `john-2026.07.05-01:23:45.pub` → `split(".")[1]` is `"07"`, so user-added public keys are silently never copied to `/var/srvctl3/share/containers/`, and those users cannot ssh into their containers even though host login (sshd_authorization.sh:12 reads the datastore directly) works.
- **high** ssh.js:79-114 + libs/sshlib.sh:6 — key revocation never propagates: `copy_user_key` only ever adds `<u>-*.pub` files; `regenerate_ssh_config` deletes only files literally named `authorized_keys`, and no code (including `remove-ve`) deletes `/var/srvctl3/share/containers/<C>/users/<U>/`. Removing a user from a container (or deleting their `.pub` from the datastore) leaves the copied key in place, and sshd_authorization.sh:16 keeps granting that key login as root and every user of the container indefinitely.
- **medium** sshd_authorization.sh:7 — `/var/srvctl3/share/common/authorized_keys` is emitted for *every* authenticating user (`%u` is ignored on that line), so any key in that file (root/admin keys) can log in as any local account on the host, contradicting the adjacent comment "used by root as root". On hosts using `usersonhost`, admin keys implicitly gain access to every customer account.
- **medium** ssh.js:216-224,231-238 — `ssh-keyscan` historically exits 0 even when it gets no key (down/unreachable container), so `result...split(" ")[2]` is `undefined`; `check_host_keys` then stores `host_key: undefined` and returns true, forcing a pointless hosts.json rewrite, and `check_container_host_keys` throws inside `fs.writeFileSync(path, undefined)` (ssh.js:220), dumping a stack trace via `console.log(err)` on every regenerate for every stopped container.
- **medium** ssh.js:206-227 — `/srv/<C>/host_key` is a self-written cache never re-validated against the container's actual sshd key; the commented-out `del container "$C" host_key` in modules/containers/libs/create-container.sh:56 means a rebuilt container keeps its stale key in `known_hosts` forever (mitigated for containers by `StrictHostKeyChecking no`, but the stale entry also lands in the shared `known_hosts` used for hosts, ssh.js:255-259).
- **low** ssh.js:249-251 — `hosts[i].host_ip` / `hosts[i].hostnet` are used unguarded; missing fields produce literal `undefined ssh-rsa …` / `10.15.undefined.undefined …` lines in both known_hosts files.
- **low** ssh.js:178-179 — the containers Host block sets `UserKnownHostsFile` twice (`/var/srvctl3/ssh/known_hosts` then `/dev/null`); OpenSSH first-match-wins per option makes the `/dev/null` line dead, so whichever behavior was intended, one of the two lines is a no-op.
- **low** ssh.js:141-144 + 84-100 — `user_keys` iterates the *cluster-wide* containers.json and mkdirs `/var/srvctl3/share/containers/<C>/users/<U>` for containers hosted on other machines, accumulating orphan directories on every host; also `fs.mkdirSync` without `recursive` crashes the whole run (uncaught) if `/var/srvctl3/share/containers` doesn't exist yet.
- **low** ssh.js:170 — success message says `srvctl-hosts.conf` while the file written is `srvctl-chosts.conf`; confuses operators grepping for the file.
- **low** libs/bashlib.sh:49-53 — `chown`/`chmod` on `/var/srvctl3/share/common/authorized_keys` and `/var/srvctl3/ssh/known_hosts` run even when neither import source existed, printing errors on a pristine install where those files are absent.

## Polish risks
Exact strings/paths/exit codes a rewrite must preserve:
- `AuthorizedKeysCommand /usr/bin/bash /usr/local/share/srvctl/modules/ssh/sshd_authorization.sh %u` + `AuthorizedKeysCommandUser root` (sshd_config:51-52) — hardcoded absolute path baked into every deployed host and container sshd_config; sshd validates the file's ownership/permissions.
- sshd_authorization.sh input contract (`$1` = username) and the three source paths: `/var/srvctl3/share/common/authorized_keys` (line 7, also consumed by sshpiperd workingdir.go:176), `/var/srvctl3/gluster/srvctl-data/users/$1/*.pub` + `/var/srvctl3/datastore/users/$1/*.pub` (lines 11-12, hardcoded, not SC_DATASTORE_*), `/var/srvctl3/share/containers/$HOSTNAME/users/*/*.pub` (line 16); must always `exit 0` (line 18) or sshd rejects key auth entirely.
- Drop-in filenames `/etc/ssh/ssh_config.d/srvctl-chosts.conf` and `/etc/ssh/ssh_config.d/srvctl-containers.conf` (ssh.js:168,183) and their contents (`StrictHostKeyChecking no` for localhost/containers, `UserKnownHostsFile /var/srvctl3/ssh/known_hosts`) — cluster automation (ca/netlib.sh rsync-over-ssh, backup, gluster) relies on non-interactive ssh working.
- `/var/srvctl3/ssh/known_hosts` (world-readable, bashlib.sh:53) and `/var/srvctl3/share/common/known_hosts` (bind-mounted into containers, datastore/lib.js:614); known_hosts line formats including the `10.15.<hostnet>.<hostnet>` VPN alias (ssh.js:251) and short-hostname alias (ssh.js:250).
- Copied key naming `/var/srvctl3/share/containers/<C>/users/<U>/<U>-<origfile>` (ssh.js:110) including `.hash` files (codepad's access.js consumes the same tree).
- `host_key` fields persisted into `hosts.json`/`containers.json` (ssh.js:197,203) and the `/srv/<C>/host_key` cache file (ssh.js:220) — other tooling (datastore lib.js `cluster_host_keys`) reads `host_key`.
- ssh.js exit behavior: `process.exit(111)` with `DATA-ERROR:` on write failure (ssh.js:52-56), 0 on success; `ssh_main` propagates via `exif "SSH-ERROR cfg $* ($?)"` (sshlib.sh:12) which aborts the whole srvctl run — hooks depend on this failing loudly.
- `regenerate_ssh_config` must keep deleting `/var/srvctl3/share/containers/*/users/*/authorized_keys` (sshlib.sh:6) — other modules drop such files and rely on regenerate to purge them.
- update_install_ssh_config early-returns when `SC_HOSTNET` is unset (bashlib.sh:13-16) — containers must never get the host treatment; it also unconditionally enables+restarts sshd and its final `run systemctl status sshd --no-pager` return value becomes the hook's exit status (non-zero fails `srvctl update-install` via run_hook's exif, commonlib.sh:104).
- `PermitRootLogin yes` + `PasswordAuthentication no` + `AuthorizedKeysFile .ssh/authorized_keys` in the deployed sshd_config (sshd_config:38,47,65) — root-key-based orchestration across the farm depends on these.

## v4 notes
- ssh.js carries dead copy-paste from the opendkim module (`TrustedHosts`/`SigningTable`/`KeyTable`, ssh.js:71-77) plus ~10 unused imports/helpers (`out`, `return_value`, `output`, `get`, `run`, `rok`, `exec_function`, `CMD`, `SC_UID0`, `localhost`); a v4 `.mjs` should keep only config-render, keyscan, and key-distribution functions.
- Three near-identical writers of the same `sshd_config` exist (`mkrootfs_sshd_config`, `update_container_sshd_config`, `mkrootfs_root_ssh` in the containers module) — collapse into one shared function; `update_container_sshd_config` and the whole `libs/userlib.sh` are dead and can be dropped.
- The keyscan loop is sequential with per-target `-T 1` timeout (ssh.js:218) — O(cluster size) wall time per regenerate; v4 should parallelize (Promise pool) and only scan targets whose key is missing/invalid, and scope container iteration to containers actually hosted locally.
- Filename parsing (`split(".")[1]`) should become a proper `endsWith(".pub")`, and key distribution should be a *sync* operation (copy + delete stale) so revocation works; consider replacing file copies entirely with the AuthorizedKeysCommand reading the datastore directly (it already does for host users, sshd_authorization.sh:11-12 — the container share tree exists only because the datastore is not mounted in containers; a narrower bind-mount could remove the whole copy machinery).
- The module is unconditionally enabled but everything meaningful is gated behind host-only hooks; in v4 the module-condition could be host-scoped, or the config-render part could move into the datastore/regenerate pipeline.
- known_hosts generation, ssh_config.d rendering, and user-key distribution are three independent concerns bundled in one script run; splitting them lets `regenerate` skip the expensive keyscan.
