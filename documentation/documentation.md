# srvctl v4 — Complete Documentation

srvctl is a container farm manager for microsite hosting on Fedora servers. It uses systemd-nspawn containers and is written in bash and JavaScript/Node.js. The CLI is invoked as `srvctl` or `sc`. srvctl is deployed across many production servers. This document describes the `v4` branch; the shipped `version` file reads `4.0.0.8`, so `$SRVCTL` evaluates to `srvctl-4.0.0.8` on this tree.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Installation](#installation)
   - [Host Requirements](#host-requirements)
   - [Installation Steps](#installation-steps)
   - [Initial Configuration](#initial-configuration)
   - [Rolling the code back to v3](#rolling-the-code-back-to-v3)
   - [Cluster Publication and Host Retirement](#cluster-publication-and-host-retirement)
   - [Hostname and DNS](#hostname-and-dns)
3. [Core System](#core-system)
   - [Entry Point — srvctl.sh](#entry-point--srvctlsh)
   - [Initialization — init.sh](#initialization--initsh)
   - [Common Library — commonlib.sh](#common-library--commonlibsh)
   - [Utility Library — lablib.sh](#utility-library--lablibsh)
4. [Module System](#module-system)
   - [Module Structure](#module-structure)
   - [Module Discovery](#module-discovery)
   - [Module List](#module-list)
5. [Command Execution](#command-execution)
   - [exec-function and the Datastore Verbs](#exec-function-and-the-datastore-verbs)
   - [Command File Format](#command-file-format)
   - [Authorization Guards](#authorization-guards)
6. [Hook System](#hook-system)
   - [Standard Hooks](#standard-hooks)
7. [Datastore](#datastore)
   - [Data Files](#data-files)
   - [Datastore Commands](#datastore-commands)
   - [Container Data Schema](#container-data-schema)
   - [User Data Schema](#user-data-schema)
   - [IP Address Calculation](#ip-address-calculation)
   - [Datastore Synchronization](#datastore-synchronization)
   - [Datastore HTTP Server](#datastore-http-server)
   - [Key Node.js Functions (lib.js)](#key-nodejs-functions-libjs)
8. [Containers](#containers)
   - [Container Lifecycle](#container-lifecycle)
   - [Rootfs Creation](#rootfs-creation)
   - [Systemd Service Template](#systemd-service-template)
   - [Container Networking](#container-networking)
   - [Resource Limits](#resource-limits)
   - [Container Commands](#container-commands)
9. [Networking](#networking)
   - [IP Address Scheme](#ip-address-scheme)
   - [OpenVPN Mesh](#openvpn-mesh)
   - [Firewall — firewalld](#firewall--firewalld)
   - [DNS — named (BIND)](#dns--named-bind)
   - [DNS Scanning](#dns-scanning)
   - [Dynamic DNS](#dynamic-dns)
10. [Reverse Proxy — HAProxy](#reverse-proxy--haproxy)
11. [Certificates and TLS](#certificates-and-tls)
    - [Certificate Authority (CA)](#certificate-authority-ca)
    - [Domain Certificates](#domain-certificates)
    - [Let's Encrypt / ACME](#lets-encrypt--acme)
    - [Wildcard Certificates](#wildcard-certificates)
    - [HAProxy Certificate Selection](#haproxy-certificate-selection)
12. [Mail Stack](#mail-stack)
    - [Postfix (SMTP)](#postfix-smtp)
    - [SASL Authentication — saslauthd](#sasl-authentication--saslauthd)
    - [Perdition (IMAP/POP3 Proxy)](#perdition-imappop3-proxy)
    - [OpenDKIM (DKIM Signing)](#opendkim-dkim-signing)
    - [Mozilla Autoconfig](#mozilla-autoconfig)
13. [User Management](#user-management)
    - [User Model](#user-model)
    - [Host Users — usersonhost](#host-users--usersonhost)
    - [Container Users — usersonve](#container-users--usersonve)
14. [SSH Access](#ssh-access)
    - [SSH Key Management](#ssh-key-management)
    - [SSHPipeRD — SSH Proxy](#sshpiperd--ssh-proxy)
15. [Storage](#storage)
    - [GlusterFS](#glusterfs)
    - [NFS](#nfs)
    - [Static File Server](#static-file-server)
    - [FTP — vsftpd](#ftp--vsftpd)
16. [Application Modules](#application-modules)
    - [WordPress](#wordpress)
    - [Odoo ERP](#odoo-erp)
    - [MariaDB](#mariadb)
    - [Codepad](#codepad)
    - [VNC Desktop](#vnc-desktop)
    - [VNC Proxy](#vnc-proxy)
17. [Backup](#backup)
    - [Filesystem Backup](#filesystem-backup)
    - [Container Backup](#container-backup)
    - [Database Backup](#database-backup)
18. [System Administration](#system-administration)
    - [Diagnostics](#diagnostics)
    - [Version Management](#version-management)
    - [Update and Installation](#update-and-installation)
    - [Regeneration](#regeneration)
    - [Utility Commands](#utility-commands)
19. [Web GUI](#web-gui)
20. [Branding](#branding)
21. [Password Generation](#password-generation)
22. [Development Tools](#development-tools)
    - [push.sh — Commit and Push](#pushsh--commit-and-push)
23. [Configuration Reference](#configuration-reference)
    - [System Directories](#system-directories)
    - [Key Environment Variables](#key-environment-variables)
    - [Configuration Files](#configuration-files)
    - [Cluster Configuration Example](#cluster-configuration-example)
24. [Command Reference](#command-reference)
    - [Container Management](#container-management)
    - [Direct Container Interaction](#direct-container-interaction)
    - [Shorthand Commands](#shorthand-commands)
    - [User Management](#user-management)
    - [Application Installation](#application-installation)
    - [Proxy and Redirects](#proxy-and-redirects)
    - [System Administration](#system-administration)
    - [Datastore Operations](#datastore-operations)
    - [Mail Administration](#mail-administration)
    - [Backup](#backup)
25. [Inter-Module Dependencies](#inter-module-dependencies)
26. [Known Issues and Workarounds](#known-issues-and-workarounds)

---

## Architecture Overview

srvctl is a modular, plugin-based system that manages a cluster of Fedora servers running systemd-nspawn containers. Each container hosts a microsite or service.

The system consists of:

- **A main CLI dispatcher** (`srvctl.sh`) that parses commands and delegates to modules.
- **37 modules** shipped under `modules/`, providing commands, hooks, and libraries for specific subsystems (containers, networking, certificates, mail, etc.). A host may also drop its own modules into `/root/srvctl-includes/modules`; `srvctl.sh` collects those into `SC_MODULES` ahead of the shipped ones.
- **A JSON-based datastore** holding one file per entity (containers, users, hosts) under a type directory, written atomically and committed to git as an audit log (`modules/datastore/lib/store.mjs`). Cluster topology is *not* datastore content: the canonical file is `/etc/srvctl/clusters.json`, from which the per-host projections in `/var/srvctl3/host/` are generated.
- **A hook system** that lets modules extend and intercept lifecycle events, each dispatch running `pre-<name>`, `<name>`, then `post-<name>` (`commonlib.sh`).
- **A cluster architecture** where hosts communicate over an OpenVPN mesh (`10.15.x.y`), export `/srv` to each other over NFS, and copy `/etc/srvctl/data` and `clusters.json` host-to-host with `rsync` over SSH. GlusterFS was the v3 replication layer and is inert in v4 (see the note under the stack table).

The technology stack:

| Layer | Technology |
|-------|-----------|
| Host OS | Fedora Server (40 or later) |
| Containers | systemd-nspawn |
| Scripting | Bash (primary), Node.js (data processing, config generation) |
| Data | JSON files, bash-sourceable `.conf` files |
| Networking | systemd-networkd, OpenVPN, firewalld (ZeroTier optional, per container) |
| Reverse proxy | HAProxy |
| Mail | Postfix, Perdition, OpenDKIM, saslauthd |
| DNS | BIND (named) |
| Storage | NFS (cluster-wide `/srv` export); GlusterFS present but disabled |
| Certificates | OpenSSL (internal CA), Let's Encrypt via certbot (public) |

GlusterFS is deliberately switched off in v4: `modules/gluster/module-condition.sh` echoes `false` on every path — the success branch keeps its `echo true` commented out as the record of the kill-switch — so `SC_USE_GLUSTER` is never true, the module's libs are never sourced and its hooks never run. Paths under `/var/srvctl3/gluster/` still appear as defaults elsewhere (notably `SC_DATASTORE_RO_DIR`), but nothing mounts them, so the datastore falls back to the local read-write copy. The module is a deprecation candidate; read the gluster sections below as documentation of dormant code.

---

## Installation

srvctl is designed for a standard Fedora server edition. Containers may use other distributions (Debian, Ubuntu, Arch).

### Host Requirements

A srvctl host that is part of a cluster should have the following partitions:

| Mount Point | Size | Filesystem | Purpose |
|-------------|------|------------|---------|
| `/glu/srvctl-data` | 2 GiB | XFS | Certificates, passwords, sensitive data (GlusterFS brick) |
| `/glu/srvctl-storage` | 500 GiB | XFS | Static file service, FTP (separate drive recommended) |
| `/var/log` | — | XFS | Log files |
| `/home` | — | XFS | User home directories |
| `/srv` | Large, fast SSD | XFS | Container root filesystems |

The two `/glu/*` bricks exist for the `gluster` module, which is inert at this
version: `modules/gluster/module-condition.sh` echoes `false` even on the
branch where every check passed (the `#echo true` line is kept as the record of
the kill-switch). Nothing therefore replicates the bricks or mounts
`/var/srvctl3/gluster/*`; the datastore stays on its local read-write directory
`/var/srvctl3/datastore` and `/var/srvctl3/storage` is a plain local directory.

### Installation Steps

```bash
dnf -y install git
cd /usr/local/share
git clone https://github.com/LaKing/srvctl.git && bash srvctl/srvctl.sh
```

That first run is a bootstrap, not a command. `init.sh` creates `/etc/srvctl`
and `/var/local/srvctl`, symlinks `/bin/sc` and `/bin/srvctl` to
`srvctl.sh`, links `/etc/bash_completion.d/srvctl-completion` to
`modules/srvctl/completion.sh`, and evaluates every module condition into
`~/.srvctl/modules.conf`. No `clusters.json` exists yet, so the cluster
reconciliation reports generation `none` and writes no host projection. Because
no command was given, dispatch then fails on purpose: `run_command` returns 54,
srvctl prints `No-command.` followed by the command hint list and exits 1. That
non-zero exit is the expected result of the install line.

### Initial Configuration

Create the static configuration by hand — since 4.0.0.7 no example files are
shipped; the templates below are the reference. Adjust every hostname,
address, and identifier to your environment:

```bash
install -d /etc/srvctl/data

cat > /etc/srvctl/clusters.json << 'EOF'
{
    "example_cluster": {
        "s1.example.com": {
            "interface": "enp1s0",
            "host_ip": "192.0.2.10",
            "gateway": "192.0.2.1",
            "prefix": "24",
            "dns1": "192.0.2.1",
            "dns2": "8.8.8.8",
            "hostnet": 16,
            "dns_server": "master",
            "dns_primary": true
        },
        "s2.example.com": {
            "interface": "enp1s0",
            "host_ip": "192.0.2.11",
            "gateway": "192.0.2.1",
            "prefix": "24",
            "dns1": "192.0.2.1",
            "dns2": "8.8.8.8",
            "hostnet": 17,
            "dns_server": "slave"
        }
    }
}
EOF

cat > /etc/srvctl/data/branding.conf << 'EOF'
## Your company - must be one word, no spaces.
SC_COMPANY=example
## Company domain name
SC_COMPANY_DOMAIN=example.com
EOF

cat > /etc/srvctl/data/ca.conf << 'EOF'
SC_ROOTCA_HOST=s1.example.com
SC_ROOTCA_SUBJ="/C=HU/ST=Hungary/L=Budapest/O=Example-CA"
EOF
```

The host-record keys srvctl actually reads:

| Key | Consumer | Meaning |
|-----|----------|---------|
| `interface` | `networkd_configure_interface` (`modules/srvctl/libs/networkdlib.sh`) | Name of the primary NIC. Only the interface whose name matches gets a static address. |
| `host_ip`, `gateway`, `prefix` | the same, plus the `/etc/hosts` and DNS generators | Static IPv4 configuration. If any of `interface`/`host_ip`/`gateway`/`prefix` is missing, that interface is written as `DHCP=YES` instead. |
| `dns1`, `dns2` | networkd and the container `resolv.conf` generator | Upstream resolvers. |
| `hostnet` | `SC_HOSTNET`, used by every addressing scheme | Per-host `10.x` id. By convention 16–255, but nothing validates it; when the key is absent `modules/containers/hooks/post-init.sh` substitutes 250 and prints `Setting SC_HOSTNET to 250 as it is undefined so far.` |
| `dns_server` | `modules/named/module-condition.sh` | Exactly `master` or `slave` enables the named module on that host; any other value, or absence, disables it. |
| `dns_primary` | `modules/named/lib/topology.js` | `true` on at most one host, and only on a `master`. Required once a cluster has more than one master. |

Every other scalar key is merely projected into `host.conf` as `SC_<KEY>`
(uppercased and shell-quoted) and is otherwise ignored — `mac_address` and
`reverse_proxy`, which older examples carried, are read by nothing in this
version. Keys must match `^[A-Za-z_][A-Za-z0-9_]*$`; `HOSTNAME`,
`CLUSTERNAME`, `CLUSTERS_SHA256` and `HOSTS_SHA256` are generated and
`HOST_KEY` belongs to the datastore, so declaring any of them — in any letter
case — is rejected. Hostnames must be lowercase DNS names and may appear in
exactly one cluster. The local machine's own hostname must appear exactly once
in the file: every root invocation revalidates that, and a topology that does
not list this host makes srvctl exit 113 before any command runs.

Customize the following files:

- `/etc/srvctl/clusters.json` — The sole topology source, read from this exact
  path. Define every cluster host, then distribute the file byte-for-byte to
  every host.
- `/etc/srvctl/data/branding.conf` — `SC_COMPANY` and `SC_COMPANY_DOMAIN`; both
  fall back to `$HOSTNAME` (`modules/branding/hooks/pre-init.sh`).
- `/etc/srvctl/data/ca.conf` — `SC_ROOTCA_HOST` (default: this host) and
  `SC_ROOTCA_SUBJ` (default `/C=HU/ST=Hungary/L=Budapest/O=SRVCTL-CA`), see
  `modules/ca/hooks/pre-init.sh`; `SC_ROOTCA_DIR` defaults to `/etc/srvctl/CA`.

Note that `/etc/srvctl/data/*.conf` are **seeds**, not live configuration:
srvctl sources `/etc/srvctl/*.conf`, and `init.sh` copies `data/<name>.conf` up
to `/etc/srvctl/<name>.conf` only while running `update-install` or
`test-modules`. Until the first `update-install`, the branding and CA values
above are not in effect. `clusters.json` is deliberately excluded from that
copy — it has one live path and no seed.

Do not create a second `clusters.json` anywhere srvctl audits: `/etc/srvctl`,
`/var/local/srvctl` and `/var/srvctl3` (bulk branches pruned) are scanned on
every root startup, and `/etc/srvctl/data/clusters.json` is tolerated only as
the legacy pathname being migrated away.
`/var/srvctl3/host/host.conf` and `/var/srvctl3/host/hosts.json` are regenerated
projections, not editable topology sources. (They lived in `/etc/srvctl` before
4.0.0.6; the first root invocation regenerates them under `/var/srvctl3/host`
and removes the legacy copies.)

On an upgraded host, root startup handles the old path conservatively — both
files are validated before anything is moved or deleted:

- only `/etc/srvctl/data/clusters.json` exists: it is atomically renamed to the
  canonical path (both must be on the same filesystem, otherwise startup
  refuses);
- both files are byte-identical: the legacy pathname is removed;
- both files differ: startup prints `DATA-ERROR: conflicting clusters
  configuration files` and exits 113, preserving both. Review the diff, put the
  chosen/merged topology in `/etc/srvctl/clusters.json`, then remove
  `/etc/srvctl/data/clusters.json` explicitly.

Non-root invocations never migrate anything; while a legacy file or legacy
projection is present they fail closed with
`DATA-ERROR: legacy clusters configuration requires a root migration` or
`DATA-ERROR: legacy host projection requires a root migration`.

After migration, verify the runtime invariant with:

```bash
find /etc/srvctl /var/local/srvctl -name clusters.json -print
find /var/srvctl3 \( -path /var/srvctl3/rootfs -o -path /var/srvctl3/mounts \
  -o -path /var/srvctl3/storage -o -path /var/srvctl3/nfs \
  -o -path /var/srvctl3/share -o -path /var/srvctl3/gluster \) -prune -o \
  -name clusters.json -print
```

The only result should be `/etc/srvctl/clusters.json`. The prune list mirrors
`audit_cluster_config_paths` in `modules/containers/lib/cluster-config.sh`,
which skips those branches because they hold container rootfs and bulk data;
it additionally rejects `/var/srvctl3/clusters.json`,
`/var/srvctl3/datastore/clusters.json` and
`/var/srvctl3/gluster/srvctl-data/clusters.json` by exact name.

With the topology in place, run the installation on the host itself:

```bash
srvctl update-install HOSTNAME
```

HOSTNAME is required on a host: without it `update-install` performs the full
`dnf` update and then stops before every host step. On a machine still called
`localhost.localdomain` the argument is validated against the canonical
topology, written to `/etc/hostname`, and the command exits **5** to signal
"reboot required" — re-run the same command after the reboot to finish the
install. Inside a container the argument is ignored and only the
`update-install-ve` hooks run.

### Rolling the code back to v3

The migration removes the files v3 boots from (`/etc/srvctl/host.conf`,
`/etc/srvctl/hosts.json`, and the `/etc/srvctl/data/clusters.json` seed that
v3's `update-install` regenerates them from), so a code rollback needs one
backout step. While still on v4 code, as root:

```bash
srvctl exec-function prepare_cluster_rollback_to_legacy
```

then immediately replace `/usr/local/share/srvctl` with the v3 code. The
function re-renders the legacy projections and restores the seed from the
canonical topology, atomically and under the publication lock. Do not run v4
`srvctl` in between: a root invocation migrates the legacy files away again,
and non-root invocations fail closed while they exist. Upgrading again later
needs no special handling — normal startup migration reclaims the files.

The function operates on the **local host only**. For a fleet rollback, run
it — and confirm it succeeded — on **every host whose code will be rolled
back, before swapping the code anywhere**; a host missed here boots v3
without an identity. It also validates the topology for the v3 generator,
which renders `host.conf` values as *unquoted* root shell assignments: if
any host record carries a value containing whitespace, quotes, `$(...)`,
backticks, or similar, the rollback refuses with `DATA-ERROR` before writing
anything. Fix those values in the canonical topology (fleet-wide) first.

### Cluster Publication and Host Retirement

Every fleet-wide topology change goes through these root-only helpers. They are
shell functions, not commands, so they are invoked through the built-in
`exec-function` verb — which `run_command` (`commonlib.sh`) accepts only for
genuine root, i.e. `SC_USER` = root *and* uid 0. `publish_data`,
`initialize_cluster_publication`, `retire_cluster_host`, `grab_data` and
`grab_cluster_config` live in `modules/datastore/libs/datalib.sh` (so the
datastore module must be enabled on the controller);
`prepare_cluster_rollback_to_legacy` lives in
`modules/containers/lib/cluster-config.sh`, which core `init.sh` sources
unconditionally.

**Prerequisites, none of which srvctl sets up for you.** Every remote step is
`ssh -n -o ConnectTimeout=3 -o BatchMode=yes <host>` or
`rsync -avz -e 'ssh -o BatchMode=yes -o ConnectTimeout=3'`, run as root and
addressing each machine by its canonical `clusters.json` key. `BatchMode=yes`
suppresses every prompt, so an unmet prerequisite is reported as a capability
failure, never as a password request. Before the first `publish_data`:

- root on the controller needs a passwordless SSH key that root on each target
  accepts. srvctl neither generates nor distributes that key pair.
- each target's host key must already be in the controller's
  `~/.ssh/known_hosts`. `update-install` appends one `ssh-keyscan` entry per
  cluster host (step 6 under *Update and Installation*); on a host that has not
  run it, add the entries by hand.
- the canonical hostname must resolve from the controller and TCP/22 must be
  reachable. srvctl opens web and mail ports only (see *Firewall — firewalld*)
  and never adds an `ssh` rule, so SSH reachability rests entirely on the
  distribution's default zone. `ConnectTimeout=3` makes a filtered port fail
  after three seconds.
- `rsync` and `/bin/node` must exist on both ends, and every target must carry
  this srvctl version: the capability probe reads
  `modules/containers/lib/cluster-config.sh`, `lib/cluster-config-cli.js` and
  `host-conf.js` on the target and requires the answer
  `srvctl-cluster-config-v2`.
- `hostname` on the target must print the canonical key exactly — a short name
  where the topology carries an FQDN fails the probe.

SELinux needs no preparation: `update-install` disables it outright.

Before the first publication after upgrading, deploy this srvctl version to
every configured host and leave the complete deployed inventory in the
canonical file. On the host holding that file, establish the verified baseline:

```bash
srvctl exec-function initialize_cluster_publication confirm-complete-inventory
```

Run initialization before editing, removing, or renaming a host. It proves
that every listed host already serves the exact canonical SHA-256 and matching
projections, but it cannot discover a host that was removed before the first
baseline. Ordinary publication fails closed while the baseline is absent or
invalid. The manifest at
`/var/srvctl3/cluster-config/publication/publication-inventory.v1` contains only
the last successful SHA-256 and ordered hostnames; it is removal-detection
state, not another copy of the cluster topology.

For a normal topology edit, run:

```bash
srvctl exec-function publish_data
srvctl regenerate all-hosts
```

`publish_data` capability-checks every hostname from the canonical file,
synchronizes non-topology seeds while excluding all `clusters*.json` files,
prepares and validates the topology everywhere, and commits only after every
prepare succeeds. It verifies the canonical SHA-256 and generated projections
on every host. A prepare failure changes no live topology; a failure during the
distributed commit is reported explicitly as a partial commit and blocks
regeneration until repaired. `grab_data <host>` now fetches static seeds only;
use `grab_cluster_config <host>` for an explicit validated topology import.

Host removal and rename are deliberately ordered:

1. Drain/decommission the old host's workloads and dependent roles.
2. While it still answers SSH and `hostname` as `OLDHOST`, run from the same
   publication controller that initialized and owns the local manifest (never
   from `OLDHOST` itself):

   ```bash
   srvctl exec-function retire_cluster_host OLDHOST confirm-decommissioned
   ```

3. Retirement verifies the exact last-published generation and retirement
   capability, stops and disables `named.service`, removes the canonical and
   legacy topology paths plus generated projections under the remote lock, and
   records an exact-generation receipt. A retry recovers safely if remote
   retirement succeeded but the controller receipt write failed.
4. Only after that command succeeds, remove or rename `OLDHOST` in
   `/etc/srvctl/clusters.json`. For removal, run `publish_data` and then
   `regenerate all-hosts`.
5. For a rename, first make the machine answer under its new canonical
   hostname, then run `publish_data`. On the renamed machine run
   `srvctl update-install NEWHOST` before the publication controller runs
   `srvctl regenerate all-hosts`.
   Publication re-enrolls the topology and clears the remote retirement marker;
   update-install re-enables boot-persistent roles such as `named.service`,
   which retirement intentionally disabled.

The initialize, retire, and publish workflows share one exclusive workflow
lock, `/run/srvctl-cluster-publication.lock` (override:
`SC_CLUSTER_PUBLICATION_LOCK_FILE`), taken with `flock --wait 60`. The
canonical topology file and its projections are guarded by a second, separate
lock, `/run/srvctl-cluster-config.lock` (`SC_CLUSTER_CONFIG_LOCK_FILE`), which
ordinary startup also takes — shared for a read, exclusive for a write.
Publication refuses a disappeared previous hostname without a matching
receipt for the exact prior manifest SHA, and refuses to publish a retired
hostname that still appears in the current canonical topology.
`regenerate all-hosts` likewise refuses to run unless the local canonical
SHA-256 and ordered host inventory equal the last successful publication.
`verify_cluster_publication_inventory <sha256> <host>...` is the read-only
check behind that refusal and can be called on its own to find out why it
fired: 0 means the inventory matches, 1 a valid but different inventory, 100 no
manifest yet, and 113 an invalid manifest.
To retire the current publication controller itself, first run
`initialize_cluster_publication confirm-complete-inventory` on another current
host while the complete, unchanged inventory is still deployed; that host then
owns the local manifest and performs the retirement.

### Hostname and DNS

Setting a correct hostname is mandatory: the running hostname must be the exact lowercase FQDN used as the host's key in `clusters.json` — `host-conf.js` matches `os.hostname()` against those keys verbatim and fails with exit 113 on an unknown or duplicate placement. Correct forward and reverse DNS entries and NTP synchronization are essential. Users and UID/GID numbers must be consistent across clustered servers — do not create users outside of srvctl.

---

## Core System

### Entry Point — srvctl.sh

`srvctl.sh` is the main executable. It:

1. Detects whether it is running in a TTY or programmatic context (`SC_TTY`).
2. Runs `/bin/pop` first, if that file exists and the caller is root on a TTY — a development-box auto-resync hook (`srvctl.sh:37`) that is never present on a production install.
3. Sets readonly constants: `HOSTNAME`, `SC_STARTTIME`, `SC_INSTALL_BIN`, `SC_INSTALL_DIR`, `SC_COMMAND_ARGUMENTS`, `SRVCTL` (version string).
4. Collects the module list into `SC_MODULES`: `/root/srvctl-includes/modules/*` first, then `$SC_INSTALL_DIR/modules/*`. That order is the precedence order for hooks and libraries.
5. Maps shorthand commands, in both the `CMD` and the `ARG` position: `?` → status, `+` → start, `-` → stop, `!` → restart.
6. Parses command-line arguments into `CMD`, `ARG`, `OPA`, `ARGS`, `OPAS`, and keeps the untouched argv in the `SC_ARGV` array so `sudomize` can re-exec through sudo without collapsing quoted arguments.
7. Sources `init.sh` for initialization; if that fails it prints `Init could not be loaded!` and exits 1 instead of continuing.
8. Calls `run_command()` to dispatch the command. On success it ends in `exit_0`; if dispatch fails it prints `Invalid command.` (or `No-command.`), lists the available commands with `hint_commands` and exits 1.

**Key variables set:**

| Variable | Description |
|----------|-------------|
| `SC_TTY` | Boolean — running in terminal or program context |
| `HOSTNAME` | System hostname (readonly; falls back to `uname -n`) |
| `DEBUG` | Debug mode flag — `false` here, may be turned on by `/etc/srvctl/debug.conf` or any `/etc/srvctl/*.conf`, made readonly in `init.sh` |
| `SC_STARTTIME` | Millisecond timestamp for timing |
| `SC_INSTALL_BIN` | Absolute path to srvctl.sh |
| `SC_INSTALL_DIR` | Installation directory (exported) |
| `SC_MODULES` | Space-separated list of module directories, root includes first |
| `SC_COMMAND_ARGUMENTS` | Original command line (`$*`), used for logging |
| `SRVCTL` | Version string: `srvctl-` plus the contents of `$SC_INSTALL_DIR/version` — currently `srvctl-4.0.0.8` |
| `CMD` | Current command (`$1`, lowercased) |
| `ARG` | First argument of the command (`$2`) |
| `ARGS` | The whole command line including `CMD` (`$*`) |
| `OPA` | Second argument of the command (`$3`) |
| `OPAS` | Everything from the first argument on (`${@:2}`) |
| `SC_ARGV` | Original argv as an array, preserved for `sudomize` |

### Initialization — init.sh

`init.sh` performs comprehensive setup:

1. Sources debug config from `/etc/srvctl/debug.conf` (if exists).
2. Creates `/etc/srvctl` and `/var/local/srvctl` directories (as root).
3. Creates symlinks for `sc` and `srvctl` in `/bin/` (if missing).
4. Sets up the bash completion symlink `/etc/bash_completion.d/srvctl-completion` → `modules/srvctl/completion.sh`.
5. Sources `lablib.sh`, then `commonlib.sh` — every function documented below exists only from this point on.
6. For `update-install` and `test-modules` only: checks that node and git are installed (installing them with dnf if not) and copies `/etc/srvctl/data/*.conf` over `/etc/srvctl/`. Cluster topology is deliberately excluded from that copy.
7. Migrates the legacy topology path (`/etc/srvctl/data/clusters.json` → `/etc/srvctl/clusters.json`) once, fails closed if old and canonical
   topology files conflict, and refreshes host-local projections from
   `/etc/srvctl/clusters.json` before sourcing `/etc/srvctl/*.conf`. Root reconciles under the shared publisher lock; a non-root caller only verifies the hashes and aborts with exit code 113 if the projection is stale.
8. Sources every `/etc/srvctl/*.conf`, then the generated projection `/var/srvctl3/host/host.conf` **last**, so a stray static file cannot shadow the canonical host identity (a variable declared readonly by a static config aborts init with 113).
9. Sources `/etc/os-release` for OS detection.
10. Determines the actual user (handles sudo scenarios via `SUDO_USER`), then makes `CMD`, `ARG`, `ARGS`, `OPA`, `OPAS` and `DEBUG` readonly.
11. Logs command execution to `~/.srvctl/srvctl.log` and `/var/log/srvctl-root.log` (root).
12. Calls `test_srvctl_modules()` to discover and configure modules.
13. Runs the init sequence in this exact order (`init.sh:303-327`):
    `pre-init-$CMD` → `pre-init` → *help breakout* → `load_libs()` → `init` → `post-init` → `post-init-$CMD`.

The command-specific hook runs **before** the generic one on the `pre-init` side and **after** it on the `post-init` side. Both dispatch points are unconditional, but no module currently ships a `pre-init-<CMD>.sh` or `post-init-<CMD>.sh` file, so `run_hook` finds nothing to source for them.

`load_libs()` runs **after** the `pre-init` hooks, not last: module library functions are therefore *not* available inside a `pre-init` hook, only from the `init` hook onwards (and in every command). This is why `pre-init` hooks confine themselves to plain variable defaults — paths such as `SC_ROOTFS_DIR`, which `modules/containers/hooks/post-init.sh` then promotes to `readonly`. Not every module waits for `post-init`, though: `modules/datastore/hooks/pre-init.sh` declares `SC_DATASTORE_RO_DIR` and `SC_DATASTORE_RW_DIR` `readonly` on the spot, and `modules/ve/hooks/pre-init.sh` sets `readonly SC_VIRT` from `systemd-detect-virt -c`.

Two commands never reach `run_command` because `init.sh` handles them itself: `man`/`help`/`-help`/`--help` print `help_commands` immediately after the `pre-init` hooks (before `load_libs`), and `complicate` calls `generate_completion` at the very end of init; both then `exit_0`.

**Key variables set:**

| Variable | Description |
|----------|-------------|
| `SC_LOG` | Log file path `~/.srvctl/srvctl.log` |
| `NOW` | Timestamp `YYYY.mm.dd-HH:MM:SS` |
| `SC_USER` | Current user (or sudoer) |
| `SC_UID0` | Boolean — running as root |
| `SC_HOME` | Home directory of `SC_USER` |
| `SC_CANONICAL_CLUSTERS_SHA256` | SHA-256 of `/etc/srvctl/clusters.json` — this invocation's topology generation (readonly, exported) |
| `SC_CLUSTER_HOSTNAME_BOOTSTRAP` | `true` only during `update-install HOSTNAME` on `localhost.localdomain`; the future identity stays unsourced and the generation is cached as `none` until the reboot |

Any disagreement between the canonical generation and what this run actually sourced — or the generation a parent all-host regeneration pinned in `SC_EXPECTED_CLUSTERS_SHA256` — aborts initialization with exit code 113 and a "retry" message, rather than mixing two topology generations in one run.

### Common Library — commonlib.sh

Provides core functions used throughout the system.

**Command documentation markers:**

| Marker | Purpose |
|--------|---------|
| `## @@@` | Optional command syntax line (`HEMP`) |
| `## @en` | Mandatory single-line English hint (`HINT`) |
| `## &en` | Mandatory multi-line English help, repeatable (`HELP`) |
| `## &&&` | Optional help content executed at runtime (`HEXE`) |

Exactly these four markers are implemented (`commonlib.sh:17-23`, mirrored by `modules/srvctl/lib/commandindex.mjs`); `hint_on_file` consumes `@en`, `@@@` and `&&&`, `help_on_file` consumes `@en` and `&en`. A `## @hu` Hungarian hint is *not* parsed by anything — one such line survives in `modules/containers/commands/add-ve.sh` as an ordinary comment.

The `## &&&` command is executed by command substitution every time the hint is rendered — on a bare `sc`, on any mistyped command and on every completion run — and the marker is searched for in the whole file, not just the first ten lines — in the grep fallback (`commonlib.sh:302-320`) and, deliberately identically, in the index parser (`modules/srvctl/lib/commandindex.mjs`).

**Functions:**

| Function | Description |
|----------|-------------|
| `hint(cmd, hint, file)` | Prints one formatted hint line (3-space indent, `%-40s` command column, `%-48s` hint column) — the layout is parsed by `completion.sh`, do not change it |
| `title(string)` | Prints a colored section header |
| `load_libs()` | Sources every file under `libs/` of each enabled module, in `SC_MODULES` order |
| `run_hook(hook)` | Sources `hooks/<hook>.sh` of every enabled module, in `SC_MODULES` order — one hook name only. A hook that returns nonzero aborts the whole CLI through `exif` |
| `run_hooks(action)` | Calls `run_hook` for `pre-$action`, `$action`, `post-$action` |
| `run_command()` | Main command dispatcher (see [Command Execution](#command-execution)) |
| `complicate(cmd)` | No-op by default; `completionlib.sh` redefines it so a hint listing also harvests the command words for completion |
| `build_command_index(paths…)` | Parses all listed command files in a single `commandindex.mjs` call into the `SC_IDX_*` arrays; sets `SC_IDX_BUILT=true` only if node actually produced entries |
| `hint_on_file(file)` | Prints one command's hint, filtered by the caller's role (`root_only`, `operators_only`, `hs_only`, `reseller_only`); reads the index when built, otherwise greps the file |
| `hint_commands()` | Prints the commands the caller is allowed to run |
| `help_on_file(file)` | Prints detailed help for one command |
| `help_commands()` | Prints help for all commands, or for `$ARG` alone |
| `test_srvctl_modules()` | Evaluates each `module-condition.sh` and caches the `SC_USE_<MODULE>` flags in `$SC_HOME/.srvctl/modules.conf`, keyed to the canonical topology generation |
| `set_permissions()` | Normalizes modes on `/etc/srvctl` and the datastore directories |

Note the asymmetry between the two listings: `hint_commands` applies both the `SC_USE_*` module filter and the permission filters, while the full `help_commands` listing applies neither — commands of disabled modules and `root_only` commands are described to everyone (FIXME at `commonlib.sh:531-534`).

### Utility Library — lablib.sh

Provides color constants, logging, messaging, and error handling.

**Color constants:** `RED`, `GREEN`, `YELLOW`, `BLUE`, `GRAY`, `CLEAR` (ANSI escape codes).

**Output functions:**

| Function | Description |
|----------|-------------|
| `prg(message)` | Green success/progress message |
| `pry(message)` | Yellow warning message |
| `msg(message)` | Info message with hostname prefix (blue/green) |
| `ntc(message)` | Notice with hostname prefix (blue/yellow) |
| `log(message)` | Prints and appends to `$SC_LOG` with timestamp |
| `logs(message)` | Silent log entry only |
| `logfs(file...)` | Log with file content concatenation |
| `dbg(message)` | Short debug message with a counter, source file and line (when `DEBUG=true` **and** `SC_TTY=true`) |
| `debug(message)` | Debug message prefixed with the milliseconds elapsed since `SC_STARTTIME` (same `DEBUG`+`SC_TTY` gate) |
| `trace(message)` | Detailed stack trace and variable inspection |
| `err(message)` | Error message to stderr and log |

**Execution functions:**

| Function | Description |
|----------|-------------|
| `run(command...)` | Prints a shell-prompt-style line (user@host, directory, prompt) then executes the arguments; returns the command's exit code. The word-splitting of `$*` is intentional, so arguments containing spaces cannot be passed |
| `nur(command...)` | Print command without executing (dry-run) |
| `exif(message)` | Exits the whole CLI if the previous command failed, with that command's exact exit code |
| `eyif(message)` | Warn (but don't exit) if the previous command failed; returns the original code |
| `exit_0()` | Clean exit printing the `## srvctl-<version>` trailer — suppressed for `exec-function`, whose output is machine-parsed |

`run`'s own failure warning is inert: `eyif` is called from inside the `then` branch, so it inspects the exit status of the just-evaluated condition (always 0) instead of the command's, and never fires (`lablib.sh:123-131`). Callers that must react to a failure invoke `exif`/`eyif` themselves on the line after `run`.

**File manipulation:**

| Function | Description |
|----------|-------------|
| `sed_file(file, old, new)` | Replaces text in a file with `sed` — arguments 2 and 3 are a sed pattern and replacement, not literal strings |
| `add_conf(file, content)` | Appends a single line to a file unless `grep` already finds it; errors out if the file does not exist |

---

## Module System

srvctl uses a plugin-based module architecture. 37 modules ship under `$SC_INSTALL_DIR/modules/<name>/`. `srvctl.sh` (lines 69-88) assembles the search list `SC_MODULES` before `init.sh` is sourced: root-supplied custom modules in `/root/srvctl-includes/modules/*` come **first**, then the shipped modules in alphabetical order. Every later loop — condition tests, lib loading, hooks, command lookup — walks `SC_MODULES` in that order, so a custom module shadows a shipped one that offers the same command.

### Module Structure

```
modules/<name>/
├── module-condition.sh     # Activation test: sourced in a subshell, must PRINT true/false
├── command.sh              # Default handler for unmatched commands (only containers/ and srvctl/)
├── commands/               # CLI commands exposed to users
│   ├── command-name.sh
│   └── ...
├── hooks/                  # Lifecycle hooks
│   ├── pre-init.sh
│   ├── init.sh
│   ├── post-init.sh
│   ├── regenerate.sh
│   ├── update-install-host.sh
│   ├── diagnose.sh
│   ├── firewalld.sh
│   ├── version.sh          # (5 modules ship one, but no `version` hook is ever fired)
│   └── ...
├── libs/                   # Library functions (sourced when module enabled)
│   └── *.sh
├── lib/                    # JS/MJS modules imported by this module's Node scripts
├── conf/                   # Configuration files and templates
├── services/               # systemd unit files installed by update-install
├── selftest/               # bash/node self-tests, run by hand (5 modules)
├── apps/                   # Standalone applications (Node.js)
└── *.js                    # Module-specific Node.js scripts
```

### Module Discovery

At startup, `test_srvctl_modules()` (in `commonlib.sh`) walks `SC_MODULES` and sources each `module-condition.sh` inside a command substitution: the condition runs in a **subshell** and its *stdout* is the verdict — exactly the string `true` enables the module, anything else disables it. A module directory with no condition file is reported as an error and left disabled. Results are cached in:

- `~/.srvctl/modules.conf` (per-user, including root — used whenever `SC_HOME` is set)
- `/var/local/srvctl/modules.conf` (legacy fallback, sourced first and only when its
  generation matches, then overridden by the per-user cache)

Each cache opens with `export SC_MODULES_CLUSTERS_SHA256=<generation>`, the SHA-256
generation of the canonical cluster file. It is rebuilt when it is missing, when that
line does not match the current generation, or when the command is `update-install` or
`test-modules`. A rebuild is written to a temporary file beside the cache and atomically
renamed only after every module has been evaluated, so a role change or an interrupted
command cannot leave `SC_USE_NAMED` stale or truncated.

Each module gets a variable `SC_USE_<MODULE_NAME_UPPERCASE>` set to `true` or `false`.
`srvctl test-modules` forces a re-evaluation, prints every verdict as
`tested module: SC_USE_X=true|false`, and exits 0 without running anything else.

### Module List

| Module | Purpose |
|--------|---------|
| `backup` | Rsync-based filesystem backup |
| `backupdb` | Database backup (MongoDB, MariaDB) |
| `branding` | Company branding and error pages |
| `ca` | Root certificate authority |
| `certificates` | Certificate lifecycle management |
| `codepad` | Codepad collaborative editor containers |
| `containers` | Container lifecycle (add, destroy, status, backup) |
| `datastore` | JSON-based configuration storage |
| `default` | Default 404 HTTP server |
| `dns` | DNS scanning and monitoring |
| `firewalld` | Firewall management |
| `ftp` | FTP server (vsftpd) |
| `gluster` | GlusterFS distributed storage — **inert**: `module-condition.sh` always prints `false` |
| `gui` | Web administration interface |
| `haproxy` | HTTP/HTTPS reverse proxy |
| `letsencrypt` | ACME/Let's Encrypt certificate automation |
| `mariadb` | MariaDB database management |
| `mozilla` | Thunderbird email autoconfig |
| `named` | BIND DNS server with master/slave |
| `nfs` | NFS file sharing |
| `ntp` | NTP time synchronization |
| `odoo` | Odoo ERP installation |
| `opendkim` | DKIM email signing |
| `openvpn` | VPN mesh network |
| `password` | Password/passphrase generation |
| `perdition` | IMAP/POP3 reverse proxy |
| `postfix` | SMTP mail server |
| `saslauthd` | SASL authentication daemon |
| `srvctl` | Core system administration commands |
| `ssh` | SSH key management and authorization |
| `sshpiperd` | SSH proxy/tunneling daemon |
| `static` | Static file HTTP server |
| `usersonhost` | Host-level user management |
| `usersonve` | Container-level user management |
| `ve` | Virtual environment detection |
| `vncproxy` | VNC proxy server |
| `wordpress` | WordPress installation |

A module is active only where its own `module-condition.sh` says so. `containers`
disables itself inside a container and otherwise requires this `$HOSTNAME` to appear in
`/var/srvctl3/host/hosts.json`; `default`, `haproxy` and other host-side modules simply
source that condition. `ve` and `usersonve` are the mirror image — enabled only when
`systemd-detect-virt -c` reports `systemd-nspawn` or `lxc`. Role modules test the host
projection instead: `named` needs `SC_DNS_SERVER` to be `master` or `slave`.

---

## Command Execution

When a user runs `srvctl <command> [args...]`, `run_command()` (`commonlib.sh`) dispatches
through this resolution order. First match wins, and every handler is *sourced into the
current shell* — it can therefore see and change every srvctl variable:

1. **Direct function execution** — `exec-function` calls a srvctl shell function by name. Genuine root only; see below.
2. **Datastore verbs** — dispatched straight to the bash wrappers in `modules/datastore/libs/bashlib.sh`, split by verb: the writes `new`, `put`, `cfg`, `del`, `add` are genuine-root only, the reads `get` and `out` are open to every caller.
3. **Root custom commands** — `/root/srvctl-includes/$CMD.sh`
4. **Module commands** — `$SC_MODULES/*/commands/$CMD.sh`, enabled modules only, in `SC_MODULES` order (first match wins)
5. **User custom commands** — `$SC_HOME/srvctl-includes/$CMD.sh` (skipped when `SC_HOME` is `/root`)
6. **Module default handlers** — `$SC_MODULES/*/command.sh`. Unlike step 4 this does not stop at the first match: every enabled module that ships one is sourced and may claim the command. Only `containers` and `srvctl` ship one — the `VE op` machinectl shorthand and the `SERVICE OP` systemd shorthand.

`run_command` returns 54 when no command word was given and 250 when nothing matched.
Neither is the process exit status: `srvctl.sh` then prints `Invalid command. <CMD>` (or
`No-command.`), lists the hints the caller is allowed to see, and **exits 1**.

### exec-function and the Datastore Verbs

`exec-function` is not a command file — it is the first branch of `run_command`
(`commonlib.sh:132-137`), and it is the primary interface for srvctl's own cluster and
service workflows. Everything after the command word (`$OPAS`) is executed **unquoted**
in the current shell, so the first word is a srvctl function name (or any executable on
`PATH`) and the rest are its whitespace-split arguments:

```bash
sc exec-function regenerate_static_server
sc exec-function create_nspawn_container_config example.com
ssh "$SC_ROOTCA_HOST" "/bin/srvctl exec-function init_openvpn_create_ca_certificates $NET $HOSTNAME"
```

The nspawn units call it at every container start (`modules/containers/execstartpre.sh`),
the openvpn module uses it over ssh to drive the root CA host, and backups, gluster and
the static/certificate regenerators expose their entry points the same way. Caveats:

- **Genuine root only**: the branch requires `SC_USER == root` *and* `UID == 0` *and* a non-empty `$OPAS`. Somebody who reached uid 0 through the generated NOPASSWD sudoers entry keeps their own `SC_USER` and is refused.
- There is **no allowlist and no quoting** — an argument containing spaces is re-split by the shell.
- Output is machine-readable: `lablib.sh` suppresses the trailing `## $SRVCTL` banner for `exec-function`.
- When the guard does not match, dispatch simply falls through to the ordinary lookup, fails, and `srvctl.sh` prints a diagnostic line (`SC_USER: …, UID: …, OPAS: …`) before exiting 1.

The raw datastore verbs are gated on the same test but only for the writes: `new`, `put`,
`cfg`, `del` and `add` need genuine root plus arguments (`commonlib.sh:146`), while `get`
and `out` are dispatched for anybody (`commonlib.sh:153`). This applies only to verbs
*typed on the command line*; a non-root read made inside a command goes through the bash
wrapper directly and is unaffected. Full role-based gating of the verbs is still open
work (WP-E.2).

### Command File Format

Each command script uses structured comments for the help system. This is the head of
`modules/containers/commands/add-ve.sh`, trimmed:

```bash
#!/bin/bash

## @@@ add-ve NAME [TYPE]

## @en Add a VE under a domain name, by instantiating from TYPE
## &en Generic container for customization.
## &en Contains basic packages.

## &&& ls /var/srvctl3/rootfs

argument container-name
## WP-E.2.b: provisioning a container is an operator/root action (was the
## non-denying authorize stub). The created container is then owned by a user.
operators_only
sudomize

## Command implementation follows...
```

| Marker | Meaning |
|--------|---------|
| `## @@@ SYNTAX` | Optional. Syntax line shown instead of the bare file name. |
| `## @en TEXT` | Mandatory. The one-line hint — only the **first match in the first 10 lines** is read. |
| `## &en TEXT` | Mandatory. Multi-line help, repeatable, matched anywhere in the file. |
| `## &&& COMMAND` | Optional. Executed and appended to the hint in `[…]` — on *every* bare `sc`, mistyped command and completion run. |
| `## spec //cat×name×hint×invocation` | Optional. Read by the gui module out of `/var/local/srvctl/commands.spec`. |

`## @@@` and `## &&&` are searched in the whole file, not only the head — `add-ve.sh`
depends on that. The translation markers `## @hu` / `## &hu` survive in one file but are
**parsed by nothing**: both readers (`commonlib.sh` and `modules/srvctl/lib/commandindex.mjs`)
hardcode `@en` / `&en`.

Guard calls double as visibility markers, so each must stand **alone on its own line**:
`hint_on_file` greps for them line-anchored to decide whether the caller may even see the
command listed. Indentation does not break the marker — the pattern is
`^[[:space:]]*<guard>[[:space:]]*(#.*)?$` (`commonlib.sh:296-300`, mirrored in
`commandindex.mjs`), so the indented `root_only` inside an `if` in
`modules/srvctl/command.sh` still hides that entry from non-root, and a trailing `#`
comment is tolerated too. What breaks the marker is sharing the line with other code
(`if root_only; then`, `root_only && …`): such a guard still enforces, but no longer hides.

### Authorization Guards

Every guard lives in `modules/srvctl/libs/authlib.sh`, which is always loaded — host- and
VE-side alike. A guard either returns or `exit`s, so it must be called *before* any state
change. The exit codes are a convention callers rely on: **44** = authorization failure,
**32** = missing argument.

| Guard | Effect |
|-------|--------|
| `root_only` | Genuine root only: `SC_USER=root` **and** uid 0 (`sc_is_root`). Plain uid 0 is not enough — the generated NOPASSWD sudoers entry lets any user reach uid 0 while keeping their own `SC_USER`. |
| `operators_only` | Root, or a caller whose **local** datastore user record has `role=operator`. The role is resolved once by `sc_role` and is host-scoped: an operator here is an ordinary user on a host whose record does not say so. |
| `owner_only <type> <id>` | Resource ownership. Root passes; the record's `user` — or, transitionally, its `reseller` — passes and is escalated through `sudomize`; anybody else exits 44. A failed datastore lookup is propagated as that error, never turned into a denial. |
| `reseller_only` | Root, or a caller whose user name is exactly **one character** long — that single-char name *is* the reseller test. Transitional, slated for removal in WP-F. |
| `hs_only` | Meant to be "host only". **Inert as a guard**: `SC_ON_HS` is never assigned, so `if $SC_ON_HS` is an empty command with status 0 and it always passes (FIXME in `authlib.sh`). Real host/VE separation comes from the module-activation conditions. It still works as a *visibility* marker — commands carrying it are hidden when `SC_HOSTNET` is unset. |
| `ve_only` | Meant to be "inside a container only". **Inert** for the same reason, and unlike `hs_only` it is not even used for visibility. |
| `authorize` | **Non-enforcing stub.** uid 0 returns; anyone else gets `DEV (Authorization implementation not complete.)` on stderr and the command *continues*. Never rely on it: of its three call sites, `remove-ve` and `destroy-ve` are really protected by the `owner_only` that follows, and `containers/commands/status.sh` is guarded by nothing else. |
| `argument <name>` | Exit 32 unless `$ARG` (the word after the command) is non-empty. The name is used only in the message. |
| `sudomize` | When not already uid 0, re-exec `$SC_INSTALL_DIR/srvctl.sh` through sudo with the original argv and exit with sudo's real status. `SC_USER` stays the original user across the re-exec, which is what lets `owner_only` re-authorize the escalated command. |

Help output mirrors enforcement: `hint_on_file` hides `root_only` commands from non-root
and `operators_only` commands from ordinary users, while `owner_only` commands stay
listed because ownership is decided per resource, not per role.

---

## Hook System

Hooks allow modules to extend and intercept lifecycle events. The `run_hook(name)` function (`commonlib.sh`) walks the enabled modules in `SC_MODULES` order — site modules from `/root/srvctl-includes/modules` first, then the installed ones — and sources `hooks/<name>.sh` from each module that ships the file. A hook that returns non-zero aborts the whole run through `exif`, so hooks must end cleanly.

The `run_hooks(action)` convenience function runs: `pre-<action>`, `<action>`, `post-<action>`.

A hook name is only a dispatch point: firing a name that no enabled module implements is a silent no-op, which is why several names below have no handler on disk.

### Standard Hooks

| Hook | When It Runs |
|------|-------------|
| `pre-init-$CMD` | First hook of every run, *before* `pre-init` (`init.sh:304`) — no shipped module implements it |
| `pre-init` | Before initialization, before module libs are loaded (branding, ca, containers, openvpn, datastore, ve) |
| `init` | During initialization, after `load_libs` (datastore, mariadb, static) |
| `post-init` | After initialization (branding, ca, containers, srvctl) |
| `post-init-$CMD` | Last init hook, *after* `post-init` (`init.sh:327`) — no shipped module implements it |
| `regenerate` | During configuration regeneration (15 modules); also fired by `add-ve`, `add-network-ve`, `add-ve-user` and `add-codepad` |
| `regenerate_rootfs` | When rebuilding base container images (`srvctl regenerate rootfs`) |
| `regenerate_certificates` | After a certificate change (certificates, letsencrypt); fired by the haproxy `regenerate` hook (`modules/haproxy/hooks/regenerate.sh:15`) and by the haproxy `http-redirect` / `https-redirect` commands |
| `update-install-host` | During `srvctl update-install` on host |
| `update-install-ve` | During `srvctl update-install` in container |
| `pre-update-install-host` | Before host update-install (the `pre-` leg of `run_hooks update-install-host`) |
| `adjust-service` | When intercepting systemctl operations on containers |
| `diagnose` | During `srvctl diagnose` |
| `firewalld` | When configuring firewall rules |
| `version` | Intended for `srvctl version`, but **never fired** — `modules/srvctl/commands/version.sh` contains no `run_hook version`, so the `hooks/version.sh` files shipped by named, postfix, perdition, opendkim and saslauthd are dead code |
| `add-ve` | After adding a new container — extension point only, no module ships a handler |
| `add_ve_<TYPE>` | After adding a container of a specific type; only `add_ve_codepad` (codepad) exists, while `add-network-ve` fires `add_ve_fedora` with no implementer |
| `add_ve_create_nspawn_container` | Around nspawn container creation (`containers/libs/addcontainerlib.sh`) |
| `add_codepad_project` | After a codepad project directory is initialized |
| `mkrootfs_fedora` | During Fedora rootfs creation (codepad, firewalld, perdition, postfix) |
| `mkrootfs_debian` | Fired by the debian, ubuntu **and arch** rootfs builders (arch deliberately reuses this name) — no module ships a handler |

The unimplemented names are kept as extension points for site modules placed
under `/root/srvctl-includes/modules`.

---

## Datastore

The datastore module provides a JSON-based configuration store for the entire srvctl system. It stores container and user records plus dynamic per-host runtime metadata; cluster topology is not datastore content at all — `/etc/srvctl/clusters.json` is canonical. In v4 the storage engine (`modules/datastore/lib/store.mjs`) is **file per entity**: a directory is a table and each `<id>.json` file is one row. Writes are atomic (temp file, `fsync`, `rename` over the target), serialized by an exclusive `.lock` in the datastore root (10 s wait, 30 s stale-steal), validated before persisting, and best-effort committed to git. Resellers are derived from users, never stored.

### Data Files

| File | Location | Content |
|------|----------|---------|
| Containers | `$SC_DATASTORE_DIR/containers/<name>.json` | One container definition per file |
| Users | `$SC_DATASTORE_DIR/users/<username>.json` | One user definition per file |
| Host runtime metadata | `$SC_DATASTORE_DIR/hosts/<hostname>.json` | Dynamic SSH host-key fields only |
| Layout marker | `$SC_DATASTORE_RW_DIR/.per-entity` | Empty file; present once the migration completed |
| Pre-migration archive | `$SC_DATASTORE_RW_DIR/.monolithic-backup/` | Copies of the v3 `hosts.json`, `users.json`, `containers.json` |
| Seeds | `/etc/srvctl/data` (`$SC_DATASTORE_SEED_DIR`) | Fresh-install `users.json` / `containers.json` seeds |
| Hosts | `/var/srvctl3/host/hosts.json` | Generated current-cluster projection |
| Clusters | `/etc/srvctl/clusters.json` | Sole canonical cluster topology |

Certificates live beside them in `$SC_DATASTORE_DIR/cert/` and per-user key
directories in `$SC_DATASTORE_DIR/users/<name>/` — the store reads only `*.json`,
so the key directories coexist with the user records. The `.gitignore` rewritten
idempotently by `init_datastore_install` keeps `cert/`, `users/*/`,
`.monolithic-backup/`, `.per-entity` and `.git.log` out of the repository.

**Migration and the `.per-entity` marker.** v3 kept three monolithic maps —
`hosts.json`, `users.json`, `containers.json` — in the datastore root.
`migrate_datastore_to_per_entity()` (`libs/datalib.sh`) converts them once via
`lib/migrate.mjs` (write-if-absent, transactional, safe to re-run), copies the
originals into `.monolithic-backup/` and creates the empty `.per-entity` marker.
The originals are deliberately **not** deleted, so a half-rsync'd host still
running v3 code keeps reading them. While the marker is absent, readers merge the
monolithic map with the per-entity files and per-entity wins; once the marker
exists the monolithic files are ignored entirely (`lib/store.mjs`, and the same
fallback in `lib.js`) so deletes are honoured. Hand-editing
`$SC_DATASTORE_RW_DIR/containers.json` on a migrated host therefore has **no
effect** — edit `containers/<name>.json` instead.

**RO/RW directory selection.** `hooks/pre-init.sh` fills in the defaults
`SC_DATASTORE_RW_DIR=/var/srvctl3/datastore`,
`SC_DATASTORE_RO_DIR=/var/srvctl3/gluster/srvctl-data` and
`SC_DATASTORE_RO_USE=true`. `hooks/init.sh` clears the read-only flag when the
gluster module is inactive, or when the gluster mount of the RW directory
succeeds; `init_datastore()` then points `SC_DATASTORE_DIR` at the selected
directory and exports it together with `SC_DATASTORE_RO_USE`, which `main.mjs`
turns into the store's `readOnly` guard. Because the gluster module is
hard-disabled in v4 (`modules/gluster/module-condition.sh` always echoes false),
the read-only branch is in practice unreachable and `SC_DATASTORE_DIR` equals the
local RW directory on every host. Migration and host reconciliation run only when
the store is writable and the caller is root.

Host membership and static fields such as `host_ip`, `hostnet`, interfaces,
gateways, and DNS roles are always read from `/etc/srvctl/clusters.json`.
Datastore readers overlay only the explicitly supported SSH host-key fields.
Writable startup removes stale static/orphan host rows transactionally
(`lib/reconcile-hosts.mjs`); when a read-only datastore fallback is selected, the
same read-time overlay ignores its stale static values without modifying it.

### Datastore Commands

These are first-class srvctl verbs, dispatched by `run_command` (`commonlib.sh`)
ahead of any module command; each call spawns one `node modules/datastore/main.mjs`
process through the bash wrappers in `libs/bashlib.sh`:

| Command | Usage | Description |
|---------|-------|-------------|
| `get` | `srvctl get container <name> <field>` | Retrieve a value (`get container <name> exist` returns true/false) |
| `put` | `srvctl put container <name> <field> [<value>]` | Set a value; omitting the value deletes the field, `true`/`false` are stored as booleans |
| `new` | `srvctl new container <name> [<type>] [<bridge>]` | Create a new entry |
| `del` | `srvctl del container <name>` | Delete an entry |
| `out` | `srvctl out container <name> [json]` | Output in env-var or JSON format |
| `cfg` | `srvctl cfg container <name> <operation>` | Configuration operations — `update_ip`, `add_mapped_port` |
| `add` | `srvctl add container <name> user <username>` | Append to the `users` or `vncuser` collection |

Supported object types: `container`, `user`, `reseller` (`new` only), `host` and
`cluster`. The mutating verbs (`new`, `put`, `cfg`, `del`, `add`) are gated on
genuine root — `SC_USER=root` **and** uid 0 — while `get` and `out` stay open to
any caller; internal non-root reads go through the bash wrappers, not this
dispatch path. Every mutation runs as one locked read-modify-write transaction,
so concurrent `sc` invocations serialize instead of clobbering each other.
Exit codes: `0` success, `100` the requested optional value is not defined,
`110` MAIN-ERROR (bad arguments, missing record), `112` LIB-ERROR (unreadable
datastore, or a write against a read-only store), and `99` fall-through —
`main.mjs` presets that status and no branch claimed the request, which is what
an unhandled type/field combination leaves behind.

### Container Data Schema

Each container record (`$SC_DATASTORE_DIR/containers/<name>.json`) has:

| Field | Description |
|-------|-------------|
| `user` | Owning username |
| `ip` | Container IP address |
| `type` | Base rootfs type (fedora, debian, ubuntu, arch) |
| `creation_time` | When the container was created |
| `br` | Bridge name — optional override; otherwise derived as `10.<b>.<c>.x` from the IP |
| `bridge` | Custom bridge name, stored when passed as the third argument of `new container` |
| `gateway` | Gateway IP — optional override; otherwise `<a>.<b>.<c>.1` |
| `interface` | Network interface — optional override; otherwise derived from the IP octets |
| `http_port` | HTTP port (default 80) |
| `https_port` | HTTPS port (default 443) |
| `quota` | Disk quota in 1K blocks, compared against `du -s /srv/<name>` (default 250000000, i.e. roughly 250 GB) |
| `du` | Last measured size in 1K blocks, written by the hourly quota check |
| `mapped_ports` | Array of port mappings: `{proto, comment, container_port, user, timestamp, host_port}` |
| `users` | Array of usernames with access |
| `vncusers` | Array of VNC users |
| `aliases` | Domain aliases |
| `altnames` | Alternative domain names |
| `mx` | Whether container has MX records |
| `use_gsuite` | Whether using Google Suite |
| `is_mail` | Whether this is a mail container |
| `dns` | DNS scan results per domain |

`all_containers_quota_check()` (`modules/containers/libs/all_containers_quota_check.sh`),
run from the containers `regenerate` hook only for the `#cron.hourly` argument,
stores `du` and then **disables and stops** `srvctl-nspawn@<name>` for every
container whose size exceeds `quota`. Note the `FIXME(v4)` in that file: if the
`quota` lookup fails the comparison is made against 0, so a healthy container
with a broken record is stopped. Its `SIZE_LIMIT` variable is dead — nothing
reads it.

### User Data Schema

Each user record (`$SC_DATASTORE_DIR/users/<username>.json`) has:

| Field | Description |
|-------|-------------|
| `reseller_id` | Reseller group ID |
| `user_id` | Unique user ID, allocated 1–255 (it becomes the third IP octet) |
| `uid` | System UID: one above the highest `uid` already recorded and never below 1000, fatal above 65530 (the seeded `root` record keeps 0). Gaps are not reused — `userUid` in `lib/mutators.mjs` takes the maximum, not the first free value |
| `name` | Display name |
| `reseller` | Parent reseller username |
| `added_by_username` | Who created this user |
| `added_on_datestamp` | Creation date |

### IP Address Calculation

Container IPs are computed from the user model:

```
10.<hostnet>.<user_id>.<container_offset>
```

Where `hostnet` is `SC_HOSTNET`, the host's unique ID (16–255 by convention — the
range is not validated anywhere), `user_id` is the owning user's sequential ID
(1–255), and `container_offset` is one above the highest fourth octet already used on
that network, starting at 2 and fatal above 250 (a freed address is not
reused). Allocation happens inside the store lock in
`lib/mutators.mjs`: `new container` uses the *acting* user's `user_id`, while
`srvctl cfg container <name> update_ip` recomputes the address on the network of
the container's recorded `user`. The derived `container_uid` is
`65536 * (user_id * 255 + container_offset)`.

### Datastore Synchronization

- `initialize_cluster_publication(confirm-complete-inventory)` — One-time,
  verified baseline of canonical SHA-256 plus the complete host inventory.
- `publish_data()` — Synchronize non-topology datastore seeds and publish the
  canonical topology with prepare/commit/verify and removal checks.
- `retire_cluster_host(host, confirm-decommissioned)` — Stop the host's DNS
  authority and detach its exact deployed topology before removal or rename.
- `grab_data()` — rsync `/etc/srvctl/data` (`$SC_DATASTORE_SEED_DIR`) from a
  specific host, excluding `data/clusters*.json`.
- `grab_cluster_config()` — Explicitly import and apply a validated topology.
- All five live in `modules/datastore/libs/datalib.sh` and require root. Only
  the three publication workflows — `initialize_cluster_publication`,
  `publish_data` and `retire_cluster_host` — serialize on the local
  publication workflow lock (`/run/srvctl-cluster-publication.lock`);
  `grab_data` takes no lock at all, and `grab_cluster_config` only takes the
  canonical cluster-configuration lock while applying the imported topology.
- Git-based version control tracks changes (`gitlib.sh`): the `new`, `put` and
  `del` wrappers call `datastore_push` — the `cfg` and `add` wrappers do not —
  which commits the RW datastore's `hosts`, `users` and `containers`
  directories with the message
  `$SC_USER@$HOSTNAME <verb args>` and appends a line to `.git.log`. In readonly
  mode it only prints a notice.

### Datastore HTTP Server

`apps/datastore-server.js` runs as root from the `datastore-server.service` unit
(written by `libs/httpserverlib.sh` during `srvctl update-install`) and listens on
port 1030 on all interfaces; haproxy forwards two internet-reachable paths to it:

- `GET /.well-known/srvctl/datastore/containers.json` — the containers snapshot,
  built with `store.readAll("containers")` so it follows the same
  per-entity/monolithic rules as the CLI. A failure answers `500`.
- `GET /.well-known/pki-validation/*` — serves domain validation files from
  `/var/srvctl3/datastore/pki-validation/`. The request path is appended
  unsanitized, so this root-owned, internet-reachable endpoint is traversable —
  see the `FIXME(v4)` in `apps/datastore-server.js`.

Any other request is answered `200` with an `INVALID URL:` body.

### Key Node.js Functions (lib.js)

`modules/datastore/lib.js` exports 47 symbols — 43 functions plus the four loaded
maps `hosts`, `users`, `containers` and `resellers`. The v4 CLI no longer uses it:
`main.mjs` is built on `lib/store.mjs`, `lib/host-topology.js`, `lib/derive.mjs`,
`lib/generators.mjs` and `lib/mutators.mjs`. `lib.js` survives as the shared model
for the module generators that are still CommonJS — named, haproxy, letsencrypt,
opendkim, perdition, ssh, vncproxy, dns-scan, usersonhost, codepad/access.js and
containers/status.js — and reads either layout through its own `load_type()`
fallback (its header comment claiming it is "consumed only by main.js" is stale).

**Container functions:** `container_uid`, `container_br`, `container_br_host_ip`, `container_br_netdev`, `container_br_network`, `container_bridge`, `container_gw`, `container_interface`, `container_host`, `container_host_ip`, `container_hostnet`, `container_reseller`, `container_user_id`, `container_user_ip_match`, `container_http_port`, `container_https_port`, `container_quota`, `container_nspawn`, `container_ethernet`, `container_ethernet_network`, `container_hosts`, `container_resolv_conf`, `container_firewall_commands`, `container_domains`, `container_mx`, `container_useruids`, `container_add_mapped_port`, `container_update_ip`.

**Cluster functions:** `cluster_etc_hosts`, `cluster_postfix_relaydomains`, `cluster_host_keys`, `cluster_user_list`, `cluster_container_list`, `cluster_host_list`, `cluster_host_ip_list`.

**User functions:** `user_uid`, `user_container_list`, `new_user`, `new_reseller`, `new_container`.

**Persistence:** `save_type(type, map)` is the v4-aware writer used by the ssh,
dns-scan and opendkim generators — it writes per-entity files (and routes `hosts`
through the locked `reconcile-hosts.mjs merge`). `write_users()` and
`write_containers()` still rewrite the whole monolithic file and are therefore
inert on a migrated store; only `lib.js`'s own legacy mutators call them.

---

## Containers

The containers module is the largest and most central module, managing the full lifecycle of systemd-nspawn containers.

### Container Lifecycle

#### Creation (`srvctl add-ve <name> [type]`)

Operator/root only (`operators_only`, then `sudomize`). TYPE defaults to `fedora` and must name a base image already present under `$SC_ROOTFS_DIR` — `add-ve` tests for `<type>/etc/os-release` and, when it is missing, prints an error and lists the available types instead of creating anything. The work itself is `add_ve` (`libs/addcontainerlib.sh`):

1. Verify `$SC_ROOTFS_DIR/<type>` exists (exit 10).
2. Refuse if the datastore record already exists (exit 11) or `/srv/<container>/rootfs` is already there (exit 12).
3. Create a database entry via the datastore (`new container`); the type `codepad` is recorded as `fedora`.
4. Run the `add_ve_create_nspawn_container` hook.
5. Create `/srv/<container>/` with the `creation-date` and `creation-user` markers.
6. Copy the rootfs from the template directory.
7. Render `<container>.nspawn`, the `network/` drop-ins, `hosts`, `ethernet.sh` and `firewall_cmd.sh` from the datastore.
8. Generate and install a self-signed SSL certificate (also copied to `/var/srvctl3/datastore/cert/<container>.pem`).
9. Create a default `index.html`.
10. Configure Postfix for outgoing mail relay.
11. Enable `httpd.service` inside the container, then copy `resolved.conf` for DNS.
12. Enable and start `srvctl-nspawn@<container>.service` — a failed start dumps the journal and exits 17.

Only after `add_ve` returns does the command run the `add-ve`, `add_ve_<type>` and `regenerate` hooks. No module ships an `add-ve` handler today; it is a no-op extension point.

#### Status (`srvctl status [container]`)

- With a container argument: `service_action srvctl-nspawn@<container>.service status` — or the named service verbatim when `/srv/<container>/rootfs` does not exist.
- Without argument: calls the bash wrapper `containers_status` (`libs/bashlib.sh`), which runs the Node.js script `modules/containers/status.js` to render the table of all containers.

#### Backup (`srvctl backup-ve <container>`)

1. Export container metadata into `/srv/<container>/container.json` (`out container ... json`).
2. Save package lists for Fedora containers. Only `rpm.packages.list` is actually written — the `dnf list installed` call is passed through `run`, which performs no redirection, so `>` and the path reach dnf as package specs and it fails (`libs/backupcontainerlib.sh:38`).
3. Rsync `/srv/<container>` to `$SC_BACKUP_PATH/srvctl-containers/<container>/<timestamp>` (`SC_BACKUP_PATH` defaults to `/backup`). A failed rsync aborts the calling command through `exif`.
4. When `SC_BACKUP_HOST` names another machine the tree is rsynced there over SSH instead — but the remote `mkdir -p` goes through `run` as one quoted word, so it fails and the rsync then aborts (`backupcontainerlib.sh:52`): remote backups are broken as shipped.

#### Recreation (`srvctl recreate-ve <container>`)

1. Backup MongoDB data if present (`ssh <container> mongodump`).
2. Stop the container (the command aborts if the stop fails).
3. Create a full backup (`backup_ve`).
4. Move old rootfs to `tmp_rootfs`.
5. Create a fresh rootfs from template.
6. Selectively restore from `tmp_rootfs`:
   - WordPress: reinstall WordPress into the fresh rootfs, then bring back `wp-content`, `wp-config.php` and the MySQL data; otherwise plain `/var/www/html`.
   - `multi-user.target.wants`, `/root/dump`, MongoDB data dirs, `/srv`, `/home`.
7. Fix UIDs/GIDs via `restore_uids`.
8. Start the container; exit 17 if the start fails.
9. Post-install inside the now-running container: rerun the codepad boilerplate installer if present, and `dnf install mongodb-org` + `mongorestore` when a dump was restored.

`tmp_rootfs` is deliberately kept as a rollback copy and the move is skipped when it already exists — so a second `recreate-ve` on the same container keeps the current rootfs and restores the *stale* `tmp_rootfs` content over it (FIXME in `commands/recreate-ve.sh`).

#### Destruction (`srvctl destroy-ve <container>`)

Takes **no** backup — that is `remove-ve`.

1. Remove the `machines.target.wants` symlink so the unit cannot come back on boot, and stop/disable a legacy srvctl v2 unit from `/etc/srvctl/containers/` if one exists. The running unit itself is not stopped here.
2. Remove the entry from the datastore — deliberately before any file is touched, so a crash leaves a re-importable orphan directory rather than a half-deleted live container.
3. Remove `/var/srvctl3/storage/static/<container>`, then force-unmount and delete all user home bind mounts (`/home/*/<container>/*`).
4. Terminate and kill the machine via `machinectl` if it is still registered.
5. Delete `/srv/<container>` in a retry loop with 3 s pauses. The loop is unbounded: a busy or stale mount inside `/srv/<container>` retries forever (FIXME in the command).

#### Removal (`srvctl remove-ve <container>`)

Same as destroy, but `backup_ve` runs first — between the unit unhook and `del container` — and a failed rsync aborts the whole removal. The backup is an rsync tree under `$SC_BACKUP_PATH/srvctl-containers/<container>/<timestamp>`, **not** a 7z archive: the command's own help line still advertises the removed v2 behaviour ("All files will be in a 7z format archive in the users home/.srvctl directory") and is stale, as its own FIXME notes.

### Rootfs Creation

Base container images are built with distro-specific scripts and stored in `$SC_ROOTFS_DIR/` (default `/var/srvctl3/rootfs/`), rebuilt from scratch by `srvctl regenerate rootfs` (`hooks/regenerate_rootfs.sh`).

Only the **fedora** image is actually built: the hook calls `mkrootfs_fedora_base fedora "systemd-container httpd mod_ssl"`, and the `gnome`, `mail`, `debian`, `ubuntu` and `arch` builder calls below it are commented out. The debian/ubuntu/arch builders documented here therefore have no live caller and produce nothing unless an admin uncomments those lines in `modules/containers/hooks/regenerate_rootfs.sh`. With the codepad module enabled its own `regenerate_rootfs` hook adds a `codepad` image (a customized fedora). Run `ls /var/srvctl3/rootfs` to see what a given host actually offers.

#### Fedora (`mkrootfs_fedora_base`)

Uses `dnf --use-host-config --installroot ... --nogpgcheck install` with the **host's** `VERSION_ID` as `--releasever`. The target directory is deleted and rebuilt on every call.

**Base packages:** dnf, initscripts, passwd, rsyslog, vim-minimal, openssh-server, openssh-clients, dhclient, chkconfig, rootfiles, policycoreutils, fedora-repos, fedora-release, bash-completion.

**Standard packages:** hostname, git, nodejs, gcc-c++, mc, openssl, postfix, mailx, sendmail, dovecot, unzip, rsync, wget, firewalld, cyrus-sasl, cyrus-sasl-lib, cyrus-sasl-plain, cyrus-sasl-md5.

**Caller-supplied packages:** the function's second argument — `systemd-container httpd mod_ssl` for the shipped `fedora` image.

**System users created:**

| Username | UID | Shell | Purpose |
|----------|-----|-------|---------|
| srv | 801 | nologin | Service account |
| git | 802 | nologin | Git operations |
| node | 803 | nologin | Node.js services |
| codepad | 804 | /bin/bash | Codepad interactive user |

**Post-setup:** root SSH keys and the srvctl `sshd_config` installed, `sc`/`srvctl` symlinked into `/bin`, postfix (with `modules/postfix/conf/ve-main.cf`), dovecot, systemd-networkd and systemd-resolved enabled, then the `mkrootfs_fedora` hook runs — codepad, firewalld, perdition and postfix implement it, each acting only on the template it targets (firewalld on `fedora`, codepad on `codepad`, perdition and postfix on the `mail` image, whose builder call is commented out).

#### Debian (`mkrootfs_debian_base`)

Uses `debootstrap stable` with `--include=ssh,systemd,dbus,libpam-systemd,mc,nodejs`. Enables systemd-networkd and systemd-resolved, then fires the `mkrootfs_debian` hook (no module supplies a handler). No live caller.

#### Ubuntu (`mkrootfs_ubuntu_base`)

Uses `debootstrap focal` from `http://archive.ubuntu.com/ubuntu` with `--include=ssh,systemd,dbus,libpam-systemd` — unlike Debian it does **not** pull in `mc` or `nodejs`. Fires the `mkrootfs_debian` hook rather than one of its own. No live caller.

#### Arch (`mkrootfs_arch_base`)

Runs `pacman-key --init`/`--populate`, then `pacstrap -G -M -c -d`. Packages: base, base-devel, inetutils. Enables systemd-networkd and systemd-resolved, and also fires the `mkrootfs_debian` hook (copy-paste; there is no `mkrootfs_arch` hook). No live caller.

#### Shared Functions

| Function | Description |
|----------|-------------|
| `mkrootfs_root_ssh(rootfs)` | Copies root's SSH keys into the image and installs `modules/ssh/sshd_config`; called by every builder |
| `mkrootfs_adduser(name, username)` | Would create a UID/GID 1000 login user with root's bash files and SSH access — **dead code**, no caller anywhere (`libs/mkrootfslib.sh`) |

### Systemd Service Template

`create_srvctl_nspawn_service` (`libs/systemlib.sh`) generates `/etc/systemd/system/srvctl-nspawn@.service` — a systemd template unit for container management. It runs only from the `update-install-host` hook, and its idempotence check tests `/usr/lib/systemd/system/srvctl-nspawn@.service`, a path it never writes to, so every `srvctl update-install` rewrites the unit and overwrites local edits.

```ini
[Service]
ExecStartPre=/bin/bash $SC_INSTALL_DIR/modules/containers/execstartpre.sh %i
ExecStart=/usr/bin/systemd-nspawn --quiet --keep-unit --boot \
    --link-journal=try-guest --settings=trusted \
    --machine=%i -D /srv/%i/rootfs
ExecStartPost=/bin/bash $SC_INSTALL_DIR/modules/containers/execstartpost.sh %i
ExecStopPost=/bin/bash $SC_INSTALL_DIR/modules/containers/execstoppost.sh %i

KillMode=mixed
Type=notify
RestartForceExitStatus=133
SuccessExitStatus=133
WatchdogSec=3min
Slice=machine.slice
Delegate=yes
TasksMax=16384
```

`$SC_INSTALL_DIR` is expanded when the unit is written, not by systemd. The unit is also `PartOf=machines.target` and `WantedBy=machines.target`; its device and resource directives are listed under Resource Limits below. nspawn units cannot be restarted (systemd#2809), so srvctl always stops and starts them.

**Pre-start (`execstartpre.sh`):** creates `/var/srvctl3/share/containers/<container>`, then either copies a manual `/srv/<container>/local.nspawn` verbatim over `<container>.nspawn` — bypassing the datastore render, the boilerplate/codepad binds and all `*.binds` processing — or regenerates the config via `srvctl exec-function create_nspawn_container_config` (exit 11 aborts the start). Exits 15, also aborting the start, when `hosts` or the nspawn file is still missing afterwards.

**Post-start (`execstartpost.sh`):** exits 14 if `/srv/<container>` is gone, runs `/srv/<container>/ethernet.sh` when present, sleeps 3 s to let networkd acquire an address, then logs the machine's IP to the journal. It always ends in `exit 0` — a non-zero status here would fail the whole unit start. The datastore `put container ip` write that used to live here is intentionally disabled.

**Post-stop (`execstoppost.sh`):** an intentional no-op placeholder (a `started false` datastore write and a `machinectl terminate` used to live here); kept because the installed unit references the path.

### Container Networking

By default srvctl manages the container network itself. The generated nspawn file carries `VirtualEthernetExtra=<oct2>-<oct3>-<oct4>` (the interface name is derived from the container IP; the separator is `_` for 192.x and `+` for 172.x), and the container configures that interface **statically** from `srvctl-ethernet.network` — address `<container ip>/24`, gateway `<net>.1`, DNS 8.8.8.8. The host end is attached by `ethernet.sh` to the per-container bridge `10.<oct2>.<oct3>.x`, which `create_networkd_bridge` materializes as `br-<name>.netdev`/`.network` in `/run/systemd/network` (volatile — recreated by regenerate and on unit start) and which `ethernet.sh` adds to firewalld's trusted zone.

`host0` with DHCP is the *exception*, not the default: `80-container-host0.network` is written only for containers that carry an explicit `bridge` key, i.e. those created with `add-network-ve`. A `zt-bridge-endpoint.network` drop-in (DHCP on `zt-*`) is written for every container, for ZeroTier interfaces. Deprecated containers get neither the veth line nor a bridge.

**Generated configuration files per container:**

| File | Purpose |
|------|---------|
| `/srv/C/C.nspawn` | systemd-nspawn settings, re-rendered from the datastore on every unit start |
| `/srv/C/local.nspawn` | Optional manual override, copied verbatim over `C.nspawn` and suppressing all generation |
| `/srv/C/network/srvctl-ethernet.network` | Static address for the srvctl-managed veth (default path) |
| `/srv/C/network/80-container-host0.network` | DHCP on `host0`, bridge-attached containers only |
| `/srv/C/network/zt-bridge-endpoint.network` | DHCP on `zt-*` (ZeroTier), always written |
| `/srv/C/hosts` | Container's `/etc/hosts` |
| `/srv/C/ethernet.sh` | Brings the veth up, adds it to the bridge, trusts the bridge in firewalld |
| `/srv/C/firewall_cmd.sh` | Host firewall rules for mapped ports; sourced immediately when regenerated |
| `/var/srvctl3/share/containers/C/config` | The container's own configuration, bind-mounted read-only inside it |

**Bind mounts:** the generated nspawn file always binds `$SC_INSTALL_DIR`, `/var/srvctl3/share/containers/C`, `/var/srvctl3/share/common`, `/srv/C/network` (as `/etc/systemd/network`) and `/srv/C/hosts` (as `/etc/hosts`) read-only. If the host has `/usr/local/share/boilerplate` or `/usr/local/share/codepad`, a `BindReadOnly` line is appended sourcing them from the hardcoded `/srv/v3-devel/rootfs/srv/boilerplate` and `/srv/c3-devel/rootfs/srv/codepad` (flagged as a TODO in `libs/systemlib.sh`). Then the contents of `/srv/C/*.binds` are appended, followed by `/srv/C/binds/*.binds` — that order is a contract. None of this happens when `local.nspawn` is present.

### Resource Limits

**Per-container (`srvctl-nspawn@.service`):**

| Resource | Limit |
|----------|-------|
| CPU quota | 800% |
| Memory max | 16 GB |
| Memory high | 8 GB |
| Tasks max | 16384 |
| Delegate | yes |
| Device policy | Closed (whitelist) |
| Allowed devices | `/dev/net/tun` rwm, `char-pts` rw, `/dev/loop-control` rw, `block-loop` rw, `block-blkext` rw, `/dev/mapper/control` rw, `block-device-mapper` rw |

**Per-user slice — never applied.** `create_userslice_config` (`libs/systemlib.sh`) would write `/etc/systemd/system/user-.slice.d/50-srvctl.conf` with `CPUQuota=400%`, `MemoryMax=16G` and `MemoryHigh=8G`, but the function is dead code with no callers, so the drop-in is never created. Its 400% also contradicts the unit's 800%.

**System-wide (`srvctl-sysctl.conf`)** — installed to `/etc/sysctl.d/` by the `update-install-host` hook:

| Parameter | Value |
|-----------|-------|
| `fs.file-max` | 4194304 |
| `fs.inotify.max_queued_events` | 2097152 |
| `fs.inotify.max_user_instances` | 2097152 |
| `fs.inotify.max_user_watches` | 4194304 |
| `vm.swappiness` | 1 |

A `kernel.pid_max=4194304` line is present but commented out. Note that every `regenerate` run raises `fs.inotify.max_user_watches` to 16777216 at runtime (a stated workaround for systemd#17992), so the 4194304 above only holds until the first regenerate after boot.

**System-wide (`srvctl-limits.conf`)** — installed to `/etc/security/limits.d/`:

| Resource | Limit |
|----------|-------|
| Open files (`nofile`, soft and hard, for `*` and `root`) | 1048576 |
| Locked memory (`memlock`, soft and hard, for `*`) | Unlimited |

**Disk quota enforcement:** `all_containers_quota_check()` runs hourly — `hooks/regenerate.sh` calls it only when `ARG` is the literal `#cron.hourly`, which is exactly what `/etc/cron.hourly/srvctl-regenerate.sh` passes. It stores each container's `du -s /srv/<container>` (1K blocks) in the datastore and, when that exceeds the container's `quota` key, disables and stops `srvctl-nspawn@<container>`. The datastore default is `250000000` — 250,000,000 blocks, i.e. roughly 250 GB, not 250 MB. If the quota lookup returns nothing the arithmetic compares against 0 and a healthy container is stopped (FIXME in `libs/all_containers_quota_check.sh`).

### Container Commands

| Command | Description |
|---------|-------------|
| `add-ve <name> [type]` | Create a new container; type defaults to `fedora` and must already exist under `$SC_ROOTFS_DIR` |
| `add-network-ve <name> <bridge>` | Create a fedora container on an existing `br-<bridge>` with DHCP |
| `add-ve-user <name> <user>` | Add a user to a container, creating the datastore user if new (reseller only) |
| `backup-ve <name>` | Backup a container |
| `destroy-ve <name>` | Permanently delete a container, no backup |
| `remove-ve <name>` | Rsync-backup, then delete a container |
| `recreate-ve <name>` | Rebuild rootfs preserving data |
| `status [name]` | Show container status |
| `regenerate [all-hosts\|rootfs]` | Rewrite generated configuration; `rootfs` rebuilds the base images, `all-hosts` repeats over ssh on every cluster host (root only) |
| `exec-all <command>` | Execute command on all running containers (root only) |
| `map-port <name> [udp] <port> <description>` | Map a TCP/UDP port to the host; stops and starts the container to apply it |
| `update-ve <name>` | Unimplemented stub — it stops the container, prints "Feature unimplemented" and leaves it **stopped** |

`regenerate` recognises only `rootfs` and `all-hosts`; any other argument (including `all`) silently falls through to the plain single-host regenerate.

The containers module also intercepts direct container names as commands. Either word order works — `srvctl <container> <op>` or `srvctl <op> <container>` — and each operation is owner-scoped:

```bash
srvctl <container-name> shell      # Interactive machinectl shell
srvctl <container-name> login      # Login
srvctl <container-name> status     # Status
srvctl <container-name> show       # Show machine properties
srvctl <container-name> reboot     # Reboot
srvctl <container-name> poweroff   # Power off
srvctl <container-name> kill       # Kill
```

---

## Networking

### IP Address Scheme

srvctl uses a single Class A network `10.x.x.x` for all container and host communication.

| Range | Purpose |
|-------|---------|
| `10.0.0.0` – `10.14.255.255` | External networks and OpenVPN connections outside srvctl |
| `10.15.x.y` | OpenVPN host-to-host mesh (x = server hostnet, y = client hostnet) |
| `10.<hostnet>.<user_id>.<offset>` | Container IPs |

The container address is built by `findIpForContainer()`
(`modules/datastore/lib/mutators.mjs`): `10.<SC_HOSTNET>.<user_id of the acting
user>.<offset>`, where the offset is one above the highest fourth octet already
in use on that `10.a.b.x` network (2 when the network is empty; gaps left by
removed containers are not reused); allocation fails once it would exceed 250.

Each host has a unique **HOSTNET** identifier, by convention between 16 and 255,
and by convention each host is prefixed with a two-digit identifier in the
company domain hostname. **Nothing validates that range.** `clusters.json`
validation (`modules/containers/lib/cluster-config.js`) never inspects the
`hostnet` value and does not even require the key; a missing value is silently
defaulted to 250 by `modules/containers/hooks/post-init.sh` before `SC_HOSTNET`
is made readonly. An out-of-range or duplicated hostnet is accepted and simply
produces broken `10.x` / `10.15.x.y` addressing.

### OpenVPN Mesh

The `openvpn` module creates a full mesh VPN between all cluster hosts. It is
enabled whenever `/etc/openvpn` exists, otherwise it falls through to the
`containers` module condition. The module is a **deprecation candidate for v4**
(campaign issue G8: a ZeroTier mesh is intended to replace the 10.15.x.y
hostnet), but it is live on production hosts until that migration completes —
the generated content in `modules/openvpn/libs/openvpnconfiglib.sh` is treated
as byte-frozen. Everything is written by `hooks/update-install-host.sh`; the
module ships no command and no regenerate hook.

**Server configuration** (`/etc/openvpn/hostnet-server.conf`):
- UDP port 1101, device `tun-hostnet`, `topology subnet`, `mode server`
- TLS server mode with CA-signed certificates, `dh /etc/openvpn/dh2048.pem`
- `cipher AES-256-CBC` and `comp-lzo` — peers of mixed versions must still
  handshake with these
- `client-config-dir hostnet-ccd` for per-client routing
- Address assignment: `ifconfig 10.15.<SC_HOSTNET>.1 255.255.255.0`, with
  `iroute 10.15.<SC_HOSTNET>.0/24` in the ccd `DEFAULT` file

**Client configuration** (`/etc/openvpn/hostnet-client-<peer>.conf`, one per
other cluster host):
- Per-peer TUN device: `tun-host<peer hostnet>`
- Connects to the peer's `host_ip` on UDP 1101
- `ifconfig 10.15.<peer hostnet>.<SC_HOSTNET>` — the fourth octet is the *local*
  hostnet
- `route 10.<peer hostnet>.0.0 255.255.0.0 10.15.<peer hostnet>.1`, so the
  peer's container network is reachable over the tunnel
- Written only when the peer has both `host_ip` and `hostnet` in the datastore

**Certificate management** (`libs/openvpnlib.sh`, on top of the `ca` module):
- Two nets are minted, `hostnet` and `usernet`. Only `hostnet` is ever
  configured: no usernet server config was ever written and the matching
  `firewalld_add_service openvpn-usernet tcp 1100` line is commented out.
- On the CA host: `init_openvpn_rootca_certificates <net>` initializes the
  network CA and mints a server+client pair for every host in `host_list`. It
  is self-guarded and returns immediately when `SC_ROOTCA_HOST != $HOSTNAME`.
- On other hosts: `grab_openvpn_rootca_certificates <net>` triggers remote
  minting over ssh (`srvctl exec-function init_openvpn_create_ca_certificates
  <net> <host>` — a cross-version wire contract, do not rename) and rsyncs its
  own material. Each file is fetched **only if it is missing locally**, so
  renewed or expired certificates are never re-synced; after expiry the mesh
  stays down until the local pem files are deleted by hand.
- Uses 2048-bit DH parameters, generated once per host.

**Firewall:** Opens UDP 1101 as `openvpn-hostnet`.

**Known defects (unfixed, all marked `FIXME(v4)` in `modules/openvpn/`):** on
Fedora 28+ split units the ccd `iroute` is written to the Fedora 27 path and
never applies; the client restart targets a misspelled unit
(`openvpn-cleint@…`), so changed client configs only come up after a reboot or
a manual restart; and the `ln -s` calls are not idempotent, printing
`File exists` on every re-run.

### Firewall — firewalld

The `firewalld` module manages host and container firewall rules. It is enabled
inside any systemd-nspawn or lxc container, on a farm host listed in
`/var/srvctl3/host/hosts.json`, and on the `update-install <host>` bootstrap
path — never on a pristine `localhost.localdomain` machine.

`hooks/update-install-host.sh` (host) and `hooks/update-install-ve.sh`
(container) install, enable and start firewalld, then fire the module's own
**`firewalld` hook point** (`run_hooks firewalld`), where `codepad`, `ftp`,
`perdition` and `postfix` contribute their ports as well.

**Global services configured** (`modules/firewalld/hooks/firewalld.sh`) — these
are opened on every managed host *and* container regardless of whether the
service runs there, which the file itself flags as a `FIXME(v4)`:
- Mail: imap, imaps, pop3s, smtp, smtps — added by name only, using firewalld's
  built-in definitions (143/993/995/25/465); the explicit port numbers appear
  only on the offline rootfs path in `hooks/mkrootfs_fedora.sh`
- Web: http (80), https (443), http8080 (8080), https8443 (8443)
- Search: https9200 (9200)
- Masquerading on the default zone, permanent and runtime (NAT for the 10.x
  container network) — added by `update-install-host.sh` after the hook point

**Functions** (`libs/firewalldlib.sh` — a cross-module ABI called from ~10 other
modules and from shell generated by `modules/datastore/lib.js`):

| Function | Description |
|----------|-------------|
| `firewalld_add_service <name> [proto] [port] [hint]` | Idempotently add a service to the live system's default zone. A built-in service name with no proto/port is added directly; otherwise an XML definition is written first. `hint` is optional, defaults to `$SC_USER`, and only lands in the XML `<description>`. |
| `firewalld_offline_add_service <name> [proto] [port]` | The same against a not-yet-booted rootfs through `chroot … firewall-offline-cmd`. No `hint` argument, and it must be called from a hook with `rootfs_base` in scope. |

Each generated service is an XML file in `/etc/firewalld/services/` (or
`<rootfs>/etc/firewalld/services/` offline). Two documented sharp edges:
`firewalld_add_service` starts `firewalld.service` as a side effect on every
call, and an unknown service name with empty proto/port writes an invalid
`<port protocol="" port=""/>` file that breaks every later `firewall-cmd
--reload` until it is removed by hand.

### DNS — named (BIND)

The `named` module runs authoritative BIND DNS with one serial authority and
zone-transfer replicas.

**Module activation:** Requires `SC_DNS_SERVER` set to exactly `master` or
`slave`. The value is projected from the host's `dns_server` key in
`/etc/srvctl/clusters.json` into `/var/srvctl3/host/host.conf`. Hosts keeping a
legacy `slave` label need no change: the label only selects the module, the
publication primary is chosen by the election below.

**DNS topology (`/etc/srvctl/clusters.json`, the sole topology source):**

- Exactly one host publishes zone content. Set `"dns_server": "master"` and
  `"dns_primary": true` on that host.
- If exactly one legacy `master` exists, it is elected when `dns_primary` is
  omitted. With more than one legacy master, exactly one `dns_primary: true`
  marker is required; srvctl fails closed instead of relying on JSON order.
- Every other DNS host is a transfer replica. An extra legacy host still
  labelled `master` is treated as a replica; it no longer generates competing
  SOA serials.
- DNS hosts require a stable `host_ip`. The primary uses replica addresses for
  NOTIFY and the transfer ACL; replicas transfer from the elected primary only.
- On NAT or multihomed DNS hosts, set `dns_replication_source` to the local
  address BIND must bind for outbound replication traffic, and set
  `dns_replication_acl_ip` to the address the remote DNS host actually sees.
  The primary emits `notify-source`; replicas emit `transfer-source`, and both
  sides authorize the configured observed address. Without these optional
  fields, `host_ip` remains the replication identity.
- The SOA MNAME defaults to `ns1.<SC_COMPANY_DOMAIN>` and is independent of a
  domain's apex A override. Set `dns_authoritative_name` on the primary only if
  its public authoritative name differs.

**Configuration generation (`named.js`):**

- Generates zone files for all containers and their domains from the datastore.
- Reads the layout-aware local datastore and fresh peer snapshots, with the
  last valid peer snapshot as a bounded-outage fallback only for the hourly
  safety run (maximum age: six hours). Manual/all-host publication requires
  every peer to be fresh and returns nonzero without publishing if one is not.
- Increments a zone's SOA serial only when its rendered content changes. The
  serial is monotonic even when two regenerations occur in one second or the
  host clock moves backwards.
- Creates primary zones with explicit NOTIFY and restricted transfers; creates
  replica zones that name only the canonical primary.
- Stores zone content in `/var/named/srvctl/<domain>.zone` (primary only;
  aliases share the primary domain's file) and the zone declarations in
  `/var/named/srvctl.conf`; replica declarations name
  `/var/named/srvctl/<domain>.slave.zone`.
- Exit-code contract consumed by `namedcfg` (`libs/bashlib.sh`): 0 success, 111
  `DATA-ERROR:` on stderr, 99 abnormal end. Tunable through the environment:
  `SC_NAMED_FETCH_TIMEOUT_MS` (peer fetch, default 3000),
  `SC_NAMED_CACHE_MAX_AGE_MS` (default 21600000, i.e. six hours) and
  `SC_NAMED_REQUIRE_FRESH`, which `namedcfg` sets to `false` only for the
  `#cron.hourly` run.

**Activation and propagation:**

- Generation is locked so cron and manual runs cannot allocate the same serial
  concurrently.
- BIND configuration and primary zone loading are checked before restart.
- After restart, primary zones receive `rndc notify`; replica zones receive a
  forced `rndc retransfer` for operator/all-host runs. srvctl polls the primary
  and local authoritative SOAs as one pending set until their serials match.
  The global deadline scales with BIND's per-primary transfer queue, and zones
  may complete out of order; command success means every replica is serving the
  published generation. Concretely: 10 s of startup allowance plus 5 s per batch
  of two queued zones per primary (BIND's default `transfers-per-ns`), capped at
  300 s. Every term is overridable for an unusually large or slow installation —
  `NAMED_REPLICA_BASE_SECONDS`, `NAMED_REPLICA_BATCH_SECONDS`,
  `NAMED_REPLICA_TRANSFERS_PER_NS`, `NAMED_REPLICA_MAX_SECONDS`, or a flat
  `NAMED_REPLICA_TIMEOUT_SECONDS` that replaces the calculation. The hourly
  safety run uses a lightweight `rndc refresh` instead (`namedcfg` exports
  `NAMED_FORCE_RETRANSFER=false` for `#cron.hourly`); the generated SOA
  refresh/retry timers are 15 minutes / 5 minutes as a recovery path if a NOTIFY
  packet is missed.
- `srvctl regenerate all-hosts` enumerates every host in every canonical
  cluster, runs ordinary hosts first, then the publication primary, then
  replicas. It attempts every host, reports all execution failures, and returns
  nonzero if any failed. Before changing the first host, it verifies the full
  canonical file SHA-256 and DNS election on every host. Identical DNS roles
  with different ordinary-host data still fail closed.

**BIND configuration (`/etc/named.conf`, rewritten by `install_named` on every
`update-install`):**
- ACL "trusted" for `10.0.0.0/8` and localhost.
- Listens on port 53 on any address with `allow-query { any; }`; recursion and
  the query cache are restricted to the trusted ACL, to prevent amplification.
- DNSSEC validation enabled.
- Includes `/etc/named.rfc1912.zones` and `/etc/named.root.key`. Caveat:
  `install_named` seeds the RFC1912 file by rsyncing `/usr/share/doc/bind/sample`,
  which current bind packages no longer ship — the copy fails unchecked and the
  included file may be absent (`FIXME(v4)` in `modules/named/libs/install.sh`).
  The same function still installs and starts `ntpd`, retired on current Fedora,
  which fails noisily and configures no time sync.

**Commands:**

| Command | Description |
|---------|-------------|
| `override-in-address <container> <ip>` | Redirect wildcard/apex A records and converge the current cluster plus all DNS authorities |
| `override-in-address <container> none` | Remove the A-record override and converge the current cluster plus all DNS authorities |
| `regenerate all-hosts` | Publish manual datastore edits in dependency order and refresh DNS replicas. This is a `containers` module command (`modules/containers/commands/regenerate.sh`), listed here because DNS publication is what makes the ordering matter; the same command also accepts `rootfs` |

For an external web server, use `override-in-address example.com 203.0.113.10`.
This changes the authoritative wildcard and apex A records; it is a DNS record
change, not an HTTP redirect. Verify both authorities with
`dig +short example.com @<primary-ip>` and
`dig +short example.com @<replica-ip>`.

### DNS Scanning

The `dns` module monitors DNS records for all container domains. Its condition
delegates to the `containers` module, so it is active on every container host —
not only on DNS servers.

**Scanner (`dns-scan.js`, invoked by `dns_scan` from the module's `regenerate`
hook):**
- Runs synchronously inside every `sc regenerate`, and therefore also inside
  `add-ve`, `add-ve-user`, `add-network-ve` and `add-codepad`. With many domains
  the resolver timeouts make container creation noticeably slower; moving it to
  a timer is an open `FIXME(v4)`.
- Queries Google DNS (8.8.8.8) for A and — inside the A success callback — AAAA,
  MX and NS records, for every domain `datastore.container_domains()` returns:
  the container name, its aliases and its altnames, each with a `www.` variant,
  plus any configured subdomains (no `www.` variant for those).
- Stores each result as `containers[<name>].dns[<domain>]` together with
  `timestamp: { time, state }`, where state is `OK`, `UNKNOWN` or the node
  resolver error code, and rewrites `$SC_DATASTORE_DIR/containers.json` on exit.
- "Problematic" means the last state was `ENOTFOUND`, `ETIMEOUT` or `ESERVFAIL`;
  those domains are re-scanned at most hourly, every other domain on every run.
- The `letsencrypt` module reads this data to decide whether a domain already
  points at this host before requesting a certificate.

### Dynamic DNS

The `named` module ships a DYNDNS server, but **the whole subsystem is dormant
and must not be revived as-is.** `install_dyndns`
(`modules/named/libs/install.sh`) prints `dyndns implementation not ready` and
returns before doing any work, and nothing anywhere in the tree calls it. Even
if it were called, the systemd unit it writes points `ExecStart` at
`modules/named/hs-apps/dyndns-server.js`, a path that does not exist, so the
service could not start. There is no srvctl command to enroll or manage a
dyndns hostname.

**DYNDNS server (`modules/named/apps/dyndns-server.js`) — what it would do:**
- HTTPS POST server on port 855, certificate and key paths taken from `argv`.
- The request path names the dyndns host; the POSTed `auth` value is compared
  against `/var/dyndns/<host>.auth`.
- Stores the client IP in `/var/dyndns/<host>.ip`.
- Runs `apps/dyndns-update.sh`, which executes `nsupdate -k
  /var/dyndns/srvctl-include-key.conf` against the local BIND; that include is a
  copy of `/var/named/srvctl-include-key.conf`, written from key material
  generated under `/var/named/keys/`.

The file header lists why it is frozen: shell command injection and path
traversal from the unvalidated host name, a plaintext non-constant-time auth
comparison, a hard-coded `setuid(103)`, and HMAC-MD5 TSIG material generated
with `dnssec-keygen -a HMAC-MD5`, which modern BIND no longer supports. A v4
rebuild needs strict input validation, `execFile` with argument arrays,
`tsig-keygen` keys and a dedicated service user.

---

## Reverse Proxy — HAProxy

The `haproxy` module provides HTTP/HTTPS reverse proxying from the host to
containers. Its condition delegates to the `containers` module, so it is active
on every container host.

**Configuration generation (`haproxy.js`, run through the `haproxycfg` wrapper
in `libs/bashlib.sh`, which writes `/etc/haproxy/haproxy.cfg`):**
- Reads containers, hosts and users from the datastore, plus `SRVCTL`,
  `SC_UID0`, `SC_COMPANY_DOMAIN` and `SC_USE_CODEPAD`.
- Frontends: `http` (`bind *:80`), `https`
  (`bind *:443 ssl crt /var/haproxy alpn h2,http/1.1`), and `port<N>` frontends
  for 9200, 8080 and 8443 — plus the codepad ports 9000, 9001 and 9002.
  On the codepad ports only some containers are routable (`codepad_port_allowed`
  in `haproxy.js`): every **codepad container** — one whose local rootfs has
  `/var/codepad/codepad4`, a `/srv/<C>/rootfs` check, so only containers on the
  generating host match — is routed on all three. 9001 and 9002 are reserved to
  those; 9000 additionally keeps the legacy opt-in for non-codepad containers
  named `*-devel*` or carrying the port in their `proxy_ports` datastore key.
  `use_codepad` is currently pinned `true` in `haproxy.js`, so the three
  frontends render on every host; the `SC_USE_CODEPAD` gate is commented out.
- Backends: `http:<ve>`, `https:<ve>` and `port<N>:<ve>` per container; the
  `/.well-known/` helpers `letsencrypt-backend` → `127.0.0.1:1028`,
  `thunderbird-backend` → `127.0.0.1:1029` (mozilla autoconfig) and
  `srvctl3data-backend` → `127.0.0.1:1030` (the datastore HTTP server, also
  serving `/.well-known/pki-validation/`); and `backend default` →
  `localhost:1282`. All four helper daemons nevertheless bind every interface
  (`listen(1028)`, `listen(1029)`, `listen(1030)`, `listen(1282)` — flagged as
  a FIXME in `modules/mozilla/apps/mozilla-autoconfig-server.js` and
  `modules/default/server.js`); nothing in srvctl opens those ports in
  firewalld, so on a default install HAProxy is the only reachable path to
  them.
- ACLs match `hdr(host)` against the container name and its altnames, plus the
  dashed `<name>.<SC_COMPANY_DOMAIN>` development form of each, plus every
  subdomain of the container name (`-m end .<name>`, `subacl` in `haproxy.js`).
  Aliases get no `use_backend` ACL at all — they only produce 301 redirect
  rules pointing at the container's own name — and subdomains of aliases or
  altnames are not matched either. Containers are emitted in descending
  domain-segment order so that first-match ACLs prefer the most specific name.
- Containers whose first dot-segment is `mail` are dropped from the **whole**
  generated configuration, not only from HTTP. Containers carrying the datastore
  key `static` keep their backends and redirect rules but get no `use_backend`
  ACLs.
- Exit codes: 0 success, 111 write error, 99 abnormal end.

**Certificate management:**
- `regenerate_haproxy_conf` calls `sync_haproxy_certificates /var/haproxy`
  (`modules/certificates/libs/certselectlib.sh`), which rebuilds `/var/haproxy`
  as the desired set and **prunes** everything else, so a renewal can no longer
  be shadowed by a stale copy. Per served domain a matching wildcard from
  `/etc/srvctl/cert/<domain>/` beats a per-domain (Let's Encrypt) certificate; a
  valid certificate always beats an expired one, and among equals the later
  `notAfter` wins. A domain covered by a valid wildcard deliberately gets no
  per-domain file, because HAProxy's SNI would prefer the exact match.
- If `certselectlib.sh` is not loaded on the host, the legacy path runs instead:
  `load_certificate_folder_files` copies with `cp -u` from the datastore cert
  directory and each `/etc/srvctl/cert/*`, never prunes, and `ca-bundle.pem` is
  removed from the crt directory afterwards.
- `hooks/update-install-host.sh` additionally seeds `/var/haproxy` with any
  pre-provisioned `/etc/srvctl/cert/<domain>/<domain>.pem`.

**Functions:**

| Function | Description |
|----------|-------------|
| `regenerate_haproxy_conf()` | Sync certificates, re-render the config, then reload — except under `ARG` `#cron.hourly`, where the reload is deliberately skipped |
| `restart_haproxy()` | Full restart; if the unit does not come back it runs `haproxy -c -f /etc/haproxy/haproxy.cfg` and prints the unit status |
| `reload_haproxy()` | Graceful reload, falling back to `restart_haproxy()` only if the unit went inactive |

Both service helpers report failure but return success, so a broken proxy does
not abort the surrounding regenerate run. `reload_haproxy` has no else branch:
a reload rejected while the old process keeps serving is still reported as
healthy, and the new configuration is silently never applied (`FIXME(v4)` in
`libs/systemdlib.sh`). Certificate refresh is ordered ahead of the re-render by
`hooks/regenerate.sh`, which runs `run_hook regenerate_certificates` first.

**Commands:**

| Command | Description |
|---------|-------------|
| `http-redirect VE [none\|https\|URL]` | Set or clear the container's HTTP redirect. No argument or `none` removes the key; an absent key means the default 301 http→https, `https` is a protocol flip, anything else is used verbatim as `redirect prefix <value>` |
| `https-redirect VE [none\|http\|URL]` | Set or clear the container's HTTPS redirect. No argument, `none`, or an absent key serves https directly; `http` is a protocol flip, anything else is used verbatim |

Both are `hs_only`, store the value under the container's `http-redirect` /
`https-redirect` datastore key (owner and reseller callers are escalated via
`sudomize`), then run the `regenerate_certificates` hook and regenerate and
reload HAProxy. All `/.well-known` paths are exempted from every redirect rule.

**Logging:** `hooks/update-install-host.sh` installs rsyslog and replaces
`/etc/rsyslog.conf` wholesale — the stock Fedora content plus the UDP 514 input
HAProxy logs to. `/etc/rsyslog.d/haproxy.conf` routes the `local2` facility to
`/var/log/haproxy.log`.

**Diagnostics:** The `diagnose` hook is currently a deliberate **no-op** —
every `socat` stats-socket query in `modules/haproxy/hooks/diagnose.sh` is
commented out, though `socat` is still installed for exactly that purpose. The
HTTP stats listener (`stats enable` / `stats uri /stats`) is likewise commented
out in `haproxy.js`; only the admin sockets `/var/lib/haproxy/stats` and
`/var/run/haproxy.stat` exist.

---

## Certificates and TLS

### Certificate Authority (CA)

The `ca` module (`libs/calib.sh`) provides a centralized root CA for internal infrastructure. State lives under `SC_ROOTCA_DIR` (default `/etc/srvctl/CA`), with one root CA per *network* name — `hostnet`, `usernet`, `gluster`, ... Issuance happens **only** on the CA host (`SC_ROOTCA_HOST == HOSTNAME`); everywhere else `root_CA_init` and `create_ca_certificate` are silent no-ops, which consumer hooks rely on being non-fatal.

**Root CA creation (`root_CA_create NET`):**
- 4096-bit RSA key at `ca/<net>.key.pem`, mode 600.
- Self-signed certificate `ca/<net>.crt.pem`, 3652 days (~10 years), CN `<SC_COMPANY>-<net>-ca`.
- Serial file `ca/<net>.srl` seeded to `02` — leaf signing uses `-CAserial`, not `-CAcreateserial`.
- Every artifact is created only when missing, and the root certificate itself is never expiry-checked: after 3652 days issuance silently continues against an expired CA.

**Certificate creation (`create_ca_certificate {server|client} NET NAME`):**
- 4096-bit RSA leaf key, certificate valid 1095 days (3 years), stored as `<net>/<type>-<name>.{key,crt}.pem`.
- Server certificates add `-extensions server` from `modules/certificates/openssl-server-ext.cnf` (`modules/ca/openssl-server-ext.cnf` carries the identical `[ server ]` section but a different header comment, and is never read).
- Re-issues when the certificate and key moduli disagree, or when the certificate fails `openssl x509 -checkend 86400` (24 hours).
- `usernet` **client** certificates are additionally exported as a passphrase-less `.p12`. The bundle is written only when absent, so a re-issued certificate leaves the old `.p12` in place.

**CA synchronization (`ca_sync`, `libs/netlib.sh`, fired from `hooks/regenerate.sh`):**
- On the CA host it only prints a notice; elsewhere it runs `rsync -aze ssh $SC_ROOTCA_HOST:/etc/srvctl/CA /etc/srvctl` after an `ssh … hostname` probe whose reply must equal the configured `SC_ROOTCA_HOST` — a short-name/FQDN mismatch skips the sync with a misleading "could not be reached" error.
- The rsync path is hardcoded, so a customized `SC_ROOTCA_DIR` is never replicated.
- Security caveat flagged in the code: the **entire** CA tree is copied — root CA private keys, every host/user key and the passwordless `.p12` bundles — so compromise of any cluster host is compromise of the whole PKI.

**Configuration:** `SC_ROOTCA_DIR` (default `/etc/srvctl/CA`), `SC_ROOTCA_HOST` (default: this host) and `SC_ROOTCA_SUBJ` (default `/C=HU/ST=Hungary/L=Budapest/O=SRVCTL-CA`) are defaulted in `modules/ca/hooks/pre-init.sh` and promoted to `readonly` in `hooks/post-init.sh`. `SC_ROOTCA_SUBJ` is a subject *prefix*; `/CN=…` is appended per certificate.

### Domain Certificates

The `certificates` module handles certificate lifecycle for containers and services. It ships no CLI commands — only libraries plus the `update-install-host` and `regenerate_certificates` hooks consumed by haproxy, containers, gui, postfix, perdition and named.

**Self-signed certificates (`create_selfsigned_domain_certificate DOMAIN PATH`, `libs/domaincertlib.sh`):**
- RSA 2048, 3650 days (10 years), CN `$DOMAIN`.
- SAN (Subject Alternative Name): `DNS:$DOMAIN` plus `DNS:*.$DOMAIN`.
- Produces `$DOMAIN.key` (passphrase stripped), `$DOMAIN.key.org` (the encrypted original), `$DOMAIN.csr`, `$DOMAIN.crt`, `$DOMAIN.pem` and a byte copy of the pem as `cert.pem`, plus the `config.txt` / `extfile.txt` / `random.txt` scratch files.
- PEM format is **private key followed by the certificate — no CA bundle**: a self-signed certificate has no chain, and the `ca-bundle.pem` path is computed in the function but never appended (the comment above the last `cat` still claims otherwise).
- Both combined pems contain the private key but are written with the default umask (0644); confidentiality depends on the directory modes set at `update-install`. The throwaway key passphrase is also persisted into `config.txt`.
- A still-valid `$DOMAIN.pem` is left alone; a certificate present without its key file aborts with exit code 46.

**`check_pem PEM`** (same lib, called by haproxy): when the pem expires within 7 days it prints subject/issuer/validity and **deletes the file**. It always returns 0 — callers depend on the deletion side effect plus their own `-f` re-check, not on the return value.

**Service certificates (`install_service_hostcertificate PATH`, `libs/servicecertlib.sh`):**
- Called with `/etc/postfix`, `/etc/perdition` and `/etc/srvctl-gui`; candidate sources are the directories under `/etc/srvctl/cert/`.
- Discovery priority, first hit wins: `$SC_COMPANY_DOMAIN` > `${HOSTNAME:3}` (hostname with its two-character site prefix stripped) > `$HOSTNAME` > the first glob-ordered subdirectory holding a usable pem+key > a freshly generated self-signed certificate for `$HOSTNAME`.
- `service_key_pem SRC DOM` (added in 4.0.0.x) accepts either a separate `<dom>.key` or a key **embedded in the combined `<dom>.pem`**, extracted with `openssl pkey` — so a single admin-supplied pem can serve both haproxy and the mail/GUI services.
- Writes `$PATH/crt.pem` (certificate with DH parameters appended), `$PATH/key.pem` and, when the source has one, `$PATH/ca-bundle.pem`; all three `chmod 400`.
- DH parameters are generated once per source directory and cached as `<src>/dhparam`. They are **1024 bit**, which modern TLS stacks reject; raising the size requires deleting the cached file.
- When no certificate can be located the function calls a bare `exit`, which inherits status 0 from `err` — the failure is invisible to `update-install` wrappers and cron.

### Let's Encrypt / ACME

The `letsencrypt` module automates public certificate acquisition over ACME http-01. Like `certificates` it exposes no CLI commands — everything runs from the `update-install-host` and `regenerate_certificates` hooks.

**ACME server (`apps/acme-server.js`):**
- Node HTTP server listening on `0.0.0.0:1028`, run as `acme-server.service` with `User=acme` (system uid 528).
- Binds `0.0.0.0:1028`, but no srvctl firewalld rule opens that port, so the reachable path is HAProxy: it matches `path_beg /.well-known/acme-challenge/` on port 80 and forwards to `127.0.0.1:1028` (backend `letsencrypt-backend`, `modules/haproxy/haproxy.js`). The port number and the path prefix are shared API between the two modules.
- Serves challenge files from `/var/acme/.well-known/acme-challenge/`; any other URL gets a plain-text `INVALID URL` body — always with HTTP 200.

**Certificate acquisition (`letsencrypt.js`, driven by `regenerate_letsencrypt`):**
- Container-level skips: names starting `mail.` are skipped unconditionally (checked first). Names ending `.devel` / `-devel` / `.local` / `-local` and dotless names are skipped only when the container declares no explicit `subdomains`; a container that does declare them is processed, and `container_domains()` then yields just those fqdns.
- Per-domain skips: `www.` names (they ride along as a second `-d`), domains covered by an installed wildcard at `/etc/srvctl/cert/<d>/<d>.pem`, a datastore certificate still valid for 7+ days, a live certbot lineage still valid for 7+ days (deployed, then skipped), domains not yet DNS-scanned, and domains whose scanned A record does not equal this host's `host_ip`.
- Runs `letsencrypt certonly --non-interactive --agree-tos --keep-until-expiring --expand --webroot --webroot-path /var/acme/ -d <domain>` (plus `-d www.<domain>` when the www A record also points here), logging to `/srv/<name>/letsencrypt<name>.log` or `/srv/<name>/letsencrypt-www.<name>.log`.
- Lineage selection tolerates certbot's `<domain>-0001` suffixes and picks the one with the latest `notAfter`; the freshly issued certificate is re-verified before deployment, because certbot can exit 0 while leaving an expired cert in place.
- Deploys `privkey + fullchain` to `$SC_DATASTORE_DIR/cert/<domain>.pem` and, when `/srv/<domain>/rootfs/etc/pki/tls/` exists, to the container's `private/localhost.key`, `certs/localhost.crt` (fullchain only), `certs/<domain>.pem` and `certs/localhost.pem`. Nothing is appended after certbot's `fullchain.pem`: it already carries the complete ISRG chain and a trust anchor does not belong in the presented chain (`modules/letsencrypt/bundlelib.js`).
- A datastore bundle that carries an expired certificate block — as every bundle written by earlier versions did, with DST Root CA X3 (expired 2021-09-30) appended — is not treated as valid even when its leaf is; it is rebuilt from the certbot lineage on the next `regenerate_certificates` run, without a new certbot request. Bundle composition and the expired-block detection are covered by `modules/letsencrypt/selftest/bundle.test.sh`.
- Per-domain failures are logged only: the process always exits 0, so a failed renewal is invisible to the caller and to cron.

**Installation (`install_acme`, `libs/letsencryptlib.sh`):**
- Installs certbot (`sc_install letsencrypt`) and writes `/etc/letsencrypt/cli.ini` (`webroot` authenticator, `webroot-path = /var/acme`, `email = webmaster@$SC_COMPANY_DOMAIN`).
- Creates the `acme` system user (uid 528) and the `/var/acme` webroot, removes a stale `/etc/letsencrypt/ca.pem` left by earlier versions, then generates, enables and starts `acme-server.service`.
- Called from **both** `modules/letsencrypt/hooks/update-install-host.sh` and `modules/certificates/hooks/update-install-host.sh`, so every `update-install` performs the install twice; re-runs are harmless apart from a `useradd: user 'acme' already exists` message.

The whole module is scheduled for the v4 DNS-01 wildcard redesign — document it, do not rework it.

### Wildcard Certificates

Wildcard certificates are **admin-supplied**: drop the combined pem into `/etc/srvctl/cert/<domain>/<domain>.pem`. srvctl never issues them (the ACME code path is http-01 only).

**Validation (`check_wildcard_pem PEM`, `libs/wildcardcertlib.sh`):** echoes the wildcard *base domain* when the first certificate in the pem survives `openssl x509 -checkend 604800` (7 days) and its subject CN starts with `*.`; otherwise it echoes the literal string `false`. That echoed string is the contract — callers compare against `false`, not against an exit code. Both OpenSSL spellings are matched (`subject=CN = *.X` and `subject=CN=*.X`).

**Application (`apply_wildcard_certificates`):** scans `/etc/srvctl/cert/*/*.pem` (not the datastore) and, for every valid wildcard, copies it to `$SC_DATASTORE_DIR/cert/<container>.pem` — mode 600 — for each container named `<base>` or `*.<base>`. Its only entry point is this module's `regenerate_certificates` hook, fired by the haproxy module (regenerate, `http-redirect`, `https-redirect`) and by named's `override-in-address`. A second branch meant to give dot-less container names the company wildcard is inert: its condition (`$c == $SC_COMPANY_DOMAIN` **and** `$c` contains no dot) can never both hold.

### HAProxy Certificate Selection

`libs/certselectlib.sh` (`sync_haproxy_certificates [TARGET_DIR]`, default `/var/haproxy`) rebuilds the directory HAProxy binds its `crt` to as a **desired set** and prunes everything else, replacing the old add-only `cp -u` that let a stale copy shadow a renewed certificate. It is called from `regenerate_haproxy_conf` (`modules/haproxy/libs/proxylib.sh`), guarded by `command -v` so a host without the certificates module falls back to the legacy copy path.

Preference per served domain:

1. A matching **wildcard** certificate from `$SC_ADMIN_CERT_DIR` (default `/etc/srvctl/cert`), installed as `<base>.pem`.
2. Otherwise a **per-domain** certificate from `$SC_DATASTORE_DIR/cert` (Let's Encrypt or fanned-out wildcard copies).
3. Self-signed per-container certificates live in `/srv/<c>/cert` and are never served by HAProxy.

Rules: expired certificates are never installed; among candidates for the same target file the later `notAfter` wins; and because HAProxy SNI prefers an exact match over a wildcard, a domain already covered by a valid wildcard gets **no** per-domain file, so the wildcard actually serves it. A wildcard covers `<base>` and one label below it — `deep.a.example.test` is *not* covered by `*.example.test`. Files are installed mode 600, and the prune pass removes stale shadows, superseded per-domain copies and `ca-bundle.pem` (not a servable certificate).

To rotate a wildcard: drop the new pem in `/etc/srvctl/cert/<domain>/` and run `srvctl regenerate` — the old copy is pruned automatically. Behaviour is covered by `modules/certificates/selftest/certselect.test.sh`.

Renewals also propagate to the other TLS services: the postfix and perdition `regenerate` hooks re-run `install_service_hostcertificate` before restarting, so `srvctl regenerate` refreshes mail TLS without a full `update-install`. The GUI still picks up its certificate at `update-install` only.

---

## Mail Stack

srvctl provides a complete mail infrastructure stack.

### Postfix (SMTP)

The `postfix` module manages SMTP on both hosts and containers.

**Host configuration (`conf/hs-main.cf` -> `/etc/postfix/main.cf`):**
- Accepts connections on all interfaces (`inet_interfaces = all`, `inet_protocols = all`).
- Trusts: `127.0.0.0/8`, `10.0.0.0/8`, `192.168.0.0/16`, `[::1]/128`, `[fe80::]/64`.
- Relays `$mydomain` plus `hash:/etc/postfix/relaydomains` (the generated map).
- TLS with certificates at `/etc/postfix/crt.pem` and `key.pem`, `smtpd_tls_security_level = may`, used for both `smtpd` and outbound `smtp`.
- SASL authentication enabled (`smtpd_sasl_type = cyrus`); `smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated`.
- Content filter: Amavis virus scanner (`127.0.0.1:10024`).
- OpenDKIM milter at `127.0.0.1:8891`, `milter_default_action = accept` (mail still flows unsigned when opendkim is down).
- 25 MB message size limit (`message_size_limit = 26214400`).
- The install hook appends two site-specific lines to the rendered file: `smtpd_tls_CAfile` (only when the certificate install produced a `ca-bundle.pem`) and `smtpd_sasl_local_domain = $SC_COMPANY_DOMAIN`.

**Container configuration (`conf/ve-main.cf` -> `/srv/<c>/rootfs/etc/postfix/main.cf`):**
- Relay host: `srvctl-gateway` (containers relay through the host).
- Maildir format for local delivery (`home_mailbox = Maildir/`).
- No virus scanning or DKIM (handled by the host).
- SASL enabled, no anonymous auth (`smtpd_sasl_security_options = noanonymous`).
- TLS from `/etc/pki/tls/certs/postfix.pem` and `/etc/pki/tls/private/postfix.key` inside the container.

**Functions (`libs/postfixlib.sh`, `libs/systemdlib.sh`):**
- `regenerate_etc_postfix_relaydomains()` — rewrites `/etc/postfix/relaydomains` from `get cluster postfix_relaydomains` (one `<domain>\tOK` line per host, container — `mail.` prefix stripped — and alias) and postmaps it. No-op when `/etc/postfix` is absent.
- `write_ve_postfix_conf()` — writes the container main.cf for a container *and* its mail-pair twin (`X` <-> `mail.X`), backing up the previous file as `main.cf-<timestamp>.bak`. Called by the containers module at add-ve time; do not rename.
- `restart_postfix()` — restart with status verification; on failure it runs `postfix check` and ends nonzero, which `run_hook`'s `exif` turns into an abort of the invoking command (a broken postfix can therefore kill `add-ve` mid-flow).
- `write_postfix_main()` — dead code: no callers, and the module condition is never true inside a container.

**Installation (`hooks/update-install-host.sh`):** installs spamassassin, postfix and amavisd-new, deploys the TLS host certificate into `/etc/postfix`, renders main.cf/master.cf from `conf/`, enables the three services, and rebuilds `/etc/aliases` from the static template — overwriting any locally added alias.

**Regenerate (`hooks/regenerate.sh`):** rewrites the relay map, re-installs the host certificate so a renewed cert reaches SMTP without a full `update-install`, then does a full restart (not a reload) of `postfix.service`.

**Firewall (`hooks/firewalld.sh`):** the stock firewalld services `smtp` (25/tcp) and `smtps` (465/tcp).

### SASL Authentication — saslauthd

The `saslauthd` module provides SASL authentication for Postfix using remote IMAP: SMTP AUTH credentials are verified by logging in to the local IMAP proxy, so mailbox passwords live only in the mail containers.

**Configuration:**
- `/etc/sasl2/smtpd.conf` (generated inline): `pwcheck_method: saslauthd`, `mech_list: LOGIN`.
- `/etc/sysconfig/saslauthd` from `conf/saslauthd.conf`: `SOCKETDIR=/run/saslauthd`, `MECH=rimap`.
- Flags: `-n 0 -O localhost -r` — `-n 0` makes saslauthd fork one process per connection instead of the default pool of 5 (`saslauthd(8)`), `-O localhost` names the rimap backend (perdition's `imap4.service` on 127.0.0.1:143), `-r` appends the realm to the login name.
- The unit is written to the RPM-owned `/usr/lib/systemd/system/saslauthd.service`, so any `cyrus-sasl` package update silently reverts it.
- The module still vendors patched `saslauthd` / `testsaslauthd` binaries under `modules/saslauthd/bin/` (for cyrus-sasl <= 2.1.26, which was incompatible with perdition). They are no longer copied over the system binaries — dead weight kept for history.
- `hooks/regenerate.sh` restarts `saslauthd.service` on **every** regenerate, even though nothing in its configuration is domain-dependent — a brief SMTP AUTH outage on each container operation.

**Commands:** (both `operators_only` + `sudomize`)
- `fix-saslauthd` — restarts saslauthd to fix mailing issues; self-described as temporary.
- `testsaslauthd user@ve` — host-only diagnostic that reads `/srv/<domain>/rootfs/home/<user>/.password` (`mail.<domain>` wins when both containers exist) and feeds it to `testsaslauthd -u … -p …`, exercising the saslauthd -> perdition -> mail-container chain. The password is echoed to the terminal and visible in the process list; with no password file found it prints `Mission failed.` and still attempts the authentication.

### Perdition (IMAP/POP3 Proxy)

The `perdition` module provides IMAP4/POP3 reverse proxying.

> **The installer is inert.** `install_perdition` (`libs/install_perdition.sh`) has no caller — its only call site is commented out in `hooks/update-install-host.sh`. A fresh host therefore never gets the perdition package, certificates, `/var/perdition` or the three units, while the module stays *enabled* and its regenerate hook aborts container provisioning on the missing map directory. The module is half-abandoned in v3 and slated for replacement by the v4 mail proxy; re-enable the commented line only deliberately.

**Routing (`perdition.js`):**
- Generates `/var/perdition/popmap.re` from the datastore container list, one line per container.
- Maps `(.*)@<domain>` to the `mail.<domain>` backend; a container already named `mail.*` maps to itself.
- Exit codes: 0 success, 99 sentinel (write callback never ran), 100 empty value, 111 write error, 112 datastore lib error. Any nonzero exit aborts the whole srvctl run via `exif` in `perditioncfg`.

**Configuration (`conf/perdition.conf` -> `/etc/perdition/perdition.conf`):**
- `bind_address 0.0.0.0`, `domain_delimiter @`, `strip_domain remote_login`.
- Regex routing via `map_library /usr/lib64/libperditiondb_posix_regex.so.0.0.0` with `map_library_opt /var/perdition/popmap.re` (the full `.so.0.0.0` path is required — the `.so.0` symlink does not work).
- `no_lookup` is also set, which per `perdition(8)` disables map lookups entirely and relays every user to `outgoing_server localhost` — it contradicts the popmap machinery above and is flagged for verification against a live host.
- The `/etc/perdition/popmap.re` seeded by the installer is dead; only `/var/perdition/popmap.re` is read.
- SSL certificates at `/etc/perdition/crt.pem` and `key.pem` (with DH parameters appended), installed by `install_service_hostcertificate` and refreshed on every regenerate. Certificate verification of the backend is deliberately off (`ssl_no_cert_verify`, `ssl_no_cn_verify`).

**Services:** three custom systemd units shipped in `services/` — `imap4s.service` (IMAP4S, 993), `pop3s.service` (POP3S, 995) and `imap4.service` (plain IMAP4, 143, `--bind_address 127.0.0.1`), the last existing only as the local rimap backend for saslauthd. There is no plain POP3 (110) unit.

**Firewall (`hooks/firewalld.sh`):** `imaps` (993) and `pop3s` (995) only. The `imap` (143) branch below them is dead code — it tests a `$container` variable that is never set on the host install path, and opening 143 would be pointless because `imap4.service` binds loopback.

### OpenDKIM (DKIM Signing)

The `opendkim` module adds DKIM signatures to outgoing email.

**Configuration generation (`opendkim.js`):**
- Generates a DKIM key with `opendkim-genkey` for every container that has a `/srv/<domain>` directory (the only "runs on this host" test), into `/srv/<domain>/opendkim/<selector>.private` — only when that file is missing.
- Copies the private key to `$SC_DATASTORE_DIR/opendkim/<domain>/<selector>.private`; the **datastore copy is the cross-host source of truth** (on clusters it may sit on the shared datastore) and is kept mode 000.
- Publishes the public key into `containers.json` as `dkim-<selector>-domainkey`, which the named module turns into the DNS TXT record.
- Writes `KeyTable` (`<selector>._domainkey.<domain> <domain>:<selector>:/var/opendkim/<domain>/<selector>.private`), `SigningTable` (`*@<domain> <selector>._domainkey.<domain>`) and `TrustedHosts` (seeded with `127.0.0.1`, `::1`, `10.0.0.0/8`, then every hosted domain) into the datastore folder.

**Runtime sync (`regenerate_opendkim`, `libs/opendkimlib.sh`):** compares `/var/opendkim` with the datastore folder (`diff -rq`); when they differ it replaces `/var/opendkim` wholesale, sets `opendkim:opendkim`, directories 750 and key/table files 640, and restarts `opendkim.service`. When they match it only starts the service if it was found inactive. `/var/opendkim` — not the datastore — is the path `/etc/opendkim.conf` references.

**Integration (`/etc/opendkim.conf`, written by `hooks/update-install-host.sh`):**
- Mode: `vs` (sign + verify), `Canonicalization relaxed/relaxed`, `MinimumKeyBits 1024`.
- Socket: `inet:8891@127.0.0.1` (Postfix milter integration).
- Selectors: `default` for regular domains, `mail` for `mail.*` containers.
- The install hook has its `regenerate_opendkim` call commented out but still enables and restarts the daemon, so on a fresh host `opendkim.service` fails to start (the KeyTable/SigningTable/TrustedHosts files do not exist yet) until the first `srvctl regenerate`; until then outgoing mail is unsigned.

### Mozilla Autoconfig

The `mozilla` module provides automatic email client configuration for Thunderbird.

**HTTP server (`apps/mozilla-autoconfig-server.js`, port 1029):**
- Answers `http://<domain>/.well-known/autoconfig/mail/config-v1.1.xml`; HAProxy matches `path_beg /.well-known/autoconfig/mail/` on every hosted domain and forwards to `127.0.0.1:1029` (backend `thunderbird-backend`). The port is not meant to be reached directly, but the process binds `0.0.0.0:1029` and runs as **root**.
- Every request — any method, any path — gets HTTP 200 and the same XML.
- Configures: IMAP (993/SSL), POP3 (995/SSL), SMTP (465/SSL), all pointing at this host's `os.hostname()`, which is baked into the XML once at startup: a hostname change or a non-FQDN hostname is only fixed by restarting the unit. The provider id is hardcoded to `D250.hu`.
- Password cleartext authentication.

**Installation (`install_mozilla_autoconfig`, `libs/install.sh`):** writes and starts `mozilla-autoconfig.service` at `update-install` — there is no regenerate, remove or diagnose counterpart. Its unit `Description` still reads "Letsencrypt server." (copy-paste), and the trailing `systemctl status` is the hook's exit status, so a unit that is not active at that instant (port 1029 occupied, restart backoff) aborts the whole `update-install` run and skips every alphabetically later module hook.

---

## User Management

### User Model

srvctl uses a hierarchical user model:

```
Root (user_id=0)
└── Resellers (single-character username, reseller_id field)
    └── Users (belong to a reseller)
        └── Containers (owned by users)
```

- **Root** has full access to everything. The seed record in `modules/datastore/default-users.json` is `root` with `user_id: 0`, `uid: 0`, `reseller_id: 0`.
- **Resellers** can create users and manage their users' containers. The datastore does mark reseller accounts (`new_reseller`, `modules/datastore/lib.js:911`, writes a `reseller_id`), but no guard reads that field: `reseller_only` (`modules/srvctl/libs/authlib.sh:77`) grants the role to any `SC_USER` whose name is exactly one character long, or to genuine root — the single-character username is a convention the guard depends on.
- **Users** can manage their own containers.

The reseller layer as a whole is a v4 deprecation candidate (G6) but is live on production; `add-user` and `change-user` still carry that guard; `add-reseller` is `root_only`.

Each user gets a `user_id`: one above the highest already allocated (starting at 1; freed ids are never reused), capped at 255 (`getNextUserId`, `modules/datastore/lib/mutators.mjs:21`; the legacy twin `get_next_user_id` survives at `lib.js:875`). It becomes the third octet of that user's container IPs — `10.<hostnet>.<user_id>.<offset>` — where the offset starts at 2 and allocation aborts above 250 (`findNextCip`, `lib/mutators.mjs:43`, the live twin of `find_next_cip_for_container_on_network` at `lib.js:838`). The Linux uid is a separate field (`uid`, allocated from 1000 upwards), and the container's root uid is derived as `65536 * (user_id * 255 + offset)`.

### Host Users — usersonhost

The `usersonhost` module manages users on the host system. Its condition sources the `containers` condition verbatim, so it is enabled exactly where `containers` is — on farm hosts, never inside a container.

**User provisioning (`main.js`):**

`main.js` is the engine; the bash side is only a wrapper (`userscfg`, `libs/bashlib.sh`). Run with no arguments, it walks every user in the datastore and ensures, in order:

1. the system account (`adduser` with the datastore `uid`; reseller-owned users get `<reseller> - <name>` as the gecos comment),
2. ssh keys in `$SC_DATASTORE_DIR/users/<user>/` (`id_ecdsa`, `srvctl_id_ecdsa`) plus a copy of `id_ecdsa` in `~/.ssh`, and `reseller_id_ecdsa.pub` / `srvctl_reseller_id_ecdsa.pub` symlinks for reseller-owned users,
3. a client certificate — `/etc/srvctl/CA/usernet/client-<user>.p12` from the `ca` module, minted on `SC_ROOTCA_HOST` (over ssh when that is a remote host) and copied to `~/<user>@$SC_COMPANY_DOMAIN.p12`,
4. the login password (`.password`/`.hash` in the datastore and `~/.password`).

It then bindfs-mounts each container into the homes of its owner, its `users[]` and its `readers[]` (the last read-only): `~/<container>/bindfs` for the rootfs and, except for `mail.*` containers, `~/<container>/html` for `/var/www/html`. A container living on another host is taken from the NFS mount `/var/srvctl3/nfs/<host>/srv/<container>/rootfs`.

**User configuration (`user.js`):** writes `~/.srvctl/user.conf` — one `SC_USER_<KEY>` line per scalar field of the user's datastore record. Dead code at this commit: its only wrapper, `usercfg` (`libs/bashlib.sh`), has no caller anywhere in the tree.

**Functions:**

| Function | Description |
|----------|-------------|
| `regenerate_users()` (`libs/userlib.sh:76`) | The only live bash function — calls `userscfg` (main.js), then returns; everything below that `return` is unreachable |
| `crate_user_password()` (`main.js:99`) | Sets the login password from the datastore. The `crate` typo is in the code, in both the JS and its dead bash twin |
| `create_user_id()` (`libs/userlib.sh:18`) | Dead code — reachable only from the unreachable tail of `regenerate_users`; duplicates the main.js logic |

**Commands:**

| Command | Description |
|---------|-------------|
| `add-user <name>` | Create a new user (reseller-only) |
| `add-reseller <name>` | Create a new reseller (root-only) |
| `add-publickey [KEY\|FILE]` | Add an ssh public key for the calling user; stored in the datastore as `users/<user>/<user>-<NOW>.pub` and verified with `ssh-keygen`. With no argument it opens `mcedit` so the key can be pasted in |
| `change-user <ve> <name>` | Reassign a container to another user — **stub**: validates its arguments, then errors out with "not implemented" |

### Container Users — usersonve

The `usersonve` module manages users inside containers. Its condition sources the `ve` module's condition, so it is enabled only *inside* a container, never on the host. Every command carries both `ve_only` and `root_only`.

**Commands:**

| Command | Description |
|---------|-------------|
| `add-user <name>` | Add or update a container user: creates the account if missing, reuses an existing `~/.password` or generates one via the `password` module, mails a welcome notice and chowns the home |
| `add-zerotier [networkid]` | Install ZeroTier VPN and join a network; with no argument the network id is looked up in `/var/srvctl3/share/common/zerotier-one/devicemap` |
| `vnc-desktop [desktop]` | Create the fixed appliance user `x` and an **unauthenticated** TigerVNC desktop on display `:0` (`securitytypes=none`, firewall opened permanently) — see [VNC Desktop](#vnc-desktop) |
| `install-crossover` | Install CrossOver (Wine) and its 32/64-bit library stack for user `x`, and point the kiosk autostart contract at it |
| `install-qlcplus` | Install QLC+ (DMX over Art-Net) from the openSUSE OBS repo for user `x` and rewrite its autostart contract. The repo release is hardcoded to `Fedora_38` |

---

## SSH Access

### SSH Key Management

The `ssh` module provides centralized SSH key management. Its condition is unconditionally `true`, so the module is enabled on every install — host or container — but everything meaningful in it is gated behind host-only hooks (`update_install_ssh_config` returns immediately when `SC_HOSTNET` is unset).

**SSH configuration (`sshd_config`, copied over `/etc/ssh/sshd_config` by `update-install`):**
- `PermitRootLogin yes`
- `PasswordAuthentication no` (key-based only) and `ChallengeResponseAuthentication no`
- `AuthorizedKeysCommand /usr/bin/bash /usr/local/share/srvctl/modules/ssh/sshd_authorization.sh %u`, with `AuthorizedKeysCommandUser root`
- X11 forwarding and GSSAPI enabled.

**Authorization script (`sshd_authorization.sh`):**

sshd calls it with the login name as `%u`. It `cat`s all four sources unconditionally — there is no precedence, the concatenation *is* the answer, and a missing file is silently skipped:

1. Common root keys: `/var/srvctl3/share/common/authorized_keys` — emitted for *every* login name, not just root, so any key placed here can log in as any local account on the host.
2. Host-to-host keys: `/var/srvctl3/gluster/srvctl-data/users/<user>/*.pub` — dead on every current install: the gluster module is hard-disabled (see [GlusterFS](#glusterfs)) and nothing mounts that path.
3. User datastore keys: `/var/srvctl3/datastore/users/<user>/*.pub`
4. Container user keys: `/var/srvctl3/share/containers/<hostname>/users/*/*.pub` — `$HOSTNAME` is the container's own name, so this line only ever matches inside a container.

**Key types:** two ECDSA keypairs per user in `$SC_DATASTORE_DIR/users/<user>/` — `id_ecdsa` for user access (also copied into `~/.ssh`) and `srvctl_id_ecdsa` for system use (srvctl-gui, sshpiperd, the reseller-user structure).

**Regeneration:** the regenerate hook calls `regenerate_ssh_config` (`libs/sshlib.sh`), which deletes stray files literally named `authorized_keys` under `/var/srvctl3/share/containers/*/users/*/` and then runs `ssh.js`. `ssh.js` performs all four of its steps on every invocation: write the `/etc/ssh/ssh_config.d/srvctl-chosts.conf` and `srvctl-containers.conf` drop-ins; `ssh-keyscan` any host or container with no stored `host_key`; render `/var/srvctl3/share/common/known_hosts` and `/var/srvctl3/ssh/known_hosts`; copy every container user's `.pub`/`.hash` files to `/var/srvctl3/share/containers/<C>/users/<U>/`.

**Known gap:** those copied `<user>-*.pub` files are never removed — not by regenerate, not by `remove-ve` — so revoking a key, or dropping a user from a container, does not revoke their access to it.

### SSHPipeRD — SSH Proxy

The `sshpiperd` module provides an SSH proxy that routes connections to containers based on composite usernames. Its condition mirrors the `containers` condition, so it is present on every farm host.

**Username format:** `<user>_<container>_<login>`

For example: `john_example.com_root` connects as `root` to the container `example.com`, authenticated as srvctl user `john`. The first field selects the key directory, the second is dialled verbatim as `<container>:22`, and the third is the account to log in as upstream (the code calls it `sc_as`).

**Regex validation:** `^[a-z][-a-z0-9.]{0,31}_[-a-z0-9.]{0,256}_[-a-z0-9]{0,31}$`

**Implementation:** a vendored, patched build of the Go sshpiper (`tg123/sshpiper`); the srvctl patch is `modules/sshpiperd/workingdir.go`. `build.sh` is a developer-only rebuild script and cannot currently complete — it calls the `run` helper without sourcing lablib, and its GOPATH `go get` workflow is dead under module-mode Go.

**Key mapping:**
- Concatenates every `*.pub` in the user's directory under the working dir *with* `/var/srvctl3/share/common/authorized_keys`, then looks for the offered key in that combined list — the common file is not a fallback, it is always included.
- On a match, loads the user's `srvctl_id_ecdsa` as the upstream key. The daemon rejects it unless the file is group/other-free (a `0077` mode check), which the bindfs view must preserve.

**Setup:**
- Listens on port **2222**, which is the sshpiperd binary's built-in default — the unit passes only `--server_key` and sets no `--port`. `tcp/2222` is opened in firewalld by the install hook.
- Runs as the `sshpiper` system user (`adduser --system sshpiper`), **not** `sshpiperd`.
- Host key `/etc/sshpiper/ssh_host_rsa_key`: the filename says rsa, the key is generated as ECDSA. Every port-2222 client pins it in `known_hosts`, so it must never be renamed or regenerated.
- Uses `bindfs -r -p +X --map=root/sshpiper` to mount `/var/srvctl3/datastore/users` read-only at `/var/sshpiper` (that path is hardcoded, not `$SC_DATASTORE_RW_DIR`).

**Inert on a fresh host.** `sc update-install` installs the binary and the unit but never enables or starts `sshpiperd.service`, so the daemon stays dead until an operator runs `sc sshpiperd !`. The bindfs mount is made only from hooks — no fstab entry, no `.mount` unit — so after a reboot `/var/sshpiper` is empty and all sshpiperd authentication fails until the next regenerate. The vendored binary is stale as well (it announces 3.1.2.1 and reads `srvctl_id_rsa`, while the rest of srvctl writes `srvctl_id_ecdsa`), so upstream key mapping cannot succeed on a fresh host without a rebuild.

---

## Storage

### GlusterFS

The `gluster` module manages distributed storage across cluster hosts.

> **Hard-disabled at this commit.** The "all checks passed" branch of `modules/gluster/module-condition.sh:59` is `echo false`, with `#echo true` kept commented out directly beneath it as the record of the kill-switch. `SC_USE_GLUSTER` is therefore never true on any host, multi-host or not: the libs are never sourced, the hooks never run, no bricks or volumes are created, `/var/srvctl3/gluster/<datadir>` is never mounted, and gluster certificate renewal never happens. The module is a deprecation candidate for v4 (G4). Everything below describes the *intended* behaviour, for the day that line is flipped back.

**Intended activation:** real (non-container) hosts listed in `/var/srvctl3/host/hosts.json` alongside at least one other host. The single-host rejection at `module-condition.sh:46-50` is live and would still apply.

**Functions:**

| Function | Description |
|----------|-------------|
| `gluster_install()` | Installs glusterfs-server, symlinks `/etc/ssl/glusterfs.{ca,pem,key}` onto the `gluster-*.pem` CA material, touches `secure-access`, opens the firewalld service and starts `glusterd` |
| `gluster_configure(datadir, mountdir)` | Peer-probes every cluster host, then creates and starts the replicated volume (one brick per host, replica count = host count, client and server SSL on) |
| `gluster_mount_data(datadir, mountdir)` | Ensures the read-only bind mount and the FUSE mount; returns 0 when the FUSE mount is present — and, because its four early error paths `return` right after `err` (which itself succeeds), also when the brick or the TLS material is missing; that return value drives `SC_DATASTORE_RO_USE` |
| `gluster_reset(datadir)` | Tears down the volume and the local brick — an operator tool, run via `sc exec-function` |

**Volumes:** two, each named after its `datadir`:

| datadir | Brick | Read-only bind mount | FUSE mount |
|---------|-------|----------------------|------------|
| `srvctl-data` | `/glu/srvctl-data/brick` | `/var/srvctl3/gluster/srvctl-data` | `$SC_DATASTORE_RW_DIR` (`/var/srvctl3/datastore`) |
| `srvctl-storage` | `/glu/srvctl-storage/brick` | `/var/srvctl3/gluster/srvctl-storage` | `/var/srvctl3/storage` |

`gluster_configure` is called from the `datastore` and `static` `update-install-host` hooks and `gluster_mount_data` from their `init` hooks; all four call sites sit behind `if $SC_USE_GLUSTER` and are dead at this commit.

**Fallout of the kill-switch:** `modules/datastore/hooks/pre-init.sh:18` still defaults `SC_DATASTORE_RO_DIR` to `/var/srvctl3/gluster/srvctl-data`, a path nothing mounts, and `modules/ssh/sshd_authorization.sh:11` still reads public keys from under it. Both degrade silently — the datastore uses its local read-write directory instead, and that key line simply contributes nothing.

### NFS

The `nfs` module shares `/srv` across the cluster via NFS. Its condition mirrors the `containers` condition, so every cluster host both exports and mounts — there is no independent opt-out.

**Exports:** `/etc/exports` is overwritten with a single line, `/srv 10.15.0.0/255.255.0.0(rw,no_root_squash)` — read-write and *without* root squashing, to the whole OpenVPN mesh. Any compromised cluster member therefore has root-equivalent write access to every other host's `/srv`, and any admin-maintained export lines on the host are lost.

**Mounts:** for every host in `get cluster host_list`, `nfs_mount` pings `10.15.<hostnet>.1`, probes the host with `showmount -e <host>` (by DNS name, not over the mesh address), and mounts `10.15.<hostnet>.1:/srv` at `/var/srvctl3/nfs/<host>/srv/` — the path `modules/usersonhost/main.js` expects for containers that live on remote hosts. Every failure is logged and skipped, never fatal.

**Operational notes:** the mounts are runtime-only (no fstab entry, no `.mount` unit), so they are gone after a reboot until the next `sc regenerate`; there is no already-mounted check, so repeated regenerates stack mounts on the same target; each host also NFS-loopback-mounts its own `/srv`; and the install hook never installs `nfs-utils`, so on a minimal Fedora host `/etc/exports` is written but never served.

### Static File Server

The `static` module runs a root Node.js HTTP daemon (`server.js`) on port 1280, on all interfaces, as `static-server.service`. It is plain `http.createServer` plus the `finalhandler` and `serve-static` packages — **not** Express. Both packages are installed with `npm install -g` by the install hook and `require`d through the hardcoded prefix `/usr/lib/node_modules`, so a different npm prefix turns `Restart=always` into a crash loop.

**Document root:** `/var/srvctl3/storage/static/<host>/html`, where `<host>` comes from the request's `Host` header (a missing `Host` falls back to `d250.hu`; leading `www.` and `static.` are stripped). The tree is seeded per container by `regenerate_static_server` (`libs/regenerate.sh`), which creates the directory and a branded placeholder `index.html` only when none exists — existing content is never overwritten.

**Logging:** one line per request — host, URL, user-agent, X-Forwarded-For.

**Caveats.** Nothing currently routes to port 1280: haproxy's default backend is `localhost:1282` (the `default` module) and the old pound proxy is gone, so this is an orphaned but permanently running root HTTP server. Its error handler calls `res.send()`, an Express API that does not exist on `http.ServerResponse`, so any `serve-static` error — a malformed percent-escape in the URL is enough — throws an uncaught `TypeError` and kills the process. And because the docroot is built from the unvalidated `Host` header, a crafted header can escape the storage tree; the module is an open v4 audit item.

### FTP — vsftpd

The `ftp` module installs the `vsftpd` package on farm hosts (its condition sources the `containers` condition) and opens firewalld's stock `ftp` service — TCP/21 plus the FTP conntrack helper — permanently in the default zone.

That is all it does. The module is two hooks (`hooks/update-install-host.sh`, `hooks/firewalld.sh`) and a module condition: no libs, no commands, no configuration templates. vsftpd is never configured, enabled or started, so plaintext port 21 stands open on every host with no opt-out and no daemon behind it. Treat the module as unmaintained.

---

## Application Modules

### WordPress

The `wordpress` module is enabled inside every non-`mail.*` container and never
on a host (`module-condition.sh` delegates to the `ve` condition). It ships one
`root_only` command.

**Installation (`srvctl install-wordpress`):**

1. Installs `php`, `php-mysqlnd` and the Fedora `wordpress` package. The old PHP
   8.0.11 version pin is retired — `install-wordpress.sh` installs the current
   distribution PHP (the line reads `sc_install php #-8.0.11`).
2. Writes `/etc/httpd/conf.d/wp-permalink.conf` (`mod_rewrite` front controller
   for pretty permalinks) and `logging-behind-reverse-proxy.conf` (redefines the
   `combined` LogFormat to log `X-Forwarded-For`), and deletes the RPM's
   `/etc/httpd/conf.d/wordpress.conf`.
3. Downloads `https://wordpress.org/latest.zip` and overlays it onto
   `/var/www/html`.
4. Calls `setup_mariadb`, then `add_mariadb_db` for the database named
   `<first hostname label>_wp`. `add_mariadb_db` sanitizes that name and sets the
   `db_name`/`db_usr`/`db_pwd` globals consumed by the next step.
5. Generates `wp-config.php` (credentials, fresh keys and salts,
   `FORCE_SSL_ADMIN`) plus a one-shot `wp-install.php`, and runs the headless
   install: site title `$HOSTNAME`, user `admin`, mail `root@localhost`, password
   from `get_password`.
6. Saves that password to `/var/www/html/.admin` (mode 000), prints it once as
   `Wordpress @ https://$HOSTNAME/wp-admin admin:<password>`, removes the distro
   `index.html` and enables httpd with `add_service httpd`.

`recreate-ve` rsyncs `/var/www/html/wp-content`, `wp-config.php` and
`/var/lib/mysql` out of the temporary container — these paths are an API and must
not move.

**Password recovery:** `scripts/restore-wordpress-password.sh` is a standalone
script, not a srvctl command: run it inside the container with the database name
as first argument. It re-applies the password saved in `/var/www/html/.admin` as
an MD5 hash in `wp_users` (WordPress upgrades the hash on the next login). It is
currently **non-functional** — its table sanity check sends the quoted literal
`'show tables'` to MySQL, which always errors, so the `UPDATE` is never reached.

### Odoo ERP

The `odoo` module installs Odoo 14 Community Edition. Like `wordpress` it is
active only inside non-`mail.*` containers. The body of `install-odoo` is a
vendored third-party installer (hisi.hr, LGPL v3+, v1.14.1) pasted under a srvctl
command header: it prints with its own `echo`/`tput` instead of the srvctl
helpers, and each block is guarded by a marker file so a re-run resumes a partial
install.

**Installation (`srvctl install-odoo`):**

1. `dnf update -y`, then the build and runtime dependencies (output discarded).
2. Creates the `odoo` system user with home `/srv/odoo`.
3. PostgreSQL `initdb`, `ident` → `md5` in `pg_hba.conf`, `template0`/`template1`
   re-encoded and the `odoo` role created.
4. Git clones OCA/OCB branch `14.0` into `/srv/odoo/odoo14`.
5. Creates `/srv/odoo/addons/{symlink,OCA}`. Every OCA addon clone and symlink is
   commented out in the script, so the tree is created empty.
6. Python virtualenv at `/srv/venv`, then `pip3 install -r requirements.txt`.
7. Rewrites `/etc/httpd/conf.d/ssl.conf` into an HTTPS reverse proxy (the
   original is kept as `ssl.conf.org`) and installs `odoo.service`.

**Configuration** (`/srv/odoo/odoo14.conf`):
- Port 8069 (XML-RPC), 8072 (longpolling), both bound to 127.0.0.1.
- Proxy mode enabled.
- 5 workers, `limit_memory_hard` 2.5 GiB / soft 2 GiB, `limit_time_cpu` 600 s,
  `limit_time_real` 1200 s, `max_cron_threads` 1.

**Inert parts:** the wkhtmltopdf/wkhtmltoimage and MS core fonts installs are
commented out ("Blocked WKHTML installation due to version mismatch"), so PDF
report rendering is not provisioned. The installer also exports the Croatian
locale `hr_HR.UTF-8` inherited from its upstream author and uses it for the
PostgreSQL template collation, and its dependency list contains `node`, which is
not a Fedora package name.

### MariaDB

The `mariadb` module manages MySQL/MariaDB database servers. It is enabled when
`mariadb.service` is active and, via the `ve` fall-through in its module
condition, inside every container. It ships **no commands**: the library is
consumed by the `wordpress` module (`setup_mariadb`, `add_mariadb_db`) and by
`backupdb` (`backup_mariadb`).

**Functions:**

| Function | Description |
|----------|-------------|
| `setup_mariadb()` | Install mariadb-server, then enable and restart the service |
| `check_mariadb_connection()` | Set the global `SC_MDA` root-auth argument and verify it with `mysql -e status` |
| `backup_mariadb()` | Wipe the previous generation, then dump every database except `information_schema`/`performance_schema` to `/root/mariadb-dump/<timestamp>/<db>.sql`; sets `BACKUP_POINT` |
| `add_mariadb_db [NAME]` | Create database + same-named user + generated password (default name `$HOSTNAME`) |
| `secure_mariadb()` | Remove anonymous/remote-root users and the test DB, set a root password — no callers in the repo |
| `mysql_root [QUERY]` | Run one query as root, or open an interactive root shell — no callers in the repo |

`SC_MDA` is `--defaults-file=$SC_MARIADB_DUMP_CONF` when that file exists
(`/etc/mysqldump.conf` by default), otherwise `-u root`; a failed connection test
terminates the whole srvctl process.

`add_mariadb_db` derives its names deterministically — `.` and `-` become `_`,
the user name is then truncated to 15 characters and the database name to 63 —
and is a no-op when `/etc/mariadb-<db>.conf` already exists, in which case it only
re-reads the saved password. The derivation is a compatibility contract with
existing production databases.

**Credential storage:** Per-database config at `/etc/mariadb-<dbname>.conf`
(`dbf:`/`usr:`/`pwd:` lines), dump credentials at `/etc/mysqldump.conf` (a mysql
`[client]` section). Both are written with the default umask and hold plaintext
passwords.

### Codepad

The `codepad` module deploys collaborative code editor containers. It is enabled
on hosts exactly when the `containers` module is — never inside a container and
never on a `mail.*` host.

**Container creation (`srvctl add-codepad <name>`):**
- Deprecated but kept: the canonical path is `add-ve <name> codepad`, which
  reaches this module through the `add_ve_codepad` hook. Only `add-codepad`
  enforces the `*-devel` name rule that is the legacy opt-in for codepad
  port 9000 (9001 and 9002 are routed by the `/var/codepad/codepad4` rootfs
  check instead, which also covers 9000); a name without that suffix, or a
  `mail.*` name, exits 13.
- Creates the container from the `codepad` template rootfs, runs `regenerate`,
  then `init_codepad_project`.

**Template rootfs (`mkrootfs_fedora_install_codepad`, run by `sc regenerate rootfs`):**
- `mkrootfs_fedora_base codepad` with systemd-container, httpd, mod_ssl, gzip,
  git-core, curl, python, openssl-devel, postgresql-devel, mariadb-server,
  ShellCheck and make. `gcc-c++` is installed on the *host* instead, by this
  module's `update-install-host` hook.
- Populates `/var/codepad` (ECDSA key, self-signed certificate, `server.js` stub,
  `.profile`, `.gitconfig`), creates a bare git repo at `/var/git` cloned into
  `/srv/codepad-project`, and writes the `codepad.service` unit.
- **No MongoDB is installed.** The build only symlinks `mongod.service` into
  `multi-user.target.wants`, so the unit is a dangling link that fails to load at
  every container boot (`libs/mkrootfs_fedora_install_codepad.sh`).

**Access management (`access.js`):**
- Copies each authorized user's `*.hash`, `*.password` and `*.ip` files from
  `$SC_DATASTORE_DIR/users/<u>/` into
  `/var/srvctl3/share/containers/<c>/users/<u>/`, which is bind-mounted read-only
  into the container.
- Authorized are: users with `access == "all"`, the container's primary user,
  every entry of its `users[]` list, and the primary user's reseller. `root` is
  always skipped. Driven by the module's `regenerate` hook through
  `configure_codepad_access`.

**Project initialization (`init_codepad_project.sh`):**
- Fresh ECDSA SSH keypair per container; the public key becomes both the codepad
  user's `authorized_keys` and root's inside that container.
- Chowns `/var/codepad` to the uid-shifted codepad uid (container uid + 804).
- Symlinks the users share (`/var/srvctl3/share/containers/<C>/users`) and the
  boilerplate project.

**Firewall:** the host opens 9000/9001/9002 as the firewalld services `https9000`,
`https9001` and `https9002`. Inside the template the same ports are registered
under the same three names, alongside 80, 443, 8080, 8443 and 9200. All of those
service names are load-bearing and must not be renamed. All three codepad ports
are TLS — haproxy binds each `ssl crt /var/haproxy` — so the host's 9000 service,
called `http9000` in earlier versions, was renamed to `https9000` to match both
the protocol and the template. A host installed before that rename keeps the stale
`http9000` service enabled alongside it (same port, harmless); remove it with
`firewall-cmd --zone="$(firewall-cmd --get-default-zone)" --permanent
--remove-service=http9000`, delete `/etc/firewalld/services/http9000.xml` and
reload. The template
registration only reaches **newly built** rootfs images: in a codepad container
created before 9002 was added, open it in place with
`sc exec-function firewalld_add_service https9002 tcp 9002`.

### VNC Desktop

The `usersonve` module includes VNC desktop creation via `vnc-desktop [DESKTOP]`:

1. Installs `tigervnc-server`.
2. Creates user `x` for VNC access.
3. Configures the desktop session. The default is `none` — a bare kiosk xsession
   that just execs `/home/x/autostart.sh`. Any other argument is installed with
   `dnf -y install "$DESKTOP"`; the `gnome` branch is unimplemented and exits 0
   without installing anything.
4. Sets up `xbindkeys`, binding Ctrl+Alt+Delete to `/home/x/autostart.sh` — the
   contract `install-crossover` and `install-qlcplus` later overwrite with their
   own application.
5. Creates a systemd `vncserver.service` around `vncsession-start :0`, with
   `:0=x` in `/etc/tigervnc/vncserver.users`.

The session config is written with `securitytypes=none` and geometry 1920x1080,
and the `vnc-server` firewall service is opened permanently, so the resulting
desktop is **unauthenticated by design**. Run `ls /usr/share/xsessions` after
installation for the session names actually available.

### VNC Proxy

The `vncproxy` module publishes the per-container VNC servers through a single
host-side proxy listening on `$SC_HOST_IP:5900`. It is enabled exactly when the
`containers` module is.

**`srvctl add-vnc-user <VE> <USERNAME>`** (`hs_only`, plus `owner_only` on the
container) stores the lowercased username in the datastore under
`containers[VE].vncusers`, regenerates the proxy configuration and restarts the
service. This is **the only time the user's VNC password is ever displayed**: it
is derived deterministically as an 8-character `hash(container, vncuser)` and is
not retrievable anywhere else, so if it is lost the only recovery is to re-run the
command. The derivation is a frozen algorithm — changing it invalidates every
deployed password.

`vncproxy.js` rewrites `/var/vncproxy/records` for *all* containers, and
`start.sh` (the unit's `ExecStart`) sources that file as bash to rebuild
`/var/vncproxy/vncproxy.db` from scratch on every start before execing the proxy
binary. Nothing in the module is installed automatically: `bash build.sh` compiles
the vendored C++ tree to `/bin/vncproxy`, `bash dnf.sh` installs sqlite,
`services/vncproxy.service` is copied to `/etc/systemd/system` by hand, and
opening the firewall for port 5900 is manual as well (those commands are
commented out in `add-vnc-user.sh`). `start.sh` exits 78 (EX_CONFIG, listed in the
unit's `RestartPreventExitStatus`) when no host projection or no `SC_HOST_IP` is
available. `vncproxy-restarter.sh` is an optional nmap-based watchdog whose
`.service` and `.timer` units exist only as comments inside that file.

---

## Backup

### Filesystem Backup

The `backup` module provides rsync-based backup utilities. Its module condition is
unconditionally true. Nothing in the repo calls these functions — they are meant
for custom include scripts or `sc exec-function`.

**Functions:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `local_backup` | `[directories]` | Backs up local directories to `$SC_BACKUP_PATH/$HOSTNAME` |
| `server_backup` | `[host] [directories]` | Remote backup via SSH with rsync, into `$SC_BACKUP_PATH/<hostname reported by host>` |
| `remote_backup` | `[proxyhost] [datahost] [directories]` | Backup through an SSH jump host, into `$SC_BACKUP_PATH/<hostname reported by datahost>`; the transfer itself runs as `root@datahost` |
| `display_backup_geometry` | `[host] [dir] [ssize] [dsize] [scount] [dcount]` | Print and log one size/file-count comparison line |

**Features:**
- `SC_BACKUP_PATH` defaults to `/backup`.
- Rsync with `--delete-after` — mirror semantics, so files deleted at the source
  are deleted from the backup too. Flags per function: `-a` locally, `-avze ssh`
  for `server_backup`, `-avz -e "ssh -A <proxy> ssh"` for `remote_backup`.
- Source vs destination size and file count display, computed only on a TTY: under
  cron the geometry fields in the log stay empty.
- Logging to `$SC_HOME/.srvctl/backup.log`. Failures of all three functions are
  logged with the same `local-backup-failure` label.
- Concurrent backup prevention by grepping `systemctl status` for a matching
  rsync; a match skips that directory for this run.

### Container Backup

**7-Zip backup (`local_container_7z_backup`) — currently disabled:**

The function body sits behind a bare `exit` in `modules/backup/libs/7zlib.sh`:
calling it terminates the srvctl process with status 0, so the caller sees success
and no archive is written. The whole library also self-disables (`return`) when
`/usr/bin/7z` is absent, and it keys off its own `BACKUP_PATH` variable (default
`/backup`), *not* `SC_BACKUP_PATH`. It has no callers in the repo.

When enabled it creates individual 7z archives per container directory under
`$BACKUP_PATH/$HOSTNAME/<container>` (or an explicit second argument):

| Archive | Content |
|---------|---------|
| `cert.7z` | `/srv/<C>/cert` — SSL certificates |
| `srv.7z` | `rootfs/srv` — service data |
| `home.7z` | `rootfs/home` — user home directories |
| `root.7z` | `rootfs/root` — root home |
| `etc.7z` | `rootfs/etc` — configuration |
| `var.7z` | `rootfs/var` — variable data |
| `var-lib-mysql.7z` | `rootfs/var/lib/mysql` — database files |

Also saves a `filelist`, a `creation-date` stamp and — only when the container
answers ssh — a `packagelist` from `dnf list installed`.

**The live container backup** is `backup_ve`
(`modules/containers/libs/backupcontainerlib.sh`), used by `backup-ve`,
`remove-ve` and `recreate-ve`. It writes `container.json` and the package lists
into `/srv/<C>`, then rsyncs the whole tree to
`$SC_BACKUP_PATH/srvctl-containers/<C>/<timestamp>`, or onto `$SC_BACKUP_HOST`
over ssh when that is set to another machine.

### Database Backup

The `backupdb` module handles database-specific backups. Its module condition is
unconditionally true; it ships no commands and no hooks, and exposes a single
library function — run it on the machine that owns the data with
`sc exec-function backupdb`.

**MariaDB:** when `/var/lib/mysql` and `/usr/bin/mysql` both exist, sources the
mariadb library by absolute path (so it works even with `SC_USE_MARIADB=false`)
and calls `backup_mariadb()`, which wipes `/root/mariadb-dump/*` and then dumps
each database individually to `/root/mariadb-dump/<timestamp>/<db>.sql`. A failed
connection test exits the whole process, in which case the MongoDB branch never
runs.

**MongoDB:** when `/var/lib/mongodb` exists — the Fedora datadir only, so
mongodb.org RPM installs at `/var/lib/mongo` are silently skipped — wipes
`/root/mongodb-dump/*` and dumps to `/root/mongodb-dump/<timestamp>/` using the
**vendored** binary in `modules/backupdb/bin/` rather than the system
mongo-tools package, a workaround for Red Hat bug 1537510. Eight r3.6.0 (2017,
x86_64) tools are vendored — bsondump, mongodump, mongoexport, mongofiles,
mongoimport, mongorestore, mongostat, mongotop — but only `mongodump` is ever
invoked, and its exit status is not checked.

---

## System Administration

### Diagnostics

`srvctl diagnose` (`modules/srvctl/commands/diagnose.sh`) is a read-only first-aid
report — it runs status commands only and changes nothing.

The command itself prints:

- srvctl version (from `$SC_INSTALL_DIR/version`) and key variables (`diagnose_variables`).
- Uptime, `uname -a` and `sestatus`.
- Memory (`free -g`, `vmstat -s`) and disk usage (`df -H`).
- Kernel and boot entries — only when `grub2-editenv` and `/boot/grub2/grub.cfg` are present.
- Status of every inactive unit in `multi-user.target.wants`, then `systemctl list-units --state=failed`.
- Postfix fatal errors since yesterday and the mail queue (`postqueue -p`).
- Firewall state, default zone, services and interfaces — only when `/usr/sbin/firewalld` exists.
- Process table (`top -n 1`) and connected shell users (`w`).

`run_hooks diagnose` then appends one section per enabled module: container
pingback to 8.8.8.8 and `d250.hu` from every running container,
`systemd-cgtop -m -n 1` and the `/srv` permission check (must be `drwxr-x---`)
from `containers`; a dump of `/var/srvctl3/host/hosts.json` from `datastore`;
a ping plus `showmount -e` per cluster host from `nfs`. The `haproxy` hook is
inert — its socat stats queries are all commented out — and the `gluster` hook
never runs because that module is hard-disabled. The `firewalld` hook repeats
the firewall section and reuses the `$zone` variable set by the command, so on
a machine without firewalld it prints `firewall-cmd --zone=` errors.

### Version Management

`srvctl version` (`modules/srvctl/commands/version.sh`) queries dnf through
`msg_version_installed` (`modules/srvctl/libs/fedoralib.sh`) for exactly two
packages: **postfix** and **nodejs**.

There is no `run_hook version` call anywhere in the tree, so the
`hooks/version.sh` files shipped by the `named`, `postfix`, `perdition`,
`opendkim` and `saslauthd` modules are dead code and never contribute a line.
Wiring the hook up would change the output and is deferred to v4 (see the
`FIXME(v4)` note at the end of `commands/version.sh`).

The version file at `$SC_INSTALL_DIR/version` holds the current version string
— `4.0.0.8` on this branch — and is what `srvctl.sh` prefixes with `srvctl-`
to build `$SRVCTL`.

### Update and Installation

`srvctl update-install HOSTNAME` (`modules/srvctl/commands/update-install.sh`,
`root_only`) is the primary installation and update mechanism. It does **not**
update the srvctl code itself — code arrives out-of-band (git clone, or
`/bin/pop` on dev boxes).

Every run starts with `sc_update`, a full `dnf -y --releasever $VERSION_ID update`.

**In a container** (`SC_USE_CONTAINERS` false): runs the `update-install-ve`
hooks and exits 0. Any argument is ignored.

**On a host** (`SC_USE_CONTAINERS` true) the HOSTNAME argument is **required**.
Without it the command prints "No argument, so we will stop here." and exits
right after the dnf update — none of the steps below run. With an argument:

1. Creates `/etc/srvctl/debug.conf` containing `DEBUG=true` if it does not exist.
2. Disables SELinux by overwriting `/etc/selinux/config` with the single line `SELINUX=disabled` (needs a reboot; this also drops `SELINUXTYPE=`).
3. Installs `mc`, `nodejs` and `git` when the binaries are missing.
4. First boot only — if `$HOSTNAME` is still `localhost.localdomain`, writes the argument to `/etc/hostname`, removes `/var/local/srvctl/modules.conf` and **exits 5**, which means *reboot required*. Install automation keys off that exit code.
5. Sets a default global git identity (`srvctl` / `srvctl@$HOSTNAME`).
6. `ssh-keyscan` of every cluster host, appended to `~/.ssh/known_hosts` (appended without deduplication, so the file grows on every run).
7. Runs every module's `update-install-host` hooks — services, firewall rules, branded error pages, the hourly regenerate cron job. The `ntp` module consists of nothing but this hook: it installs `ntpsec`, then enables and starts `ntpd.service`. It never disables Fedora's default `chronyd`, so both time daemons stay enabled and race at the next boot — disable `chronyd` by hand.
8. Rebuilds `/var/local/srvctl/commands.spec` via `make_commands_spec` when `SC_USE_GUI` is true (it is, on every host).
9. Installs bash completion to `/etc/bash_completion.d/srvctl-completion`, removing that path first when it is a symlink back into the install dir.
10. Runs `set_permissions` (`commonlib.sh`) and prints "please reboot".

### Regeneration

`srvctl regenerate [all-hosts|rootfs]`
(`modules/containers/commands/regenerate.sh`, `root_only` and host-only)
rewrites generated configuration from the datastore. Only the two literals
`rootfs` and `all-hosts` are special-cased — any other argument silently falls
through to the plain single-host regenerate, so `srvctl regenerate all` does
**not** touch the cluster.

**No argument:** runs `run_hook regenerate`, i.e. the `regenerate` hook of every
enabled module:

| Module | Hook does |
|--------|-----------|
| `containers` | Imports stray `/srv` containers into the database, creates locally-missing ones, repairs ownership, rewrites `/etc/hosts`, sets `fs.inotify.max_user_watches=16777216` |
| `ca` | `ca_sync` — rsync mirror of the CA host's `/etc/srvctl/CA` (no-op on the CA host itself) |
| `haproxy` | Fires the `regenerate_certificates` sub-hook (certificates + Let's Encrypt), re-renders `/etc/haproxy/haproxy.cfg` and reloads |
| `named` | Rewrites `/var/named/srvctl.conf` and changed zone files, restarts and verifies BIND |
| `dns` | `dns_scan` — public-DNS scan of every container domain into the datastore |
| `opendkim` | Generates missing DKIM keys, rebuilds TrustedHosts/KeyTable/SigningTable, restarts opendkim |
| `postfix` | Rewrites and postmaps `/etc/postfix/relaydomains`, restarts postfix |
| `perdition` | Rewrites `/var/perdition/popmap.re`, restarts imap4s/imap4/pop3s |
| `saslauthd` | Restarts `saslauthd.service` |
| `ssh` | `ssh_config.d` drop-ins, host-key scan, known_hosts and user public-key distribution |
| `sshpiperd` | Re-ensures the read-only bindfs mount on `/var/sshpiper` |
| `nfs` | Re-mounts the cluster NFS shares over the OpenVPN mesh addresses |
| `static` | Creates missing per-container docroots under `/var/srvctl3/storage/static/` |
| `usersonhost` | `userscfg` — system accounts, passwords, ssh keys, client certificates, per-container bindfs mounts |
| `codepad` | Republishes user credential files into `/var/srvctl3/share/containers/<C>/users/<u>/` |

**With `rootfs`:** `cd /root`, then `run_hook regenerate_rootfs` — rebuilds the
container base images under `/var/srvctl3/rootfs` (`containers` and `codepad`
provide that hook).

**With `all-hosts`:** `regenerate_all_hosts` (`modules/containers/libs/regenlib.sh`)
runs the same regeneration on every host of the canonical
`/etc/srvctl/clusters.json` — every ordinary host in canonical file order,
across all clusters, then the global DNS publication primary and its replicas —
locally or over ssh as appropriate, after checking that each host agrees on the topology checksum.

**Cron job:** `/etc/cron.hourly/srvctl-regenerate.sh` (installed by the
`containers` module's `update-install-host` hook) runs
`srvctl regenerate '#cron.hourly'` every hour. That literal argument is matched
by the hooks: it additionally enforces container disk quotas
(`all_containers_quota_check`) and makes haproxy skip its reload.

### Utility Commands

| Command | Description |
|---------|-------------|
| `customize COMMAND` | Create/edit `$SC_HOME/srvctl-includes/<command>.sh`: back up an existing copy to `.srvctl/srvctl-includes.bak/`, otherwise seed a template, open `mcedit`, then beautify, shellcheck and rebuild completion data. Exit 23 when no name is given. Root only |
| `fix-owner` | **Inert.** The help promises a recursive chown to the parent directory's owner, but the single `chown` line in `modules/srvctl/commands/fix-owner.sh` is commented out, so the command does nothing at all. Root only |
| `fix-sshd` | `chown root:ssh_keys` and `chmod 600` on the three `/etc/ssh/ssh_host_*_key` files, then restarts `sshd.service`. Root only |
| `ls` | `find . -type f -exec ls -lt {} +` — recursive file listing, newest first |

---

## Web GUI

The `gui` module ships a web-based administration interface that **this
codebase never installs**. The entire body of
`modules/gui/hooks/update-install-host.sh` is wrapped in `if false`, so the
systemd unit, the TLS material in `/etc/srvctl-gui`, the npm globals and the
tcp/250 firewall rule are never written. The daemon only runs on hosts that
still carry srvctl2-era setup; v4 replaces it with cockpit.

`module-condition.sh` nevertheless reports `true` on every host (`false` only
inside a container), so `SC_USE_GUI` is true on every host — which keeps the one
live part of the module running.

**Live part — `libs/spec.sh`:** `make_commands_spec` is called from
`update-install` under `if $SC_USE_GUI` and writes
`/var/local/srvctl/commands.spec`, one record per command with four fields
joined by U+00D7 (`×`): `sourcepath×command×hint×syntax`. Command files whose
first ten lines contain `root_only` or `## interactive` are skipped.

**Dormant server (`server.js`, port 250):**
- HTTPS with `requestCert`/`rejectUnauthorized` against the usernet CA (`/etc/srvctl/CA/ca/usernet.crt.pem`); the client certificate CN is the srvctl username.
- Express + Socket.io, required from the global prefix `/usr/lib/node_modules/`.
- ssh2 for remote command execution using the user's internal `srvctl_id_ecdsa` key.
- Reads the datastore JSON files and `/var/local/srvctl/commands.spec` once, at startup.
- Terminal emulation via the vendored `hterm_all.js`; the `/wetty` static mount is dead, nothing installs that npm package.
- `SC_DATASTORE_DIR` and `SC_INSTALL_DIR` are hardcoded to `/var/srvctl3/datastore` and `/usr/local/share/srvctl`.

**Frontend (`modules/gui/srvctl-gui/`):** `index.html`, `index.js`, `index.css`,
`scripts.js`, `styles.css`, `wetty.html`, `wetty.js`, `hterm_all.js`.

**Dependencies:** express, node-pty, socket.io, ssh2 — plus angular,
angular-ui-bootstrap, angular-sanitize and bootstrap, served statically from
the global node_modules prefix.

---

## Branding

The `branding` module customizes web interfaces and error pages. It is enabled
exactly when the `containers` module is — its `module-condition.sh` sources that
module's condition.

**Configuration** (defaulted in `hooks/pre-init.sh`, then made readonly and
exported by `hooks/post-init.sh`):
- `SC_COMPANY` — Company name. Defaults to `$HOSTNAME`.
- `SC_COMPANY_DOMAIN` — Company domain. Defaults to `$HOSTNAME`.

**Generated content:**
- `setup_index_html <name> <dir>` (`libs/brandinglib.sh`) writes a dark placeholder `<dir>/index.html` with the inlined logo and `<name> @ $HOSTNAME`, and copies `favicon.ico` beside it. It silently does nothing when `<dir>` does not exist. Called by `containers` (add-ve, into `/srv/$C/rootfs/var/www/html`) and by `static` (regenerate).
- `hooks/update-install-host.sh` writes error pages for 400, 403, 404, 408, 414, 500, 501, 502, 503 and 504. Each code yields two files in `/var/www/html`: `<code>.html` for web servers and `<code>.http` — the same body prefixed with a raw HTTP/1.1 status line and headers — which haproxy serves byte-verbatim via `errorfile`. 404, 408, 414 and 501 are generated but not currently wired up in `haproxy.js`, which emits `errorfile` lines only for 400, 403, 500, 502, 503 and 504.

**Assets:** `logo.svg` and `favicon.ico`, both inlined/copied by the functions
above. `html/503.html` is an orphan — nothing in the tree references it.

---

## Password Generation

The `password` module generates pronounceable, memorable passwords. It is a
pure library module: its condition always prints `true`, so it is enabled
everywhere, containers included.

**Pattern:** Two words separated by a hyphen, 11-15 characters from
`[A-Za-z-]` (e.g. `Kelto-Ardu`). Each word opens with either an uppercase
vowel plus a consonant cluster, or an uppercase consonant plus vowel plus
consonant, and then adds vowel + cluster + vowel.

**Implementations:**
- Node.js — `get_password()` in `lib.js`, wrapped by the `get-password.js` CLI shim (which ignores its arguments).
- Pure bash — `get_password` in `libs/get-password.sh`, sourced into every srvctl shell.
- `new_password` (`libs/bashlib.sh`) is the bash wrapper around the Node implementation. It captures stderr into the value (`2>&1`), and on failure `exif` aborts the whole srvctl run with a misleading `SSH-ERROR` message.

**Usage:** `new_password` by domain certificate generation
(`certificates/libs/domaincertlib.sh`), by `usersonhost` and by
`usersonve/commands/add-user.sh`; `get_password` by the `mariadb` and
`wordpress` modules; `lib.js` directly by `usersonhost/main.js`.

Both implementations use non-cryptographic randomness (`$RANDOM` /
`Math.random()`) for roughly 39 bits of entropy, while the results become
long-lived database, user and TLS credentials — flagged `FIXME(v4)` in both
files.

---

## Development Tools

### push.sh — Commit and Push

`push.sh` sits in the project root and is **not** part of the srvctl command
set; it is the Codepad push button for the srvctl source tree. Optional
arguments are appended to the commit message. It does not build, back up,
beautify or generate README files.

1. `cd`s to its own directory (exit 7 on failure) and requires a `.git` there (exit 6).
2. Adds that directory to the caller's `git config --global safe.directory` once, so git's dubious-ownership guard does not block a tree owned by another user.
3. Warns when the current branch is not `master`.
4. Runs `shellcheck -x` over just the changed and untracked `.sh` files — informational, it never blocks the push. Exits 112 when shellcheck is not installed.
5. Exits 0 when `git status --porcelain` is empty (nothing to commit).
6. Increments the last field of the `version` file (`awk -F. -v OFS=. '{$NF++; print}'`) — only once there is something to commit.
7. Falls back to `$USER@$HOSTNAME` as the commit identity when git has none configured.
8. `git add -A .`, then commits with the new version (plus any arguments) as the message; exit 5 if the commit fails.
9. Pushes with `--set-upstream origin <branch>` when a remote exists. A failed push exits 4 and warns that the commit exists only locally; with no remote configured the commit stays local.

`encode.mjs` and `claude.sh`, documented here in earlier releases, were removed
in 4.0.0.6 (commit `ba8b0ab`).

---

## Configuration Reference

### System Directories

| Path | Purpose |
|------|---------|
| `/usr/local/share/srvctl/` | Installation directory |
| `/etc/srvctl/` | Static configuration (`clusters.json`, `.conf` files) |
| `/etc/srvctl/data/` | Non-topology configuration seeds such as branding and CA settings; each `*.conf` here is copied into `/etc/srvctl/` during `update-install` / `test-modules` |
| `/etc/srvctl/CA/` | Certificate authority files (default of `SC_ROOTCA_DIR`) |
| `/etc/srvctl/cert/` | Admin-installed certificates, one directory per domain (`cert/<domain>/`) |
| `/var/srvctl3/host/` | Generated per-host projection of the canonical topology (`host.conf`, `hosts.json`); never edit |
| `/var/srvctl3/cluster-config/` | Publication state (`cluster-config/publication`) and `retired-generation.sha256`, the receipt written when this host is retired from the cluster |
| `/var/srvctl3/datastore/` | Read-write data store (`SC_DATASTORE_RW_DIR`) |
| `/var/srvctl3/gluster/` | Read-only bind mounts of the local GlusterFS bricks; `gluster/srvctl-data` is the default `SC_DATASTORE_RO_DIR` |
| `/var/srvctl3/rootfs/` | Container rootfs templates |
| `/var/srvctl3/mounts/` | Container mounts |
| `/var/srvctl3/share/` | Shared data (per-container user dirs, common keys) |
| `/var/srvctl3/ssh/` | Host-side `known_hosts`, generated by `modules/ssh/ssh.js` (`make_host_keys`) and pointed at by the `UserKnownHostsFile` lines of the `/etc/ssh/ssh_config.d` drop-ins it writes. The separate `mkdir` at `modules/srvctl/commands/update-install.sh:93` is redundant — the ssh module creates the directory itself — and the stale comment beside it does not mean the directory is unused |
| `/var/srvctl3/storage/` | Static file storage — a plain local directory at this version; it is the `srvctl-storage` gluster volume only in the dormant gluster design |
| `/var/srvctl3/nfs/` | NFS mounts from cluster hosts |
| `/var/local/srvctl/` | Legacy module-state fallback, `commands.spec`, shell-completion word lists |
| `$SC_HOME/.srvctl/` | Per-user state (root included): `modules.conf` cache, `srvctl.log`, `srvctl-includes.bak/` |
| `/srv/` | Container root directories |
| `/var/haproxy/` | HAProxy certificates |
| `/var/perdition/` | Perdition popmap |
| `/var/opendkim/` | DKIM keys |
| `/var/named/srvctl/` | DNS zone files |
| `/var/acme/` | ACME challenge files |
| `/var/sshpiper/` | SSHPipeRD user mapping |
| `/var/dyndns/` | Dynamic DNS update files |
| `/glu/srvctl-data/brick` | GlusterFS brick for the `srvctl-data` volume (sensitive data) |
| `/glu/srvctl-storage/brick` | GlusterFS brick for the `srvctl-storage` volume (bulk storage) |

### Key Environment Variables

| Variable | Description |
|----------|-------------|
| `SRVCTL` | `srvctl-` plus the contents of the `version` file (e.g., `srvctl-4.0.0.8`) |
| `SC_INSTALL_DIR` | Installation directory |
| `SC_INSTALL_BIN` | Path to srvctl.sh |
| `SC_MODULES` | Space-separated module directory list — `/root/srvctl-includes/modules/*` first, then the installed `modules/*` |
| `SC_TTY` | Running in terminal (`true`/`false`) |
| `SC_STARTTIME` | Startup timestamp (ms) |
| `SC_USER` | Invoking user: `$SUDO_USER` when reached through sudo, otherwise `$USER` |
| `SC_UID0` | Effective uid is 0 (`true`/`false`) — not the same thing as `SC_USER == root` |
| `SC_HOME` | Home directory of `SC_USER` |
| `SC_LOG` | Log file path (`~/.srvctl/srvctl.log`) |
| `SC_HOSTNET` | Host's unique 10.x network ID. Documented as 16–255, but nothing validates it: `cluster-config.js` never inspects the value, and `containers/hooks/post-init.sh` silently defaults it to 250 when the projection has none |
| `SC_CLUSTERNAME` | Cluster name (defaults to `test_cluster` when unprojected) |
| `SC_HOSTNAME` | System hostname, as projected from the topology |
| `SC_CLUSTERS_SHA256` | Generation hash of `clusters.json`; `SC_HOSTS_SHA256` is the hash of this cluster's host map |
| `SC_HOST_IP` | Host's routable IP, from the `host_ip` key |
| `SC_COMPANY` | Company name |
| `SC_COMPANY_DOMAIN` | Company domain |
| `SC_ROOTCA_HOST` | Root CA host (defaults to `$HOSTNAME`) |
| `SC_ROOTCA_DIR` | Root CA directory (defaults to `/etc/srvctl/CA`) |
| `SC_ROOTCA_SUBJ` | Root CA certificate subject (defaults to `/C=HU/ST=Hungary/L=Budapest/O=SRVCTL-CA`) |
| `SC_ROOTFS_DIR` | Container rootfs templates directory (defaults to `/var/srvctl3/rootfs`) |
| `SC_MOUNTS_DIR` | Container mounts directory (defaults to `/var/srvctl3/mounts`) |
| `SC_DATASTORE_RO_DIR` | Read-only datastore (defaults to `/var/srvctl3/gluster/srvctl-data`) |
| `SC_DATASTORE_RW_DIR` | Read-write datastore (defaults to `/var/srvctl3/datastore`) |
| `SC_DATASTORE_DIR` | Whichever of the two `init_datastore` selected for this invocation |
| `SC_DATASTORE_SEED_DIR` | Fresh-install seed directory (defaults to `/etc/srvctl/data`) — what `grab_data` pulls and `publish_data` distributes, minus every `clusters*.json` |
| `SC_DATASTORE_RO_USE` | `true` while the store must be treated as read-only. Defaulted to `true` in `datastore/hooks/pre-init.sh` and cleared by `hooks/init.sh` wherever gluster is inactive; exported to `main.mjs` as the store's `readOnly` guard |
| `SC_ADMIN_CERT_DIR` | Admin-installed certificate root scanned for wildcards by `sync_haproxy_certificates` (defaults to `/etc/srvctl/cert`) |
| `SC_CLUSTER_CONFIG_LOCK_FILE` | Lock guarding reads and writes of the canonical topology and its projections (defaults to `/run/srvctl-cluster-config.lock`) |
| `SC_CLUSTER_PUBLICATION_LOCK_FILE` | Exclusive lock shared by `initialize_cluster_publication`, `retire_cluster_host` and `publish_data` (defaults to `/run/srvctl-cluster-publication.lock`) |
| `SC_CLUSTER_PUBLICATION_STATE_DIR` | Publication manifest and retirement receipts (defaults to `/var/srvctl3/cluster-config/publication`) |
| `SC_BACKUP_PATH` | Backup destination path (defaults to `/backup`) |
| `SC_BACKUP_HOST` | Remote backup host; backups stay local when unset or equal to `$HOSTNAME` |
| `SC_DNS_SERVER` | DNS server role; the `named` module is enabled only when this is exactly `master` or `slave` |
| `SC_OPENVPN_HOSTNET_SERVER` | OpenVPN hostnet server (defaults to `$HOSTNAME`) — assigned in `openvpn/hooks/pre-init.sh` but currently read by nothing |
| `SC_VIRT` | Output of `systemd-detect-virt -c`, computed locally inside each `module-condition.sh` rather than exported globally. `systemd-nspawn` and `lxc` mean "inside a container"; on bare metal the value is the literal `none`, never the empty string, so a `-z` test is always false. Other runtimes (docker, podman, wsl) are not recognised as containers |
| `SC_USE_<MODULE>` | Module enabled flag — the literal string `true` or `false` printed by `module-condition.sh` (e.g., `SC_USE_CONTAINERS`), cached in modules.conf and made readonly at init |
| `CMD` | Current command, lowercased; the `?` `+` `-` `!` shorthands are mapped to status/start/stop/restart |
| `ARG` | First argument (same shorthand mapping) |
| `ARGS` | All arguments |
| `DEBUG` | Debug mode flag, normally set in `/etc/srvctl/debug.conf` |
| `NOW` | Startup timestamp, `YYYY.MM.DD-HH:MM:SS` |

### Configuration Files

| File | Format | Purpose |
|------|--------|---------|
| `/etc/srvctl/clusters.json` | JSON | Sole canonical cluster topology; identical on every host |
| `/var/srvctl3/host/hosts.json` | JSON | Generated current-cluster projection; do not edit |
| `/var/srvctl3/host/host.conf` | Bash | Generated host-specific settings; do not edit |
| `/var/srvctl3/cluster-config/retired-generation.sha256` | Text | Exact-generation receipt written by `retire_cluster_config` (`modules/containers/lib/cluster-config.sh`) when `retire_cluster_host` decommissions this host, so an interrupted retirement can be retried safely. A later successful publication re-enrols the host and removes the marker |
| `/etc/srvctl/data/branding.conf` | Bash | Company name and domain |
| `/etc/srvctl/data/ca.conf` | Bash | CA host and subject |
| `/etc/srvctl/debug.conf` | Bash | Debug settings (`DEBUG=true`); sourced first thing in init.sh |
| `$SC_DATASTORE_RW_DIR/containers/<name>.json` | JSON | One container record per file — the authoritative v4 layout |
| `$SC_DATASTORE_RW_DIR/users/<name>.json` | JSON | One user record per file |
| `$SC_DATASTORE_RW_DIR/hosts/<name>.json` | JSON | One host record per file |
| `$SC_DATASTORE_RW_DIR/.per-entity` | marker | Written once migration succeeded. While it exists, v4 readers ignore the monolithic files completely, so deletes are honoured |
| `$SC_DATASTORE_RW_DIR/{containers,users,hosts}.json` | JSON | v3 monolithic store. Read only as a fallback *before* the marker exists, archived to `.monolithic-backup/` by the migration, and never written by v4 |
| `$SC_HOME/.srvctl/modules.conf` | Bash | Module enable/disable cache, per user and including root (`/root/.srvctl/modules.conf`). Keyed to the topology by a first line `export SC_MODULES_CLUSTERS_SHA256=<sha256>`; rebuilt when missing, when that generation differs, or on `update-install` / `test-modules` |
| `/var/local/srvctl/modules.conf` | Bash | Legacy module-state cache, kept as a fallback. Sourced only when its generation matches, and always *before* the file above, so anything hand-edited here is overridden a few lines later; `commonlib.sh:611` still carries the commented-out line that used to make it authoritative for root |
| `/var/local/srvctl/commands.spec` | Text | `×`-separated command list rebuilt by `make_commands_spec` (modules/gui/libs/spec.sh) on every `update-install`, read by the GUI server — which is itself dormant, nothing installs the daemon |

### Cluster Configuration Example

```json
{
  "My_cluster": {
    "t1.example.com": {
      "mac": "080027000001",
      "host_ip": "192.168.88.103",
      "gateway": "192.168.88.1",
      "prefix": "24",
      "dns1": "8.8.8.8",
      "dns2": "8.8.4.4",
      "hostnet": "78",
      "dns_server": "master",
      "dns_primary": true,
      "reverse_proxy": "haproxy"
    },
    "t2.example.com": {
      "mac": "080027000002",
      "host_ip": "192.168.88.104",
      "gateway": "192.168.88.1",
      "prefix": "24",
      "dns1": "8.8.8.8",
      "dns2": "8.8.4.4",
      "hostnet": "79",
      "dns_server": "slave",
      "reverse_proxy": "haproxy"
    }
  }
}
```

`dns_primary: true` pins the one DNS publication primary. It may be omitted
only when exactly one `dns_server: "master"` exists. Any additional legacy
masters and all slaves serve as transfer replicas of that canonical primary;
multiple masters without exactly one marker are an error, as is `dns_primary:
true` on a host that is not a `master`, or a cluster with no master at all.
The optional `dns_replication_source` and `dns_replication_acl_ip` keys are
validated as IP addresses when present.

Every scalar value (string, number or boolean) in a host record is projected
verbatim into `host.conf` as `SC_<KEY UPPERCASED>`; nested objects and arrays
are dropped. Only a few keys are read by anything:

| Key | Consumer |
|-----|----------|
| `host_ip` | `SC_HOST_IP` — DNS records, vncproxy bind address, cluster reachability |
| `hostnet` | `SC_HOSTNET` — container addresses `10.<hostnet>.<user_id>.<n>` and the OpenVPN mesh `10.15.<server hostnet>.<client hostnet>` |
| `dns1` | the networkd generator below, and `SC_DNS1` — the all-containers pingback check |
| `dns_server` | `SC_DNS_SERVER` — enables the `named` module when exactly `master` or `slave` |
| `dns_primary` | the primary election described above |
| `interface`, `gateway`, `prefix`, `dns2` | `networkd_configure_interface` (`modules/srvctl/libs/networkdlib.sh`), reached from the `pre-update-install-host` hook. It reads them back through the datastore (`get host $HOSTNAME <key>`, which overlays the canonical record), writes the NIC whose name equals `interface` as a static `/etc/systemd/network/<iface>.network`, and falls back to `DHCP=YES` when any of `interface`/`host_ip`/`gateway`/`prefix` is missing |
| `mac` / `mac_address`, `reverse_proxy` | nothing. They are still projected (`SC_MAC`, `SC_REVERSE_PROXY`) and serve as inventory notes — which is why either spelling of the MAC key is accepted, and why `reverse_proxy` takes any value: HAProxy is selected by the module condition, not by this key |

Typing is free-form: this example writes `"hostnet": "78"` while the
Installation example writes `"hostnet": 16`. Both work, because the projection
shell-quotes strings, numbers and booleans alike and the consumers compare
loosely. Values should still stay inside `[A-Za-z0-9._:/@+,=-]`: that is the
charset the v3 generator, which renders host.conf as unquoted shell
assignments, can emit without executing them. Publication itself does not
check this — only `prepare_cluster_rollback_to_legacy` does, through the
`v3safe` command of `modules/containers/lib/cluster-config-cli.js`, and it
refuses the whole rollback until every offending value is removed.

---

## Command Reference

Every command below is a script under `modules/<module>/commands/<name>.sh`, and
its first `## @@@` line is the authoritative syntax that `srvctl help` prints.
Availability depends on the owning module being enabled, so the host-side and
the container-side command sets differ. Two shipped commands are inert stubs and
are marked as such.

### Container Management

| Command | Description |
|---------|-------------|
| `srvctl add-ve NAME [TYPE]` | Create a container from a base image. TYPE defaults to `fedora` and is accepted only if `$SC_ROOTFS_DIR/TYPE/etc/os-release` already exists — run `ls /var/srvctl3/rootfs` for the types a given host has |
| `srvctl add-network-ve NAME BRIDGE` | Create a fedora container attached to an existing `br-BRIDGE`, with DHCP networking |
| `srvctl add-ve-user VE USERNAME` | Create a cluster user and give it the container (reseller/root) |
| `srvctl status [VE]` | With an argument, `systemctl status` of `srvctl-nspawn@VE`; without one, the cluster-wide table rendered by `containers/status.js` |
| `srvctl recreate-ve VE` | Back up, wipe and rebuild the rootfs, restoring user data as far as possible |
| `srvctl update-ve VE` | **Stub.** Stops the container's unit and then errors `Feature unimplemented`, leaving the container stopped (`containers/commands/update-ve.sh:39`) |
| `srvctl destroy-ve VE` | Permanently delete the container, its files and its datastore records |
| `srvctl remove-ve VE` | Back up the container (see Backup) and then delete it |
| `srvctl exec-all COMMAND` | Run one shell command in every running container (root only) |
| `srvctl map-port VE [udp] PORT DESCRIPTION` | Map a container TCP port — or a UDP port with the `udp` keyword — to the host. PORT must be 1–65535 |
| `srvctl regenerate [all-hosts\|rootfs]` | Without an argument, run the `regenerate` hook of every enabled module on this host. `all-hosts` does the same over ssh on every current-cluster host and every global DNS authority, in publication order. `rootfs` rebuilds the base images under `$SC_ROOTFS_DIR` |

**`regenerate` takes only `all-hosts` or `rootfs`.** There is no `all` argument.
`srvctl regenerate all` does not fail — it falls through to the plain
single-host regenerate (`containers/commands/regenerate.sh:37,50`), so an
operator who types it has *not* regenerated the cluster. Cron additionally calls
`srvctl regenerate '#cron.hourly'`, which is the literal that triggers the
hourly container quota check.

**`regenerate rootfs` builds only `fedora`** (plus `codepad` when that module is
enabled). Builders for debian, ubuntu, arch and the gnome/mail variants exist in
`containers/libs/mkrootfs_*.sh`, but their calls are commented out in
`containers/hooks/regenerate_rootfs.sh:15-19` and build nothing unless an admin
re-enables them.

### Direct Container Interaction

`modules/containers/command.sh` is the module *default* command: it is reached
only after no named command matched. It accepts either word order —
`srvctl VE OP` or `srvctl OP VE` — and maps the operation onto `machinectl`,
provided `/srv/VE` exists and the machine is running. All of these operations
are owner-scoped (`owner_only container`).

| Command | Description |
|---------|-------------|
| `srvctl <container> shell` | Open an interactive `machinectl shell` |
| `srvctl <container> login` | `machinectl login` — a getty session |
| `srvctl <container> status` | `machinectl status` |
| `srvctl <container> show` | `machinectl show` — container properties |
| `srvctl <container> reboot` | Reboot the container |
| `srvctl <container> poweroff` | Power off the container |
| `srvctl <container> kill` | Kill the container with all its processes |

`start`, `stop` and `restart` are *not* handled here. They fall through to the
generic systemd shorthand in `modules/srvctl/command.sh`, whose `adjust-service`
hook rewrites the container name to the `srvctl-nspawn@VE` unit. Because nspawn
units cannot be restarted (systemd#2809), `restart` is performed as stop + start.
The same path also accepts `srvctl all-containers <op>` (root only), which
applies the operation to every container.

### Shorthand Commands

`srvctl.sh` rewrites these operators before dispatch, in **both** the command
and the argument position, so `srvctl ? www.example.com` and
`srvctl www.example.com ?` are equivalent.

| Shorthand | Command |
|-----------|---------|
| `?` | `status` |
| `+` | `start` |
| `-` | `stop` |
| `!` | `restart` |

They apply to any systemd unit as well as to containers: `srvctl httpd !`
restarts and enables `httpd.service`, `+` starts and enables, and `-` stops the
unit — it does *not* disable it: `service_action` runs `systemctl disable` only
for the spelled-out `disable` operation. Mutating an arbitrary *host* service
through this shorthand is
root-only; `status` and `--user` units are not gated.

### User Management

| Command | Description |
|---------|-------------|
| `srvctl add-user USERNAME` | On a host: create the user in the cluster datastore and on the system (reseller/root). Inside a container the identically named `usersonve` command creates or updates the container-local account, its password and its home structure |
| `srvctl add-reseller USERNAME` | Add a user as reseller of the host cluster (root only) |
| `srvctl add-ve-user VE USERNAME` | Add a cluster user for a container (reseller/root) |
| `srvctl add-publickey [KEY\|FILE]` | Store an SSH public key for the calling user; with no argument it opens `mcedit` so a key can be pasted in |
| `srvctl add-vnc-user VE USERNAME` | Register a VNC user for a container, regenerate the vncproxy routing and restart the service. This is the only time the derived VNC password is displayed |
| `srvctl change-user VE USERNAME` | **Stub.** Intended to move a container to a different owner (which implies a new IP and a restart); it validates its arguments and then errors `not implemented` (`usersonhost/commands/change-user.sh`) |

### Application Installation

Host side:

| Command | Description |
|---------|-------------|
| `srvctl add-codepad NAME` | **Deprecated**, kept for compatibility: create a container from the `codepad` template rootfs. The canonical path is `add-ve NAME codepad`; only `add-codepad` enforces the `*-devel` name rule that is the legacy opt-in for codepad port 9000 (9000, 9001 and 9002 are all proxied wherever the rootfs has `/var/codepad/codepad4`) |

Inside a container, root only:

| Command | Description |
|---------|-------------|
| `srvctl install-wordpress` | Install WordPress and its dependencies |
| `srvctl install-odoo` | Install the Odoo 14 Community ERP/CRM stack. Upstream OCB 14.0 is end-of-life and its pinned requirements no longer build against current Fedora Python, so this fails on current images (`odoo/commands/install-odoo.sh:236`) |
| `srvctl vnc-desktop [DESKTOP]` | Create the appliance user `x` with a VNC virtual desktop:0 — gnome, ratpoison, xfce, i3, mate, … |
| `srvctl install-crossover` | Add CrossOver/Wine to the `vnc-desktop` appliance user |
| `srvctl install-qlcplus` | Add QLC+ (DMX over Art-Net) to the `vnc-desktop` appliance user |
| `srvctl add-zerotier NETWORKID` | Install ZeroTier inside the container and join NETWORKID |

### Proxy and Redirects

| Command | Description |
|---------|-------------|
| `srvctl http-redirect VE [none\|https\|URL]` | Place an HTTP redirect for the container in the proxy configuration. IPv4 only, default port. No argument, or `none`, removes the redirect |
| `srvctl https-redirect VE [none\|http\|URL]` | The same for HTTPS traffic |
| `srvctl override-in-address VE [none\|IP]` | Temporarily override the container's `IN A` record in the named zone file; `none` restores it |

### System Administration

| Command | Description |
|---------|-------------|
| `srvctl update-install HOSTNAME` | Run the install/update script. On a host this installs or updates the container farm and the HOSTNAME argument is required — without it the command stops after the dnf update. Inside a container the argument is ignored (root only) |
| `srvctl diagnose` | First-aid diagnostics: srvctl version and variables, uptime, kernel, boot config, inactive srvctl services, recent postfix fatal errors, firewall zones |
| `srvctl version` | Query the package manager for the versions of the packages srvctl cares about |
| `srvctl customize COMMAND` | Create or edit a custom command in `~/srvctl-includes` (root only) |
| `srvctl fix-owner` | **Stub.** The help promises a recursive `chown` of the current directory to its parent's owner, but the only `chown` line is commented out, so the command does nothing (`srvctl/commands/fix-owner.sh:15`). Root only |
| `srvctl fix-sshd` | Restore ownership `root:ssh_keys` and mode 600 on the sshd key files (root only) |
| `srvctl ls` | Recursive file listing of the current directory, newest first |
| `srvctl exec-function NAME [ARGS]` | Call an internal srvctl shell function directly. Not a command file: a hard-coded first-precedence branch in `run_command` (`commonlib.sh:132`), restricted to genuine root — `SC_USER=root` **and** uid 0 |

### Datastore Operations

These are not command files. `run_command` dispatches the verbs by name
(`commonlib.sh:146-158`) onto the bash wrappers in
`modules/datastore/libs/bashlib.sh`, each of which spawns
`modules/datastore/main.mjs`. Reads (`get`, `out`) are open to any caller;
the mutating verbs (`new`, `put`, `cfg`, `del`, `add`) require genuine root and
at least one argument. `new`, `put` and `del` git-commit the JSON change through
`datastore_push`.

| Command | Description |
|---------|-------------|
| `srvctl get DAT ARG [FIELD]` | Print a value. Exit 0 with the value, exit 100 when an optional value is not defined, any other code on error |
| `srvctl put DAT ARG FIELD [VALUE]` | Set a field; omitting VALUE deletes it. `true`/`false` are stored as booleans, everything else as a string |
| `srvctl new DAT ARG [TYPE] [BRIDGE]` | Create a record — `container`, `user`, `reseller`, … |
| `srvctl del DAT ARG` | Delete a record |
| `srvctl out DAT ARG [json]` | Dump a record as sourceable shell variables, or as JSON |
| `srvctl cfg DAT ARG OPERATION [ARGS]` | Run an internal mutating operation, e.g. `cfg container VE update_ip` |
| `srvctl add DAT ARG FIELD VALUE` | Append to an array field, e.g. `add container VE user alice` |

### Mail Administration

| Command | Description |
|---------|-------------|
| `srvctl testsaslauthd user@ve` | End-to-end SMTP AUTH check for one container mail user; the password is read from the container home and filled in automatically |
| `srvctl fix-saslauthd` | Restart `saslauthd`. A stop-gap, described by its own help as temporary |

### Backup

| Command | Description |
|---------|-------------|
| `srvctl backup-ve VE` | Write `container.json` and the package lists into `/srv/VE`, then rsync the whole tree to `$SC_BACKUP_PATH/srvctl-containers/VE/$NOW` — by default `/backup/srvctl-containers/...` — or onto `$SC_BACKUP_HOST` over ssh when that names another machine. A failed rsync aborts the command |

The same `backup_ve` function (`containers/libs/backupcontainerlib.sh`) is also
called by `remove-ve` and `recreate-ve`, so both take a full copy before they
destroy anything.

**Inert:** `modules/backup/libs/7zlib.sh` still defines
`local_container_7z_backup`, the older 7z archive flavour writing to
`$BACKUP_PATH/$HOSTNAME/VE`. It has no caller in the tree, and its body begins
with a bare `exit` (`7zlib.sh:51`) that terminates the whole srvctl process with
status 0 without making a backup. The multi-line help of `remove-ve` still
describes that obsolete "7z archive in the user's home/.srvctl" behaviour; the
code does not do it.

---

## Inter-Module Dependencies

The dependency the code actually encodes is **activation**: a module's
`module-condition.sh` sources another module's condition to decide whether it is
enabled. The tree below is that graph and covers all 37 shipped modules.
`Wildcards` and `Error Pages` are not modules — wildcard certificates live in
`certificates/libs/wildcardcertlib.sh`, the error pages in `modules/branding/html/`.

```
always enabled (module-condition.sh is "echo true")
    backup, backupdb, ntp, password, srvctl, ssh

own condition
    firewalld    true inside a container; on a host when listed in hosts.json,
                 and on the `update-install <host>` bootstrap path
    gluster      never: the "all checks passed" branch of module-condition.sh is
                 `echo false`, with `#echo true` kept commented out beneath it
    gui          host only (false inside a container)
    named        only when SC_DNS_SERVER is 'master' or 'slave'

containers (host side: not inside a container, topology known)
    |
    +-- branding, certificates, datastore, default, dns, ftp, haproxy,
    |   letsencrypt, nfs, opendkim, perdition, postfix, saslauthd,
    |   sshpiperd, static, usersonhost, vncproxy
    +-- haproxy --- mozilla
    +-- ca         true outright when /etc/openvpn exists, else via containers
    +-- openvpn    true outright when /etc/openvpn exists, else via containers
    +-- codepad    false inside a container or on a mail.* host, else via containers

ve (inside a systemd-nspawn or lxc container)
    |
    +-- usersonve
    +-- mariadb    true outright when mariadb.service is active, else via ve
    +-- odoo       false on a mail.* container, else via ve
    +-- wordpress  false on a mail.* container, else via ve
```

**Edge legend:** an indented child (or `A --- B`) means *B's*
`module-condition.sh` sources *A's*, so B can only be enabled where A is. It does
**not** mean that B calls A.

Runtime coupling is a separate graph, and part of it runs the other way round:

| Consumer | Provider | Mechanism |
|----------|----------|-----------|
| `haproxy` | `certificates`, `letsencrypt` | `haproxy/hooks/regenerate.sh:15` calls `run_hook regenerate_certificates`; both modules implement that hook |
| `postfix`, `perdition`, `gui` | `certificates` | `certificates/libs/servicecertlib.sh` installs the service PEM into `/etc/postfix`, perdition and so on |
| `openvpn`, `certificates` | `ca` | host and domain certificates are signed by the cluster CA |
| `postfix`, `perdition` | `saslauthd` | SMTP and IMAP authentication is delegated to `saslauthd` (`MECH=rimap`) |
| `postfix` | `opendkim` | outgoing mail is signed through the OpenDKIM milter |
| `datastore` | `gluster` | `datastore/hooks/init.sh` mounts the `srvctl-data` volume onto `$SC_DATASTORE_RW_DIR` when `SC_USE_GLUSTER` is true; with gluster inert the hook simply clears `SC_DATASTORE_RO_USE` and the store uses the local read-write directory — read-only mode survives only a *failed* gluster mount |
| `sshpiperd` | `datastore` | `mount_sshpiper` bind-mounts a read-only view of the datastore users directory at `/var/sshpiper`, where the daemon reads each user's `*.pub` |
| `dns` | `named` | `dns/dns-scan.js` resolves every container domain against 8.8.8.8 and writes the result into `containers.json`; `named` is what publishes those zones on master/slave hosts |

---

## Known Issues and Workarounds

These come from `documentation/hints.txt` — the file was called `TODO.txt` until
4.0.0.6 (commit `ba8b0ab`), which moved it unchanged. The `TODO.md` in the
repository root is a different document: the prioritised findings of the
2026-07-16 datastore audit.

- **pthread_create** — containers can fail to start threads with "Resource temporarily unavailable"; a kernel/cgroup limit, see the link in `hints.txt`.
- **Network unreachable** — restart `systemd-networkd` on the host and in the affected container. The automatic restart is deliberately left commented out in `containers/execstartpre.sh:47-48` (systemd#13530).
- **Container restart failure** — nspawn units cannot be restarted (systemd#2809). srvctl works around this by turning `restart` into stop + start in `containers/hooks/adjust-service.sh`. `hints.txt` also suggests dropping `--keep-unit`, which is still present in the shipped unit template (`containers/libs/systemlib.sh:188`).
- **Dovecot key size** — an upstream Fedora bug with certain key sizes (RHBZ 1882939). Worked around at image build time: `containers/libs/mkrootfs_fedora.sh:91` rewrites `default_bits = 1024` to `default_bits = 4096` in the new rootfs' `/etc/pki/dovecot/dovecot-openssl.cnf`. Container images built before that change keep the 1024-bit file.
- **Firewall bridges** — bridge interfaces must be in the trusted zone. The default per-container bridge is trusted automatically by the generated `/srv/VE/ethernet.sh` (`datastore/lib.js:434,441`, run from `execstartpost.sh`), and `add-network-ve` trusts `host0` inside the new container. `add-zerotier` does the same for the `zt-*` interface it joins (`modules/usersonve/commands/add-zerotier.sh`). A custom `br-NAME` bridge on the *host* still has to be put in the trusted zone by hand.
- **Remote backups are broken** — with `SC_BACKUP_HOST` set to another machine, the remote `mkdir` is handed to `run` as a single word, so it never executes and the following rsync aborts (`containers/libs/backupcontainerlib.sh:52-53`). Local backups are unaffected.

**No longer an issue:** the `saslauthd` threading lock-up needs no manual
workaround — `-n 0` (fork one process per connection) ships in
`modules/saslauthd/conf/saslauthd.conf:13`. `fix-saslauthd` remains available for
restarting a wedged daemon.
