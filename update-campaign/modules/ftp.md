# module ftp — v3 fact sheet (commit 988c38c)

## Purpose
Minimal host-side FTP enablement: during host installation/update it installs the `vsftpd`
package and opens the stock `ftp` service (TCP/21 + conntrack helper) in firewalld.
That is the module's entire footprint — 3 files, 9 lines, unchanged since 2018
(`git log`: created 44b936f 2018-06-08, condition tweaked deab3f2 2019-01-07).
It has no commands, no libs, no conf, and it never configures, enables or starts the
vsftpd service itself (see Bugs).

## Activation
`modules/ftp/module-condition.sh:4` contains only
`source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"` — the ftp module is
enabled exactly when the **containers** module is, i.e. on container-farm hosts:

- `false` if `$HOSTNAME == localhost.localdomain` (containers/module-condition.sh:3-7)
- `false` inside a container (`systemd-detect-virt -c` = `systemd-nspawn`/`lxc`) when
  `$SC_HOSTNET` is set or `/etc/srvctl/data` exists (containers/module-condition.sh:9-19)
- `true` if the hostname appears quoted in `/etc/srvctl/hosts.json` (containers/module-condition.sh:21-25)
- bootstrap escape hatch: `true` whenever `CMD == update-install` and an `$ARG` is given
  (containers/module-condition.sh:28-32)

Conditions are evaluated in a subshell (`trtm="$(source …)"`, commonlib.sh:436) so the
`readonly SC_VIRT` inside the sourced file does not leak. Result is cached as
`export SC_USE_FTP=true|false` in `/var/local/srvctl/modules.conf` (root) or
`~/.srvctl/modules.conf` and only re-tested on `update-install`/`test-modules` or when the
cache file is missing (commonlib.sh:422-450). The ftp module inherits the containers
condition's bootstrap edge case verbatim (any `update-install ARG` run enables it, even on
machines not in `hosts.json`).

## Commands
-

(The module has no `commands/` directory.)

## Hooks
| hook file | lifecycle point | what it does |
|---|---|---|
| `hooks/update-install-host.sh` | `run_hooks update-install-host`, fired from `modules/srvctl/commands/update-install.sh:83` during `sc update-install HOSTNAME` on a host | `sc_install vsftpd` (line 3) — `dnf -y -q install vsftpd` via modules/srvctl/libs/fedoralib.sh:6-12. Does not enable/start/configure the service. |
| `hooks/firewalld.sh` | `run_hooks firewalld`, fired (nested) from `modules/firewalld/hooks/update-install-host.sh:12` and `modules/firewalld/hooks/update-install-ve.sh:12` | `firewalld_add_service ftp` (line 3) — via modules/firewalld/libs/firewalldlib.sh:3-49: starts firewalld, and unless the service is already in the default zone, runs `firewall-cmd --zone=<default> --permanent --add-service=ftp` + `--reload`, using the stock `/usr/lib/firewalld/services/ftp.xml` (21/tcp + FTP conntrack helper). |

Ordering note: `SC_MODULES` is built by alphabetical glob (srvctl.sh:72-75), and
`firewalld` sorts before `ftp`, so during `run_hooks update-install-host` the nested
`firewalld` hook (which opens port 21) executes **before** `ftp/hooks/update-install-host.sh`
installs vsftpd. Neither depends on the other, so this is harmless today.
The `update-install-ve` trigger path is moot in practice: inside a VE, `SC_USE_FTP` is
false (containers condition), and `run_hook` skips hooks of disabled modules
(commonlib.sh:93).

## Libs
-

(No `libs/` directory; the module consumes `firewalld_add_service` from the firewalld
module and `sc_install` from the srvctl module, provides nothing to others.)

## Config & templates
-

(No `conf/` directory. No vsftpd.conf template exists anywhere in the repo; vsftpd runs
with distro defaults if anyone ever starts it.)

