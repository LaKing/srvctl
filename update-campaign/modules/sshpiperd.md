# sshpiperd — v3 fact sheet (commit 988c38c)

## Purpose
Installs and wires up a patched build of tg123/sshpiper (`sshpiperd`) on container-host machines. The daemon listens on TCP 2222 and reverse-proxies SSH sessions into nspawn containers using a composite username scheme `<user>_<container>_<account>`: it dials `<container>:22` and logs in as `<account>`, authenticating the client against the user's public keys from the srvctl datastore and signing upstream with the user's `srvctl_id_ecdsa` key. The module ships a prebuilt 6.3 MB Go binary (`modules/sshpiperd/sshpiperd`), the patched source file (`workingdir.go`), a rebuild script (`build.sh`), a systemd unit, and a bindfs mount of the datastore users dir at `/var/sshpiper` (the daemon's working dir).

## Activation
`module-condition.sh:3` just sources `modules/containers/module-condition.sh`, so activation is identical to the containers module: enabled when the host is not `localhost.localdomain`, not itself a container (`systemd-detect-virt -c` not nspawn/lxc), and (`$SC_HOSTNET` set or `/etc/srvctl/data` exists) with `$HOSTNAME` present in `/etc/srvctl/hosts.json`; also force-enabled during `sc update-install <arg>` (containers/module-condition.sh:3-32). Note containers' condition file declares `readonly SC_VIRT` — harmless here only because conditions are evaluated in a `$( source ... )` subshell (commonlib.sh:436).

## Commands
| command | hint | behavior | side effects |
|---|---|---|---|
| (none) | - | Module has no `commands/` directory. `build.sh` at module root is a developer-only rebuild script, not wired into dispatch (no `## @en` header, not executable, uses `run` which is undefined outside srvctl context). | build.sh, if it worked: installs golang, `go get`s sshpiper, patches `workingdir.go`, builds, copies to `/bin/sshpiperd`, restarts service via `sc sshpiperd !` |

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/regenerate.sh` | `run_hook regenerate` — fired by `sc regenerate` (incl. hourly cron `/etc/cron.hourly/srvctl-regenerate.sh` installed by containers module), `add-ve`, `add-ve-user`, `add-codepad`, `add-network-ve`, regenlib | Calls `mount_sshpiper` (ensures the bindfs mount is present). |
| `hooks/update-install-host.sh` | `run_hooks update-install-host` — host part of `sc update-install` (modules/srvctl/commands/update-install.sh:83) | Creates system user `sshpiper`; `mkdir -p /var/sshpiper`; `sc_install bindfs`; mounts via `mount_sshpiper`; `mkdir -p /etc/sshpiper`; generates ECDSA host key at `/etc/sshpiper/ssh_host_rsa_key` if absent; `chown -R sshpiper:root /etc/sshpiper`; removes legacy `/usr/lib/systemd/system/sshpiperd.service`; copies the vendored binary to `/bin/sshpiperd`; installs `/etc/systemd/system/sshpiperd.service`; `systemctl daemon-reload`; opens firewalld service `sshpiperd` tcp 2222. Never enables or starts the service. |

## Libs
`libs/sshpiperlib.sh` provides a single function, sourced globally by `load_libs` whenever the module is enabled:
- `mount_sshpiper()` (sshpiperlib.sh:3-13) — if `mount | grep "on /var/sshpiper type fuse"` finds nothing, runs `bindfs -r -p +X --map=root/sshpiper /var/srvctl3/datastore/users /var/sshpiper`. Used only by this module's own two hooks; no other module or core code calls it (verified by grep). A commented-out line (:9) shows an older gluster source path.

## Config & templates
- `services/sshpiperd.service` → copied verbatim to `/etc/systemd/system/sshpiperd.service` (hooks/update-install-host.sh:28). Unit: `ExecStart=/bin/sshpiperd --server_key /etc/sshpiper/ssh_host_rsa_key`, `User=sshpiper`, `Group=sshpiper`, `Restart=always`, `RestartSec=3`, `WantedBy=multi-user.target`. No `--working_dir` flag, so the daemon uses upstream default `/var/sshpiper`.
- `sshpiperd` (6.3 MB prebuilt Go binary, vendored in git) → copied to `/bin/sshpiperd` (hooks/update-install-host.sh:26). Embedded banner shows it was built at srvctl 3.1.2.1 (repo is at 3.2.5.9).
- `workingdir.go` — patched upstream source used only by `build.sh`; `@SRVCTL_VERSION` token substituted at build time (build.sh:28).
- No `conf/` directory.

## State touched
- Host paths: `/bin/sshpiperd`, `/etc/systemd/system/sshpiperd.service`, `/etc/sshpiper/ssh_host_rsa_key{,.pub}`, `/var/sshpiper` (bindfs read-only view of `/var/srvctl3/datastore/users`, root remapped to sshpiper), `/etc/firewalld/services/sshpiperd.xml`, removes `/usr/lib/systemd/system/sshpiperd.service`.
- System accounts: system user (and group) `sshpiper`.
- systemd units: `sshpiperd.service` (installed + daemon-reload; not enabled/started by the module).
- Network: listens on TCP 2222 (firewalld service `sshpiperd`, opened to the default zone); dials `<container>:22` upstream.
- Datastore (read-only, via bindfs): per-user dirs under `/var/srvctl3/datastore/users/<user>/` — reads `*.pub` and `srvctl_id_ecdsa` (deployed binary: `srvctl_id_rsa`, see Bugs); also reads `/var/srvctl3/share/common/authorized_keys` (workingdir.go:176).
- Dev-only (build.sh): `/root/go` GOPATH, dnf-installs golang.

## Dependencies
- Core helpers: `msg`, `run`, `debug` (lablib.sh), `run_hook`/`run_hooks` dispatch (commonlib.sh:85-114).
- Other modules: `containers` (module condition, cron-driven regenerate that keeps the mount alive), `srvctl` (`sc_install` from fedoralib.sh:6, `update-install` command, generic `sc <service> !` service dispatch in modules/srvctl/command.sh used by build.sh), `firewalld` (`firewalld_add_service`, firewalldlib.sh:3), `ssh`/`usersonhost` (create the `srvctl_id_ecdsa` keypairs and `*.pub` files in the datastore that the daemon consumes — userlib.sh:38-41, main.js:140-147), `datastore` (layout of `/var/srvctl3/datastore/users`).
- External binaries: `bindfs` (FUSE), `ssh-keygen`, `adduser`/`useradd`, `systemctl`, `firewall-cmd`, `mount`, `grep`; build-time: `dnf`, `go`, `golang` toolchain.

## Bugs & smells
- **high** `modules/sshpiperd/sshpiperd` (deployed by `hooks/update-install-host.sh:26`) — the vendored binary is stale relative to its own source: binary strings contain `srvctl_id_rsa` and no `srvctl_id_ecdsa`, and its banner says srvctl 3.1.2.1, while `workingdir.go:30` was changed to `srvctl_id_ecdsa` after 3.1.2.6 (git: 245c87c→e179f53 diff) and the rest of srvctl only generates `srvctl_id_ecdsa` (modules/ssh/libs/userlib.sh:38-41, modules/usersonhost/main.js:140). On a host installed from this repo, the daemon looks up a per-user private key file (`<user>/srvctl_id_rsa`) that srvctl never creates, so upstream key mapping can never succeed except via legacy leftover files.
- **high** `modules/sshpiperd/workingdir.go:137-138` — `strings.Split(user,"_")[1]`/`[2]` runs *before* the `checkUsername` regexp check (line 140). Any SSH connection whose username has fewer than two `_` (e.g. bots trying `root` on the world-open port 2222) triggers an index-out-of-range panic inside the daemon; unless upstream wraps the callback in `recover`, the process dies (systemd restarts it after 3 s), giving a trivial unauthenticated remote DoS. Same ordering exists in the source the vendored binary was built from (git show 245c87c).
- **medium** `modules/sshpiperd/hooks/update-install-host.sh:28-29` — the unit is installed and `daemon-reload` run, but the service is never `enable`d or `start`ed. A fresh `sc update-install` leaves sshpiperd dead until an operator manually runs `sc sshpiperd !` (only build.sh:44 does that, and only for the author).
- **medium** `modules/sshpiperd/workingdir.go:192-196` — in the authorized-key scan, any parse error from `ssh.ParseAuthorizedKey` (one malformed/comment line in any `<user>/*.pub` or in `/var/srvctl3/share/common/authorized_keys`) aborts the whole loop and denies auth, silently blocking all keys that appear after the bad line.
- **low** `modules/sshpiperd/build.sh:7-10` — inverted test: warns "workingdir.go - patch file missing" when the file *exists*, and does nothing (no abort) when it is actually missing; then `build.sh:26` (`cat workingdir.go > $GOPATH/.../workingdir.go`) truncates the upstream file to empty if run from the wrong cwd.
- **low** `modules/sshpiperd/build.sh:31-32` — uses the `run` helper but the script is standalone (never sourced in srvctl context, no lablib), so `run: command not found` and the build can never complete as `bash build.sh`; additionally the GOPATH `go get` workflow (:19-22) is dead under module-mode Go, and the `@SRVCTL_INSTALL_DIR` sed (:29) is a no-op — the token no longer exists in workingdir.go.
- **low** `modules/sshpiperd/workingdir.go:176` — shell command built by string-concatenating the client-supplied username into `bash -c "cat …/<user>/*.pub …"`. Safe today only because `checkUsername` (:165) runs first; if the daemon were ever started with `--allow_bad_username` (checkUsername short-circuits true, :86-88) this is remote shell injection as user `sshpiper`.
- **low** `modules/sshpiperd/libs/sshpiperlib.sh:10` + `hooks/regenerate.sh:3` — the bindfs mount is created only at hook time and is not in fstab or a .mount unit; after a host reboot `/var/sshpiper` is an empty dir (sshpiperd still runs, all auth fails) until the hourly `srvctl regenerate` cron remounts it — up to ~1 h SSH-proxy outage per reboot. Also, if `mount_sshpiper` fails (bindfs missing), the sourced hook's non-zero status makes `run_hook`'s `exif` (commonlib.sh:104) abort the entire `regenerate` run.
- smell `modules/sshpiperd/hooks/update-install-host.sh:15-18` — generates an **ecdsa** key but names it `ssh_host_rsa_key`; misleading but load-bearing (unit references it).
- smell `modules/sshpiperd/libs/sshpiperlib.sh:10` — hardcodes `/var/srvctl3/datastore/users` instead of `$SC_DATASTORE_RW_DIR/users`.
- smell `modules/sshpiperd/hooks/update-install-host.sh:23-24` — "TODO remove after upgrade" legacy cleanup (`rm -fr /usr/lib/systemd/system/sshpiperd.service`) still runs on every update-install.
- smell `modules/sshpiperd/workingdir.go:26-34,94-130` — `UserAuthorizedKeysFile`, `UserUpstreamFile` and `parseUpstreamFile` are dead code in the patched version; `workingdir.go:147` `addr == ""` check is unreachable (addr always ends `:22`).

## Polish risks
A rewrite must preserve exactly:
- Binary path `/bin/sshpiperd` (services/sshpiperd.service:7, hooks/update-install-host.sh:26, build.sh:5,38).
- Unit name/path `/etc/systemd/system/sshpiperd.service` and its contents: `ExecStart=/bin/sshpiperd --server_key /etc/sshpiper/ssh_host_rsa_key`, `User=sshpiper`, `Group=sshpiper`, `Restart=always`, `RestartSec=3` (services/sshpiperd.service:5-11).
- Host-key path and (misleading) filename `/etc/sshpiper/ssh_host_rsa_key`, generated `-t ecdsa -N ''` (hooks/update-install-host.sh:18) — regenerating or renaming it breaks known-host pinning for every user of port 2222.
- System user name `sshpiper` and ownership `sshpiper:root` on `/etc/sshpiper` (hooks/update-install-host.sh:6,21).
- Mount: exact bindfs invocation `bindfs -r -p +X --map=root/sshpiper /var/srvctl3/datastore/users /var/sshpiper` (sshpiperlib.sh:10) and mountpoint `/var/sshpiper` (= daemon's default WorkingDir); idempotence check greps `"on /var/sshpiper type fuse"` (sshpiperlib.sh:5).
- Firewalld service name `sshpiperd`, tcp/2222 (hooks/update-install-host.sh:31) — the public contract port.
- Composite username wire format `<user>_<container>_<account>` and its regexp `^[a-z][-a-z0-9\.]{0,31}_[-a-z0-9\.]{0,256}_[-a-z0-9]{0,31}$` (workingdir.go:42,137-138); upstream is always `<container>:22` (workingdir.go:144).
- Key filenames consumed from the datastore: `<user>/*.pub`, `<user>/srvctl_id_ecdsa` (workingdir.go:30,176) and the extra global keys file `/var/srvctl3/share/common/authorized_keys` (workingdir.go:176) — shared contracts with the ssh, usersonhost and gui modules.
- 0077-perm check on the mapped private key (workingdir.go:77) — datastore key files must stay 0600-equivalent through the bindfs view.

## v4 notes
- The whole module is really three concerns: (1) provision a binary + unit + firewall port, (2) keep a bindfs view of datastore users mounted, (3) the Go mapping logic. Only (3) is srvctl-specific; it is ~80 lines and maps cleanly onto modern sshpiperd's plugin API — a small .mjs (or yaml-driven config) serving the `user_ve_as → as@ve:22` mapping and key lookup would eliminate the vendored binary, the stale-binary drift, and build.sh entirely.
- Replace hook-time `mount_sshpiper` with a proper `var-sshpiper.mount` systemd unit (or fstab entry) so the mount survives reboots; drop the mount|grep idempotence hack.
- Fix ordering: validate username with the regexp *before* splitting; enable+start the service in the install flow.
- The prebuilt-binary-in-git pattern (6.3 MB blob, embedded version 3.1.2.1) is the strongest argument in the repo for reproducible installs; v4 should pin an upstream release and verify a checksum at install time instead of vendoring.
- Duplication seen: module-condition delegating to containers (same pattern in several modules — v4 could express "requires: containers" declaratively); bindfs/dnf/firewalld install steps repeat across modules and belong in shared install primitives.