## State touched
- **Host packages:** installs `vsftpd` RPM (hooks/update-install-host.sh:3).
- **firewalld permanent config:** adds service `ftp` to the default zone; runs
  `firewall-cmd --reload`; starts `firewalld.service` as a side effect
  (firewalldlib.sh:5,30,44,47). Only if the stock `/usr/lib/firewalld/services/ftp.xml`
  were missing would it write `/etc/firewalld/services/ftp.xml` (with empty proto/port —
  see firewalld module's fact sheet).
- **Network:** exposes TCP/21 (and passive FTP via the nf_conntrack_ftp helper referenced
  by the stock service definition) on the host.
- **Not touched:** no systemd unit is enabled (`vsftpd.service` untouched), no container
  paths, no datastore keys.

## Dependencies
- **containers module** — its `module-condition.sh` is sourced by absolute path
  (module-condition.sh:4); if that file moved, ftp would silently evaluate to disabled.
- **firewalld module** — defines `firewalld_add_service` (libs are only loaded for enabled
  modules, commonlib.sh:47-66) and is the sole trigger of the `firewalld` hook; if
  `SC_USE_FIREWALLD` were false, ftp's firewall hook never runs.
- **srvctl module** — `sc_install` (fedoralib.sh:6; defined only when `ID == fedora`,
  fedoralib.sh:3) and the `update-install` command that fires `update-install-host`.
- **Core helpers:** `run_hook`/`run_hooks` (commonlib.sh:85-114), `run`, `exif`/`eyif`,
  `msg`/`ntc` (lablib.sh).
- **External binaries:** `dnf`, `firewall-cmd`, `systemctl`.

## Bugs & smells
- **medium** modules/ftp/hooks/update-install-host.sh:3 — vsftpd is installed but never
  configured, enabled, or started (no `conf/`, no `add_service vsftpd`, nothing anywhere
  in the repo touches vsftpd besides this line), while documentation.md:1229 claims the
  module "installs and configures vsftpd". Concrete harm: after `sc update-install`,
  port 21 is opened in firewalld but no FTP daemon runs — the module delivers no working
  FTP, and an admin who manually starts vsftpd gets untracked distro-default config.
- **low** modules/ftp/hooks/firewalld.sh:3 — plaintext-FTP port 21 is opened permanently
  in the default zone on every container-farm host on every `update-install`, with no
  opt-out short of disabling the module (whose condition is just "is a containers host").
  Harm: standing firewall exposure for a service that is not even running.
- **low** modules/ftp/hooks/update-install-host.sh:3 — the hook's exit status is dnf's;
  on a transient repo/dnf failure `run_hook`'s `exif` (commonlib.sh:104) aborts the entire
  `sc update-install` run mid-way (message "`$dir hook 'update-install-host' failed`") for
  a nonessential package. (`run` itself only `eyif`-warns, lablib.sh:108-111, but still
  propagates the code as the hook's return value.)

## Polish risks
- Hook filenames are the contract: `hooks/update-install-host.sh` and
  `hooks/firewalld.sh` are looked up literally as `$dir/hooks/$hook.sh`
  (commonlib.sh:97); renaming either silently detaches the module.
- Module directory name `ftp` produces the cached variable name `SC_USE_FTP`
  (commonlib.sh:431,448) persisted in modules.conf files on production hosts.
- firewalld service name must stay exactly `ftp` — idempotency depends on
  `firewall-cmd --permanent --query-service=ftp` matching prior runs
  (firewalldlib.sh:21) and on the stock `/usr/lib/firewalld/services/ftp.xml` existing
  (firewalldlib.sh:27); a renamed service would re-add a second service and change the
  "already enabled" detection.
- Package name `vsftpd` installed via plain `dnf -y -q install` (fedoralib.sh:10) —
  rerunning must stay a no-op.
- `module-condition.sh` must emit exactly `true` on stdout to enable
  (commonlib.sh:437); it currently emits whatever the containers condition emits —
  keep the delegation semantics (including the `update-install + ARG` bootstrap path).
- Preserve hook exit-status semantics: both hooks currently end in a command whose
  status propagates to `run_hook`'s `exif`; a rewrite that swallows failures changes
  update-install abort behavior.
- User-visible strings on rerun come from shared helpers, not this module
  ("firewalld: ftp is enabled already." firewalldlib.sh:23; "Service ftp already
  defined in firewalld" firewalldlib.sh:29) — nothing module-local to preserve.

## v4 notes
- This module is a 2-line policy statement ("open ftp; install vsftpd"). In v4 it should
  not be a standalone module: fold it into a declarative host-provisioning manifest
  (packages: [vsftpd], firewall-services: [ftp]) consumed by one .mjs installer, as the
  identical pattern recurs in nfs, postfix, perdition, codepad, gui, sshpiperd hooks.
- The condition-by-sourcing-another-module's-condition trick (also used elsewhere) should
  become an explicit declared dependency (`requires: containers`) in module metadata.
- Decide the module's fate: either finish it (ship a vsftpd.conf template, enable the
  service, passive port range + matching firewall rule, per-user/container FTP roots) or
  drop it and stop opening port 21 fleet-wide. As-is it is half-implemented; the
  coverage matrix already lists it as "undecided" (update-campaign/000-COVERAGE.md:38).
- If kept, prefer FTPS or drop FTP for SFTP via the existing sshpiperd/ssh plumbing —
  plaintext FTP plus conntrack-helper dependence is legacy.
