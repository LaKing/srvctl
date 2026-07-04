# srvctl v3 — Complete Documentation

srvctl is a container farm manager for microsite hosting on Fedora servers. It uses systemd-nspawn containers and is written in bash and JavaScript/Node.js. The CLI is invoked as `srvctl` or `sc`. srvctl is deployed across many production servers.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Installation](#installation)
3. [Core System](#core-system)
   - [Entry Point — srvctl.sh](#entry-point--srvctlsh)
   - [Initialization — init.sh](#initialization--initsh)
   - [Common Library — commonlib.sh](#common-library--commonlibsh)
   - [Utility Library — lablib.sh](#utility-library--lablibsh)
4. [Module System](#module-system)
5. [Command Execution](#command-execution)
6. [Hook System](#hook-system)
7. [Datastore](#datastore)
8. [Containers](#containers)
   - [Container Lifecycle](#container-lifecycle)
   - [Rootfs Creation](#rootfs-creation)
   - [Systemd Service Template](#systemd-service-template)
   - [Container Networking](#container-networking)
   - [Resource Limits](#resource-limits)
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
17. [Backup](#backup)
    - [Filesystem Backup](#filesystem-backup)
    - [Container Backup](#container-backup)
    - [Database Backup](#database-backup)
18. [System Administration](#system-administration)
    - [Diagnostics](#diagnostics)
    - [Version Management](#version-management)
    - [Update and Installation](#update-and-installation)
    - [Regeneration](#regeneration)
19. [Web GUI](#web-gui)
20. [Branding](#branding)
21. [Password Generation](#password-generation)
22. [Development Tools](#development-tools)
23. [Configuration Reference](#configuration-reference)
24. [Command Reference](#command-reference)

---

## Architecture Overview

srvctl is a modular, plugin-based system that manages a cluster of Fedora servers running systemd-nspawn containers. Each container hosts a microsite or service.

The system consists of:

- **A main CLI dispatcher** (`srvctl.sh`) that parses commands and delegates to modules.
- **37 modules** providing commands, hooks, and libraries for specific subsystems (containers, networking, certificates, mail, etc.).
- **A JSON-based datastore** managing configuration for containers, users, hosts, and clusters.
- **A hook system** that lets modules extend and intercept lifecycle events.
- **A cluster architecture** where multiple servers share data via GlusterFS and communicate over OpenVPN.

The technology stack:

| Layer | Technology |
|-------|-----------|
| Host OS | Fedora Server |
| Containers | systemd-nspawn |
| Scripting | Bash (primary), Node.js (data processing, config generation) |
| Data | JSON files, bash-sourceable `.conf` files |
| Networking | systemd-networkd, OpenVPN, firewalld |
| Reverse proxy | HAProxy |
| Mail | Postfix, Perdition, OpenDKIM, saslauthd |
| DNS | BIND (named) |
| Storage | GlusterFS, NFS |
| Certificates | OpenSSL (internal CA), Let's Encrypt (public) |

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

### Installation Steps

```bash
dnf -y install git
cd /usr/local/share
git clone https://github.com/LaKing/srvctl.git && bash srvctl/srvctl.sh
```

This creates symlinks at `/bin/sc` and `/bin/srvctl`.

### Initial Configuration

Copy example configuration and customize:

```bash
cp -R /usr/local/share/srvctl/example-conf/data /etc/srvctl
```

Edit the following files:

- `/etc/srvctl/data/clusters.json` — Define cluster hosts with MAC, IP, hostnet, gateway, DNS server role.
- `/etc/srvctl/data/branding.conf` — Set `SC_COMPANY` and `SC_COMPANY_DOMAIN`.
- `/etc/srvctl/data/ca.conf` — Set `SC_ROOTCA_HOST` and `SC_ROOTCA_SUBJ`.

Then run the full installation:

```bash
srvctl update-install
```

### Hostname and DNS

Setting a correct hostname is mandatory. Correct forward and reverse DNS entries and NTP synchronization are essential. Users and UID/GID numbers must be consistent across clustered servers — do not create users outside of srvctl.

---

## Core System

### Entry Point — srvctl.sh

`srvctl.sh` is the main executable. It:

1. Detects whether it is running in a TTY or programmatic context (`SC_TTY`).
2. Sets readonly constants: `SC_INSTALL_BIN`, `SC_INSTALL_DIR`, `SRVCTL` (version string).
3. Discovers modules from `/root/srvctl-includes/modules/` and `$SC_INSTALL_DIR/modules/`.
4. Maps shorthand commands: `?` → status, `+` → start, `-` → stop, `!` → restart.
5. Parses command-line arguments into `CMD`, `ARG`, `OPA`, `ARGS`, `OPAS`.
6. Sources `init.sh` for initialization.
7. Calls `run_command()` to dispatch the command.

**Key variables set:**

| Variable | Description |
|----------|-------------|
| `SC_TTY` | Boolean — running in terminal or program context |
| `HOSTNAME` | System hostname (readonly) |
| `DEBUG` | Debug mode flag |
| `SC_STARTTIME` | Millisecond timestamp for timing |
| `SC_INSTALL_BIN` | Absolute path to srvctl.sh |
| `SC_INSTALL_DIR` | Installation directory |
| `SC_MODULES` | Space-separated list of module directories |
| `SC_COMMAND_ARGUMENTS` | Original command-line arguments |
| `SRVCTL` | Version string, e.g. `srvctl-3.2.5.9` |
| `CMD` | Current command (lowercased) |
| `ARG` | First argument |
| `ARGS` | All arguments |

### Initialization — init.sh

`init.sh` performs comprehensive setup:

1. Sources debug config from `/etc/srvctl/debug.conf` (if exists).
2. Creates `/etc/srvctl` and `/var/local/srvctl` directories (as root).
3. Creates symlinks for `sc` and `srvctl` in `/bin/` (if missing).
4. Sets up bash completion symlink.
5. Processes configuration files from `/etc/srvctl/data/` and `/etc/srvctl/*.conf`.
6. Sources `/etc/os-release` for OS detection.
7. Determines the actual user (handles sudo scenarios via `SUDO_USER`).
8. Logs command execution to `~/.srvctl/srvctl.log` and `/var/log/srvctl-root.log` (root).
9. Calls `test_srvctl_modules()` to discover and configure modules.
10. Runs hook chain: `pre-init` → `pre-init-$CMD` → `init` → `post-init` → `post-init-$CMD`.
11. Loads libraries via `load_libs()`.

**Key variables set:**

| Variable | Description |
|----------|-------------|
| `SC_LOG` | Log file path `~/.srvctl/srvctl.log` |
| `NOW` | Timestamp `YYYY.mm.dd-HH:MM:SS` |
| `SC_USER` | Current user (or sudoer) |
| `SC_UID0` | Boolean — running as root |
| `SC_HOME` | Home directory of `SC_USER` |

### Common Library — commonlib.sh

Provides core functions used throughout the system.

**Command documentation markers:**

| Marker | Purpose |
|--------|---------|
| `## @@@` | Optional command syntax line |
| `## @en` | Mandatory single-line English hint |
| `## &en` | Mandatory multi-line English help (repeatable) |
| `## &&&` | Optional dynamically-executed help content |
| `## @hu` | Optional Hungarian translation hint |

**Functions:**

| Function | Description |
|----------|-------------|
| `hint(cmd, hint, file)` | Formats and prints a command hint |
| `title(string)` | Prints a colored section header |
| `load_libs()` | Sources all `libs/*.sh` files from enabled modules |
| `run_hook(hook)` | Executes hook scripts from all enabled modules matching the hook name |
| `run_hooks(action)` | Calls `pre-$action`, `$action`, `post-$action` hooks |
| `run_command()` | Main command dispatcher (see [Command Execution](#command-execution)) |
| `hint_on_file(file)` | Parses a command file for hint metadata |
| `hint_commands()` | Prints all available commands |
| `help_on_file(file)` | Prints detailed help for a command |
| `help_commands()` | Prints help for all or a specific command |
| `test_srvctl_modules()` | Discovers modules and caches configuration |
| `set_permissions()` | Sets proper file permissions on srvctl directories |

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
| `dbg(message)` | Short debug message (when `DEBUG=true`, `SC_TTY=true`) |
| `debug(message)` | Timestamped debug message with elapsed milliseconds |
| `trace(message)` | Detailed stack trace and variable inspection |
| `err(message)` | Error message to stderr and log |

**Execution functions:**

| Function | Description |
|----------|-------------|
| `run(command...)` | Execute command with visual feedback (user@host, directory, prompt) |
| `nur(command...)` | Print command without executing (dry-run) |
| `exif(message)` | Exit if the previous command failed |
| `eyif(message)` | Warn (but don't exit) if the previous command failed |
| `exit_0()` | Clean exit with success message |

**File manipulation:**

| Function | Description |
|----------|-------------|
| `sed_file(file, old, new)` | Replace a line in a file using sed |
| `add_conf(file, content)` | Append content to a file if not already present |

---

## Module System

srvctl uses a plugin-based module architecture. There are 37 modules, each living under `modules/<name>/`.

### Module Structure

```
modules/<name>/
├── module-condition.sh     # Determines if module is active (returns true/false)
├── command.sh              # Default command handler for this module
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
│   ├── version.sh
│   └── ...
├── libs/                   # Library functions (sourced when module enabled)
│   └── *.sh
├── conf/                   # Configuration files and templates
├── apps/                   # Standalone applications (Node.js)
└── *.js                    # Module-specific Node.js scripts
```

### Module Discovery

At startup, `test_srvctl_modules()` iterates all module directories, sources each `module-condition.sh`, and records whether the module is active. Results are cached in:

- `/var/local/srvctl/modules.conf` (root)
- `~/.srvctl/modules.conf` (per-user)

Each module gets a variable `SC_USE_<MODULE_NAME_UPPERCASE>` set to `true` or `false`.

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
| `gluster` | GlusterFS distributed storage |
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

---

## Command Execution

When a user runs `srvctl <command> [args...]`, `run_command()` dispatches through this resolution order:

1. **Direct function execution** — If `CMD` is `exec-function` (root only), execute the named function directly.
2. **Datastore commands** — Commands `new`, `get`, `put`, `out`, `cfg`, `del`, `add` route to corresponding datastore functions.
3. **Root custom commands** — `/root/srvctl-includes/$CMD.sh`
4. **Module commands** — `$SC_MODULES/*/commands/$CMD.sh` (first match wins)
5. **User custom commands** — `$SC_HOME/srvctl-includes/$CMD.sh` (non-root only)
6. **Module default handlers** — `$SC_MODULES/*/command.sh` (each module can claim unmatched commands)

If no handler matches, the command fails with exit code 250 and help is shown.

### Command File Format

Each command script uses structured comments for the help system:

```bash
#!/bin/bash
## @@@ add-ve CONTAINER [TYPE]
## @en Add a new virtual environment container
## &en Creates a new container under the given domain name.
## &en Optional TYPE parameter sets the base rootfs (default: fedora).
## @hu Új virtuális környezet hozzáadása

## Only root can run this
root_only

## Require a container name argument
argument container-name

## Command implementation follows...
```

### Authorization Guards

Commands use these functions to restrict access:

| Guard | Effect |
|-------|--------|
| `root_only` | Only root can run this command |
| `reseller_only` | Only resellers or root |
| `hs_only` | Only on the host (not inside a container) |
| `ve_only` | Only inside a container |
| `authorize` | Check container ownership or root |
| `argument <name>` | Require an argument is provided |
| `sudomize` | Elevate to root if needed |

---

## Hook System

Hooks allow modules to extend and intercept lifecycle events. The `run_hook(name)` function iterates all enabled modules and sources `hooks/<name>.sh` from each.

The `run_hooks(action)` convenience function runs: `pre-<action>`, `<action>`, `post-<action>`.

### Standard Hooks

| Hook | When It Runs |
|------|-------------|
| `pre-init` | Before initialization |
| `init` | During initialization |
| `post-init` | After initialization |
| `pre-init-$CMD` | Before init, command-specific |
| `post-init-$CMD` | After init, command-specific |
| `regenerate` | During configuration regeneration |
| `regenerate_rootfs` | When rebuilding base container images |
| `update-install-host` | During `srvctl update-install` on host |
| `update-install-ve` | During `srvctl update-install` in container |
| `pre-update-install-host` | Before host update-install |
| `adjust-service` | When intercepting systemctl operations on containers |
| `diagnose` | During `srvctl diagnose` |
| `firewalld` | When configuring firewall rules |
| `version` | During `srvctl version` |
| `add-ve` | After adding a new container |
| `add_ve_<TYPE>` | After adding a container of a specific type |
| `mkrootfs_fedora` | During Fedora rootfs creation |
| `mkrootfs_debian` | During Debian rootfs creation |

---

## Datastore

The datastore module provides a JSON-based configuration store for the entire srvctl system. It stores information about containers, users, hosts, resellers, and clusters.

### Data Files

| File | Location | Content |
|------|----------|---------|
| Containers | `$SC_DATASTORE_RW_DIR/containers.json` | All container definitions |
| Users | `$SC_DATASTORE_RW_DIR/users.json` | All user definitions |
| Hosts | `/etc/srvctl/hosts.json` | Cluster host definitions |
| Clusters | `/etc/srvctl/clusters.json` | Cluster topology |

### Datastore Commands

These are first-class srvctl commands:

| Command | Usage | Description |
|---------|-------|-------------|
| `get` | `srvctl get container <name> <field>` | Retrieve a value |
| `put` | `srvctl put container <name> <field> <value>` | Set a value |
| `new` | `srvctl new container <name>` | Create a new entry |
| `del` | `srvctl del container <name>` | Delete an entry |
| `out` | `srvctl out container <name>` | Output in env-var or JSON format |
| `cfg` | `srvctl cfg container <name> <operation>` | Configuration operations |
| `add` | `srvctl add container <name> <field> <value>` | Add to collections |

Supported object types: `container`, `user`, `host`, `cluster`.

### Container Data Schema

Each container entry in `containers.json` has:

| Field | Description |
|-------|-------------|
| `user` | Owning username |
| `ip` | Container IP address |
| `type` | Base rootfs type (fedora, debian, ubuntu, arch) |
| `creation_time` | When the container was created |
| `br` | Bridge name |
| `bridge` | Custom bridge configuration |
| `gateway` | Gateway IP |
| `interface` | Network interface |
| `http_port` | HTTP port (default 80) |
| `https_port` | HTTPS port (default 443) |
| `quota` | Disk quota in bytes (default 250000000 / 250 MB) |
| `mapped_ports` | Array of port mappings: `{proto, host_port, container_port, comment}` |
| `users` | Array of usernames with access |
| `vncusers` | Array of VNC users |
| `aliases` | Domain aliases |
| `altnames` | Alternative domain names |
| `mx` | Whether container has MX records |
| `use_gsuite` | Whether using Google Suite |
| `is_mail` | Whether this is a mail container |
| `dns` | DNS scan results per domain |

### User Data Schema

Each user entry in `users.json` has:

| Field | Description |
|-------|-------------|
| `reseller_id` | Reseller group ID |
| `user_id` | Unique user ID |
| `uid` | System UID (1000+) |
| `name` | Display name |
| `reseller` | Parent reseller username |
| `added_by_username` | Who created this user |
| `added_on_datestamp` | Creation date |

### IP Address Calculation

Container IPs are computed from the user model:

```
10.<hostnet>.<user_id>.<container_offset>
```

Where `hostnet` is the host's unique ID (16–255), `user_id` is the user's sequential ID, and `container_offset` is assigned sequentially per user.

### Datastore Synchronization

- `publish_data()` — Rsync the datastore to all cluster hosts.
- `grab_data()` — Rsync the datastore from a specific host.
- Git-based version control tracks changes (`gitlib.sh`).

### Datastore HTTP Server

The datastore module runs an HTTP server on port 1030:

- `GET /.well-known/srvctl/datastore/containers.json` — Serves the containers JSON.
- `GET /.well-known/pki-validation/*` — Serves domain validation files.

### Key Node.js Functions (lib.js)

The datastore `lib.js` exports 50+ functions for data access and configuration generation:

**Container functions:** `container_uid`, `container_br`, `container_gw`, `container_interface`, `container_host`, `container_host_ip`, `container_user`, `container_reseller`, `container_http_port`, `container_https_port`, `container_quota`, `container_nspawn`, `container_ethernet`, `container_ethernet_network`, `container_hosts`, `container_resolv_conf`, `container_firewall_commands`, `container_domains`, `container_mx`, `container_useruids`, `container_add_mapped_port`, `container_update_ip`, `container_nspawn_network_mapped_ports`, `container_br_netdev`, `container_br_network`.

**Cluster functions:** `cluster_etc_hosts`, `cluster_postfix_relaydomains`, `cluster_host_keys`, `cluster_user_list`, `cluster_container_list`, `cluster_host_list`, `cluster_host_ip_list`.

**User functions:** `user_uid`, `user_container_list`, `new_user`, `new_reseller`.

---

## Containers

The containers module is the largest and most central module, managing the full lifecycle of systemd-nspawn containers.

### Container Lifecycle

#### Creation (`srvctl add-ve <name> [type]`)

1. Validate that the rootfs template exists in `$SC_ROOTFS_DIR/<type>`.
2. Check that the container does not already exist.
3. Create a database entry via the datastore (`new container`).
4. Run the `add-ve` hook across all modules.
5. Run the distro-specific hook `add_ve_<type>`.
6. Create configuration files in `/srv/<container>/`.
7. Copy the rootfs from the template directory.
8. Generate and install a self-signed SSL certificate.
9. Create a default `index.html`.
10. Configure Postfix for outgoing mail relay.
11. Copy `resolved.conf` for DNS.
12. Enable `httpd.service` inside the container.
13. Enable and start `srvctl-nspawn@<container>.service`.

#### Status (`srvctl status [container]`)

- With a container argument: shows `systemctl status srvctl-nspawn@<container>.service`.
- Without argument: calls the Node.js `containers_status` script for an overview of all containers.

#### Backup (`srvctl backup-ve <container>`)

1. Export container metadata (JSON) from the datastore.
2. Save package lists (`dnf list installed`, `rpm -qa`) for Fedora containers.
3. Rsync `/srv/<container>` to the backup path with a timestamp.
4. Supports remote backup hosts via SSH.

#### Recreation (`srvctl recreate-ve <container>`)

1. Backup MongoDB data if present (mongodump).
2. Stop the container.
3. Create a full backup.
4. Move old rootfs to `tmp_rootfs`.
5. Create a fresh rootfs from template.
6. Selectively restore data:
   - WordPress: `wp-content`, `wp-config.php`, MySQL data.
   - MongoDB: dump and restore.
   - Systemd services, `/srv`, `/home`, `/root`.
7. Fix UIDs/GIDs via `restore_uids`.
8. Run post-install scripts.
9. Start the container.

#### Destruction (`srvctl destroy-ve <container>`)

1. Stop the systemd service and disable it.
2. Remove the entry from the datastore.
3. Unmount all user home bind mounts (`/home/*/<container>/*`).
4. Terminate via `machinectl terminate`.
5. Delete `/srv/<container>` completely.

#### Removal (`srvctl remove-ve <container>`)

Same as destroy but creates a backup first. Intended for archiving before deletion.

### Rootfs Creation

Base container images are built with distro-specific scripts and stored in `$SC_ROOTFS_DIR/` (default `/var/srvctl3/rootfs/`).

#### Fedora (`mkrootfs_fedora_base`)

Uses `dnf --installroot` with the current Fedora `VERSION_ID`.

**Base packages:** dnf, initscripts, passwd, rsyslog, vim-minimal, openssh-server, openssh-clients, dhclient, chkconfig, rootfiles, policycoreutils, fedora-repos, fedora-release, bash-completion.

**Standard packages:** hostname, git, nodejs, gcc-c++, mc, openssl, postfix, mailx, sendmail, dovecot, unzip, rsync, wget, firewalld, cyrus-sasl (all).

**System users created:**

| Username | UID | Shell | Purpose |
|----------|-----|-------|---------|
| srv | 801 | nologin | Service account |
| git | 802 | nologin | Git operations |
| node | 803 | nologin | Node.js services |
| codepad | 804 | /bin/bash | Codepad interactive user |

**Post-setup:** Root SSH keys installed, srvctl symlinked, postfix/dovecot/systemd-networkd/systemd-resolved enabled.

#### Debian (`mkrootfs_debian_base`)

Uses `debootstrap stable`. Packages: ssh, systemd, dbus, libpam-systemd, mc, nodejs. Enables systemd-networkd and systemd-resolved.

#### Ubuntu (`mkrootfs_ubuntu_base`)

Uses `debootstrap focal` from `archive.ubuntu.com`. Same package set as Debian.

#### Arch (`mkrootfs_arch_base`)

Uses `pacstrap`. Packages: base, base-devel, inetutils. Enables systemd-networkd and systemd-resolved.

#### Shared Functions

| Function | Description |
|----------|-------------|
| `mkrootfs_root_ssh(rootfs)` | Copies root SSH keys into the rootfs |
| `mkrootfs_adduser(name, username)` | Creates a UID 1000 user with SSH access |

### Systemd Service Template

srvctl generates `/etc/systemd/system/srvctl-nspawn@.service` — a systemd template unit for container management.

```ini
[Service]
ExecStartPre=/bin/bash .../modules/containers/execstartpre.sh %i
ExecStart=/usr/bin/systemd-nspawn --quiet --keep-unit --boot \
    --link-journal=try-guest --settings=trusted \
    --machine=%i -D /srv/%i/rootfs
ExecStartPost=/bin/bash .../modules/containers/execstartpost.sh %i
ExecStopPost=/bin/bash .../modules/containers/execstoppost.sh %i

Type=notify
KillMode=mixed
RestartForceExitStatus=133
SuccessExitStatus=133
WatchdogSec=3min
Slice=machine.slice
TasksMax=16384
```

**Pre-start (`execstartpre.sh`):** Creates config directory, generates nspawn config from datastore (unless a `local.nspawn` override exists), validates required files.

**Post-start (`execstartpost.sh`):** Executes custom `ethernet.sh` if present, waits for container to stabilize, extracts and logs the container IP.

**Post-stop (`execstoppost.sh`):** Cleanup placeholder.

### Container Networking

Each container gets:

- A `host0` virtual ethernet interface with DHCP (default).
- A systemd-networkd configuration in `/srv/<container>/network/`.
- An `ethernet.sh` script for custom network setup.
- Optional bridge configuration for custom networks.
- Optional ZeroTier integration.

**Generated configuration files per container:**

| File | Purpose |
|------|---------|
| `/srv/C/C.nspawn` | systemd-nspawn settings (from datastore) |
| `/srv/C/network/80-container-host0.network` | Default DHCP config |
| `/srv/C/network/srvctl-ethernet.network` | Custom ethernet config |
| `/srv/C/hosts` | Container's `/etc/hosts` |
| `/srv/C/ethernet.sh` | Custom network setup script |
| `/srv/C/firewall_cmd.sh` | Firewall rules |

**Bind mounts:** The nspawn config includes extra bind mounts read from `*.binds` files in `/srv/C/` and `/srv/C/binds/`. Common binds include `/usr/local/share/boilerplate` and `/usr/local/share/codepad`.

### Resource Limits

**Per-container (systemd service):**

| Resource | Limit |
|----------|-------|
| CPU quota | 800% |
| Memory max | 16 GB |
| Memory high | 8 GB |
| Tasks max | 16384 |
| Device policy | Closed (whitelist) |
| Allowed devices | `/dev/net/tun`, `/dev/loop*`, `/dev/mapper` |

**Per-user slice:**

| Resource | Limit |
|----------|-------|
| CPU quota | 400% |
| Memory max | 16 GB |
| Memory high | 8 GB |

**System-wide (`srvctl-sysctl.conf`):**

| Parameter | Value |
|-----------|-------|
| `fs.file-max` | 4194304 |
| `fs.inotify.max_queued_events` | 2097152 |
| `fs.inotify.max_user_instances` | 2097152 |
| `fs.inotify.max_user_watches` | 4194304 |
| `vm.swappiness` | 1 |

**System-wide (`srvctl-limits.conf`):**

| Resource | Limit |
|----------|-------|
| Open files (all users) | 1048576 |
| Locked memory (all users) | Unlimited |

**Disk quota enforcement:** `all_containers_quota_check()` runs periodically, compares each container's disk usage against its quota (default 250 MB), and stops containers exceeding their quota.

### Container Commands

| Command | Description |
|---------|-------------|
| `add-ve <name> [type]` | Create a new container |
| `add-network-ve <name> <bridge>` | Create a container on a network bridge |
| `add-ve-user <name> <user>` | Add a user to a container |
| `backup-ve <name>` | Backup a container |
| `destroy-ve <name>` | Permanently delete a container |
| `remove-ve <name>` | Archive and delete a container |
| `recreate-ve <name>` | Rebuild rootfs preserving data |
| `status [name]` | Show container status |
| `regenerate [rootfs\|all]` | Regenerate configuration |
| `exec-all <command>` | Execute command on all running containers |
| `map-port <name> <port>` | Map a TCP/UDP port to host |
| `update-ve <name>` | Update container OS (unimplemented) |

The containers module also intercepts direct container names as commands, supporting:

```bash
srvctl <container-name> shell      # Open shell
srvctl <container-name> login      # Login
srvctl <container-name> status     # Status
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

Each host has a unique **HOSTNET** identifier between 16 and 255. By convention, each host is prefixed with a two-digit identifier in the company domain hostname.

### OpenVPN Mesh

The `openvpn` module creates a full mesh VPN between all cluster hosts.

**Server configuration:**
- UDP port 1101
- Subnet topology
- TLS server mode with CA-signed certificates
- Client config directory for per-client routing
- Address assignment: `10.15.<SC_HOSTNET>.0/24`

**Client configuration:**
- Per-host TUN device: `tun-host<hostnet>`
- Connects to peer host via `<host_ip>:1101`
- Client IP based on peer's HOSTNET value

**Certificate management:**
- On the CA host: `init_openvpn_rootca_certificates(net)` initializes the network CA and generates certificates for all cluster hosts.
- On other hosts: `grab_openvpn_rootca_certificates(net)` retrieves certificates via rsync/SSH from the CA host.
- Uses 2048-bit DH parameters.

**Firewall:** Opens UDP 1101 as `openvpn-hostnet`.

### Firewall — firewalld

The `firewalld` module manages host and container firewall rules.

**Global services configured:**
- Mail: imap, imaps, pop3s, smtp, smtps
- Web: http (80), https (443), http8080 (8080), https8443 (8443)
- Search: https9200 (9200)
- Masquerading enabled (NAT for containers)

**Functions:**

| Function | Description |
|----------|-------------|
| `firewalld_add_service(name, proto, port, hint)` | Add a firewall service permanently |
| `firewalld_offline_add_service()` | Add service in chroot/rootfs context |

Each service is defined as an XML file in `/etc/firewalld/services/`.

### DNS — named (BIND)

The `named` module runs an authoritative BIND DNS server with master/slave replication.

**Module activation:** Requires `SC_DNS_SERVER` set to `master` or `slave`.

**Configuration generation (`named.js`):**
- Generates zone files for all containers and their domains from the datastore.
- Creates master zones on the master server, slave zones with `masters` directives on slave servers.
- Stores zone files in `/var/named/srvctl/`.

**BIND configuration (`/etc/named.conf`):**
- ACL "trusted" for `10.0.0.0/8` and localhost.
- Recursion allowed only for trusted clients.
- DNSSEC validation enabled.
- Includes RFC1912 zones and root key.

**Commands:**

| Command | Description |
|---------|-------------|
| `override-in-address <container> <ip>` | Temporarily redirect a container's A records |

### DNS Scanning

The `dns` module monitors DNS records for all container domains.

**Scanner (`dns-scan.js`):**
- Queries Google DNS (8.8.8.8) for A, AAAA, MX, NS records.
- Caches results with hourly refresh for problematic domains.
- Stores scan results in the containers datastore with timestamps and state.

### Dynamic DNS

The `named` module includes a DYNDNS server:

**DYNDNS server (`dyndns-server.js`):**
- HTTPS server for dynamic DNS updates.
- POST endpoint for hostname updates with authentication.
- Stores IP in `/var/dyndns/` files.
- Executes `nsupdate` for BIND zone updates using TSIG authentication.

---

## Reverse Proxy — HAProxy

The `haproxy` module provides HTTP/HTTPS reverse proxying from the host to containers.

**Configuration generation (`haproxy.js`):**
- Reads container and host data from the datastore.
- Creates frontend/backend sections for each container.
- Generates ACLs based on domain names (sorted longest-first for specificity).
- SSL/TLS certificate binding per domain.
- Excludes mail containers from HTTP proxying.

**Certificate management:**
- Certificates loaded from the datastore and `/etc/srvctl/cert/`.
- PEM files validated and copied to `/var/haproxy/`.
- Supports wildcard certificates.

**Functions:**

| Function | Description |
|----------|-------------|
| `regenerate_haproxy_conf()` | Generate HAProxy config from datastore |
| `restart_haproxy()` | Full restart with syntax validation |
| `reload_haproxy()` | Graceful reload with validation |

**Commands:**

| Command | Description |
|---------|-------------|
| `http-redirect <container> <target>` | Set HTTP redirect |
| `https-redirect <container> <target>` | Set HTTPS redirect |

**Logging:** rsyslog configured for `local2` facility, logs to `/var/log/haproxy.log`.

**Diagnostics:** The `diagnose` hook shows HAProxy stats and session info.

---

## Certificates and TLS

### Certificate Authority (CA)

The `ca` module provides a centralized root CA for internal infrastructure.

**Root CA creation (`root_CA_create`):**
- 4096-bit RSA key
- 10-year validity
- Stored in `/etc/srvctl/CA/`

**Certificate creation (`create_ca_certificate`):**
- Creates client and server certificates with proper extensions.
- Validates certificate/key modulus matching.
- Checks 24-hour expiration threshold.
- Supports PKCS12 export for client certificates.

**CA synchronization (`ca_sync`):**
- Syncs the CA directory from the root CA host to all other hosts via rsync/SSH.
- `SC_ROOTCA_HOST` designates which host is the CA.

**Configuration:** `SC_ROOTCA_SUBJ` sets the certificate subject (e.g., `/C=HU/ST=Hungary/L=Budapest/O=D250-Laboratories-CA`).

### Domain Certificates

The `certificates` module handles certificate lifecycle for containers and services.

**Self-signed certificates (`create_selfsigned_domain_certificate`):**
- PEM format: key + certificate + CA bundle.
- SAN (Subject Alternative Name) support.
- 10-year validity.
- Removes passphrase from the private key.

**Service certificates (`install_service_hostcertificate`):**
- Discovery priority: company domain > hostname prefix > exact hostname > any available.
- Adds DH parameters for services requiring them (e.g., Perdition).
- Restrictive file permissions (400).

### Let's Encrypt / ACME

The `letsencrypt` module automates public certificate acquisition.

**ACME server (`acme-server.js`):**
- HTTP server on port 1028.
- Serves challenge files from `/var/acme/.well-known/acme-challenge/`.
- Runs as the `acme` user.

**Certificate acquisition (`letsencrypt.js`):**
- Checks prerequisites: no `www` prefix, no wildcard, valid DNS pointing to host.
- Uses `certbot --webroot` method.
- Deploys certificates to the datastore and container rootfs TLS directories.
- Skips development, local, and mail domains.

**Installation (`install_acme`):**
- Installs certbot.
- Creates `/etc/letsencrypt/cli.ini` with email and webroot settings.
- Sets up the ACME server as a systemd service.

### Wildcard Certificates

**Validation (`check_wildcard_pem`):** Validates wildcard certificates and checks for 7-day expiration.

**Application (`apply_wildcard_certificates`):** Matches wildcard certificates from the datastore against container domains and applies them.

---

## Mail Stack

srvctl provides a complete mail infrastructure stack.

### Postfix (SMTP)

The `postfix` module manages SMTP on both hosts and containers.

**Host configuration (`hs-main.cf`):**
- Accepts connections on all interfaces.
- Trusts: `127.0.0.0/8`, `10.0.0.0/8`, `192.168.0.0/16`.
- TLS with certificates at `/etc/postfix/crt.pem` and `key.pem`.
- SASL authentication enabled (Cyrus SASL).
- Content filter: Amavis virus scanner (`127.0.0.1:10024`).
- OpenDKIM milter at `127.0.0.1:8891`.
- 25 MB message size limit.

**Container configuration (`ve-main.cf`):**
- Relay host: `srvctl-gateway` (containers relay through the host).
- Maildir format for local delivery (`home_mailbox = Maildir/`).
- No virus scanning or DKIM (handled by the host).
- SASL enabled, no anonymous auth.

**Functions:**
- `regenerate_etc_postfix_relaydomains()` — Manages relay domain configuration.
- `write_ve_postfix_conf()` — Writes Postfix config for containers.
- `restart_postfix()` — Restart with status verification.

**Installation:** Installs postfix, amavisd-new, spamassassin, creates certificates.

**Firewall:** SMTP (25), SMTPS (465).

### SASL Authentication — saslauthd

The `saslauthd` module provides SASL authentication for Postfix using remote IMAP.

**Configuration:**
- Mechanism: `rimap` (remote IMAP authentication).
- Flags: `-n 0 -O localhost -r` (no threading issues, localhost backend, include realm).

**Commands:**
- `fix-saslauthd` — Restarts saslauthd to fix mailing issues.
- `testsaslauthd` — Tests user authentication by reading `.password` files from containers.

### Perdition (IMAP/POP3 Proxy)

The `perdition` module provides IMAP4/POP3 reverse proxying.

**Routing (`perdition.js`):**
- Generates `/var/perdition/popmap.re` mapping rules from the container list.
- Maps `(.*)@domain` to `mail.domain` backend server.

**Configuration:**
- Binds on `0.0.0.0`.
- Uses `popmap.re` for regex-based routing.
- SSL certificates at `/etc/perdition/`.

**Services:** Three separate systemd units: `imap4.service`, `imap4s.service`, `pop3s.service`.

**Firewall:** imaps, pop3s, imap.

### OpenDKIM (DKIM Signing)

The `opendkim` module adds DKIM signatures to outgoing email.

**Configuration generation (`opendkim.js`):**
- Generates DKIM keys via `opendkim-genkey` for each container.
- Creates `KeyTable`, `SigningTable`, `TrustedHosts` files.
- Stores private keys in `/var/opendkim/<domain>/`.

**Integration:**
- Mode: `vs` (sign + verify).
- Socket: `inet:8891@127.0.0.1` (Postfix milter integration).
- Selectors: `default` for regular domains, `mail` for `mail.*` containers.

### Mozilla Autoconfig

The `mozilla` module provides automatic email client configuration for Thunderbird.

**HTTP server (`mozilla-autoconfig-server.js`, port 1029):**
- Serves `.well-known/autoconfig/mail/config-v1.1.xml`.
- Configures: IMAP (993/SSL), POP3 (995/SSL), SMTP (465/SSL).
- Password cleartext authentication.

---

## User Management

### User Model

srvctl uses a hierarchical user model:

```
Root (user_id=0)
└── Resellers (have reseller_id field)
    └── Users (belong to a reseller)
        └── Containers (owned by users)
```

- **Root** has full access to everything.
- **Resellers** can create users and manage their users' containers.
- **Users** can manage their own containers.

Each user has a unique `user_id` that maps to a network segment: container IPs are `10.<hostnet>.<user_id>.<offset>`.

### Host Users — usersonhost

The `usersonhost` module manages users on the host system.

**User provisioning (`main.js`):**
- Creates system users.
- Generates passwords and SSH keys.
- Updates host system accounts.
- Handles reseller relationships.

**User configuration (`user.js`):**
- Reads `users.json` from the datastore.
- Generates per-user shell configuration (`~/.srvctl/user.conf`).
- Exports `SC_USER_*` variables.

**Functions:**

| Function | Description |
|----------|-------------|
| `create_user_id()` | Creates user, password, SSH key, and client certificate |
| `regenerate_users()` | Regenerates all user configurations |
| `create_user_password()` | Updates password from datastore |

**Commands:**

| Command | Description |
|---------|-------------|
| `add-user <name>` | Create a new user (reseller-only) |
| `add-reseller <name>` | Create a new reseller (root-only) |
| `add-publickey [keyfile]` | Add SSH public key to user account |

### Container Users — usersonve

The `usersonve` module manages users inside containers.

**Commands:**

| Command | Description |
|---------|-------------|
| `add-user <name>` | Add user to container with password and mail notification |
| `add-zerotier` | Install ZeroTier VPN and join a network |
| `vnc-desktop` | Create VNC remote desktop session (see [VNC Desktop](#vnc-desktop)) |
| `install-crossover` | Placeholder for Wine/Crossover |
| `install-qlcplus` | Placeholder for QLC+ lighting control |

---

## SSH Access

### SSH Key Management

The `ssh` module provides centralized SSH key management.

**SSH configuration (`sshd_config`):**
- `PermitRootLogin: yes`
- `PasswordAuthentication: no` (key-based only)
- `AuthorizedKeysCommand` points to `sshd_authorization.sh`
- X11 forwarding and GSSAPI enabled.

**Authorization script (`sshd_authorization.sh`):**

Aggregates authorized keys from multiple sources for each login:

1. Common root keys: `/var/srvctl3/share/common/authorized_keys`
2. User SSH keys: `/var/srvctl3/gluster/srvctl-data/users/<user>/*.pub`
3. User datastore keys: `/var/srvctl3/datastore/users/<user>/*.pub`
4. Container user keys: `/var/srvctl3/share/containers/<hostname>/users/*/*.pub`

**Key types:** ECDSA keys are generated per user — `id_ecdsa` for user access and `srvctl_id_ecdsa` for system use.

**Regeneration:** The regenerate hook clears `authorized_keys` and calls `regenerate_ssh_config` to rebuild from the datastore.

### SSHPipeRD — SSH Proxy

The `sshpiperd` module provides an SSH proxy that routes connections to containers based on composite usernames.

**Username format:** `<user>_<container>_<service>`

For example: `john_example.com_root` connects as `root` to the container `example.com`, authenticated as srvctl user `john`.

**Regex validation:** `^[a-z][-a-z0-9.]{0,31}_[-a-z0-9.]{0,256}_[-a-z0-9]{0,31}$`

**Implementation:** Modified Go version of sshpiper with srvctl customizations.

**Key mapping:**
- Searches `*.pub` files in the user's datastore directory.
- Falls back to `/var/srvctl3/share/common/authorized_keys`.
- Loads matching private key (`srvctl_id_ecdsa`) for upstream connection.

**Setup:**
- Listens on port 2222.
- Runs as the `sshpiperd` system user.
- Uses bindfs to mount user datastore read-only at `/var/sshpiper`.

---

## Storage

### GlusterFS

The `gluster` module manages distributed storage across cluster hosts.

**Activation:** Only on multi-host clusters.

**Functions:**

| Function | Description |
|----------|-------------|
| `gluster_install()` | Installs glusterfs-server, sets SSL symlinks, enables service |
| `gluster_configure()` | Creates replicated volumes (replica factor = host count) |
| `gluster_mount_data()` | Mounts GlusterFS volumes |
| `gluster_reset()` | Cleanup and removal |

**Volumes:**
- Bricks at `/glu/<datadir>/brick`.
- Read-only bindmount to `/var/srvctl3/gluster/<datadir>`.
- FUSE mount to `/srvctl/data`.
- SSL enabled.

### NFS

The `nfs` module shares `/srv` across the cluster via NFS.

**Exports:** `/srv` is shared to `10.15.0.0/16` (OpenVPN network) with read-write access.

**Mounts:** Remote hosts' `/srv` directories are mounted at `/var/srvctl3/nfs/<host>/srv/`.

### Static File Server

The `static` module serves static files via an Express-based Node.js server on port 1280.

**Route:** `/var/srvctl3/storage/static/<host>/html`

**Logging:** host, URL, user-agent, X-Forwarded-For.

### FTP — vsftpd

The `ftp` module installs and configures vsftpd for FTP file transfers.

---

## Application Modules

### WordPress

The `wordpress` module provides WordPress installation on containers.

**Installation (`srvctl install-wordpress`):**

1. Installs PHP 8.0.11, `php-mysqlnd`, and the `wordpress` package.
2. Creates Apache `mod_rewrite` configuration for permalink support.
3. Downloads the latest WordPress from source.
4. Creates `wp-config.php` with database credentials.
5. Creates `wp-install.php` for headless installation.
6. Generates a random admin password.
7. Auto-creates a MariaDB database via `add_mariadb_db`.

**Password recovery:** `restore-wordpress-password.sh` resets the admin password via direct MD5 database update.

### Odoo ERP

The `odoo` module installs Odoo 14 Community Edition.

**Installation (`srvctl install-odoo`):**

1. PostgreSQL setup with UTF-8 locale.
2. Creates `odoo` system user.
3. Git clones OCB (Odoo Community Bundle).
4. Creates addon directory structure.
5. Python virtualenv with dependencies.
6. Systemd service integration.
7. Apache proxy configuration.

**Configuration:**
- Port 8069 (XML-RPC), 8072 (longpolling).
- Proxy mode enabled.
- 5 workers, memory/CPU time limits.

### MariaDB

The `mariadb` module manages MySQL/MariaDB database servers.

**Functions:**

| Function | Description |
|----------|-------------|
| `setup_mariadb()` | Install mariadb-server |
| `check_mariadb_connection()` | Validate connection using defaults file |
| `backup_mariadb()` | Per-database backups to `/root/mariadb-dump/` |
| `add_mariadb_db()` | Create database + user + password |
| `secure_mariadb()` | Remove test DB, set root password |
| `mysql_root()` | Direct MySQL shell access |

**Credential storage:** Per-database config at `/etc/mariadb-<dbname>.conf`, dump credentials at `/etc/mysqldump.conf`.

### Codepad

The `codepad` module deploys collaborative code editor containers.

**Container creation (`srvctl add-codepad <name>`):**
- Creates a Fedora container with the `-devel` suffix requirement.
- Installs development packages: gcc, git, postgresql-devel, mariadb, ShellCheck, etc.
- Creates a codepad Node.js service.
- Sets up MongoDB.

**Access management (`access.js`):**
- Copies user authentication keys to container share directories.
- Handles primary users, additional developers, and reseller access.

**Project initialization (`init_codepad_project.sh`):**
- ECDSA SSH key generation.
- Git repository initialization.
- Links to boilerplate project.
- Symbolic link to user access directory.

**Firewall:** Ports 9000 (HTTP) and 9001 (HTTPS).

### VNC Desktop

The `usersonve` module includes VNC desktop creation via `vnc-desktop`:

1. Installs `tigervnc-server`.
2. Creates user `x` for VNC access.
3. Configures a desktop environment (xfce, gnome, ratpoison, etc.).
4. Sets up `xbindkeys` for custom keyboard shortcuts.
5. Creates a systemd `vncserver` service.

---

## Backup

### Filesystem Backup

The `backup` module provides rsync-based backup utilities.

**Functions:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `local_backup` | `[directories]` | Backs up local directories to `$SC_BACKUP_PATH/$HOSTNAME` |
| `server_backup` | `[host] [directories]` | Remote backup via SSH with rsync |
| `remote_backup` | `[proxyhost] [datahost] [directories]` | Backup through SSH tunnel/proxy |

**Features:**
- Rsync with `--delete-after -a` for consistent snapshots.
- Source vs destination size and file count display.
- Logging to `$SC_HOME/.srvctl/backup.log`.
- Concurrent backup prevention.

### Container Backup

**7-Zip backup (`local_container_7z_backup`):**

Creates individual 7z archives per container directory:

| Archive | Content |
|---------|---------|
| `cert.7z` | SSL certificates |
| `srv.7z` | Service data |
| `home.7z` | User home directories |
| `root.7z` | Root home |
| `etc.7z` | Configuration |
| `var.7z` | Variable data |
| `var-lib-mysql.7z` | Database files |

Also saves package lists (dnf) and a file listing for the entire container.

### Database Backup

The `backupdb` module handles database-specific backups.

**MariaDB:** Calls `backup_mariadb()` which dumps each database individually to `/root/mariadb-dump/`.

**MongoDB:** Uses `mongodump` to `/root/mongodb-dump/<timestamp>/`. Includes tools: mongodump, mongoexport, mongoimport, mongorestore, mongostat, mongotop, bsondump.

---

## System Administration

### Diagnostics

The `srvctl diagnose` command performs comprehensive system checks:

- srvctl version and key variables.
- System uptime, kernel version, boot configuration.
- Inactive systemd services.
- Postfix fatal errors (since yesterday).
- Mail queue status.
- Firewall settings (zones, services, interfaces).
- Process table.
- Connected shell users.
- Memory, disk, CPU statistics.
- Container network pingback (8.8.8.8 and d250.hu from each container).
- `/srv` directory permissions.
- `systemd-cgtop` summary.

### Version Management

`srvctl version` reports installed software versions including postfix, nodejs, and other important packages. Each module can contribute via the `version` hook.

The version file at `$SC_INSTALL_DIR/version` contains the current version string (e.g., `3.2.5.9`).

### Update and Installation

`srvctl update-install [hostname]` is the primary installation and update mechanism.

**On containers:** Runs `update-install-ve` hooks.

**On hosts:**
1. Configures cluster setup, SELinux.
2. Installs core dependencies (mc, nodejs, git).
3. Sets hostname if not already configured.
4. Configures git globally.
5. SSH-scans all cluster hosts.
6. Runs all module `update-install-host` hooks (installs services, firewall rules, etc.).
7. Sets file permissions.
8. Generates command completions.

### Regeneration

`srvctl regenerate` updates configuration across the system.

**Default:** Runs the `regenerate` hook from all enabled modules. This triggers:
- Validation of `/srv` permissions.
- Container directory and database synchronization.
- `/etc/hosts` regeneration.
- Network configuration rebuild.
- Inotify settings check.
- Quota enforcement.
- Certificate regeneration and application.
- HAProxy config rebuild.
- DNS zone regeneration.
- Postfix relay domain updates.
- SSH key redistribution.
- DKIM key management.
- Let's Encrypt certificate renewal.

**With `rootfs` argument:** Rebuilds base container images via `regenerate_rootfs` hook.

**With `all-hosts` argument:** Runs regeneration on all cluster hosts via SSH.

**Cron job:** `/etc/cron.hourly/srvctl-regenerate.sh` runs regeneration automatically every hour.

### Utility Commands

| Command | Description |
|---------|-------------|
| `customize <name>` | Create/edit custom commands in `~/srvctl-includes/` |
| `fix-owner` | Recursive chown to match parent directory ownership |
| `fix-sshd` | Fix sshd key file permissions |
| `ls` | Recursive file listing sorted by modification date |

---

## Web GUI

The `gui` module provides a web-based administration interface.

**Server (`server.js`, port 250):**
- HTTPS with client certificate verification against the usernet CA.
- Framework: Express + Socket.io.
- SSH integration for remote command execution.
- Loads datastore JSON files.
- Parses command specs from `/var/local/srvctl/commands.spec`.
- Terminal emulation via wetty.

**Frontend:**
- `index.html` — Main GUI entry point.
- `wetty.html/js` — Terminal emulation.
- `scripts.js`, `styles.css` — UI logic and styling.

**Dependencies:** express, pty.js, socket.io, ssh2.

**Status:** Installation hook currently commented out (under development).

---

## Branding

The `branding` module customizes web interfaces and error pages.

**Configuration:**
- `SC_COMPANY` — Company name.
- `SC_COMPANY_DOMAIN` — Company domain.

**Generated content:**
- Branded `index.html` with company logo and name (`setup_index_html()`).
- HTTP error pages: 400, 403, 404, 408, 414, 500, 501, 502, 503, 504.

**Assets:** `logo.svg`, `favicon.ico`, `503.html`.

---

## Password Generation

The `password` module generates pronounceable, memorable passwords.

**Pattern:** Two words separated by a hyphen. Each word uses consonant-vowel combinations or consonant clusters (e.g., "Brand-Sleek", "Ting-Krap").

**Implementations:**
- Node.js (`lib.js` / `get-password.js`).
- Pure bash (`libs/get-password.sh`).

**Usage:** Called by certificate generation, new user creation, and authentication token generation throughout the system.

---

## Development Tools

### push.sh — Build and Publish

Development script for building and publishing srvctl:

1. Enforces execution as the `codepad` user.
2. Backs up the project to `/srv/push-backup`.
3. Increments the version number.
4. Runs shellcheck on all `.sh` files.
5. Beautifies bash code using a Python script.
6. Optionally stages, commits, and pushes via git.
7. Generates `README.md` from `README.txt` and help output.

### encode.mjs — File Encoding Tool

Node.js utility that recursively scans project directories and merges source files (.mjs, .sh, .js) with metadata into a single output file at `var/tools/$PROJECT.$VERSION.txt`.

Skips: `node_modules`, `.git`, `var`, `cert` directories. Handles symlinks and circular references.

### claude.sh — Claude Integration

Wrapper script that invokes the Claude CLI with restricted tool permissions:

```bash
claude --allowed-tools Bash,Read,Edit,WebFetch
```

---

## Configuration Reference

### System Directories

| Path | Purpose |
|------|---------|
| `/usr/local/share/srvctl/` | Installation directory |
| `/etc/srvctl/` | Static configuration (JSON, .conf files) |
| `/etc/srvctl/data/` | Cluster, branding, and CA configuration |
| `/etc/srvctl/CA/` | Certificate authority files |
| `/etc/srvctl/cert/` | Host certificates |
| `/var/srvctl3/datastore/` | Read-write data store |
| `/var/srvctl3/rootfs/` | Container rootfs templates |
| `/var/srvctl3/mounts/` | Container mounts |
| `/var/srvctl3/share/` | Shared data (containers, common keys) |
| `/var/srvctl3/gluster/` | GlusterFS mounted data |
| `/var/srvctl3/ssh/` | SSH known hosts |
| `/var/srvctl3/storage/` | Static file storage |
| `/var/srvctl3/nfs/` | NFS mounts from cluster hosts |
| `/var/local/srvctl/` | Module state, command specs |
| `/srv/` | Container root directories |
| `/var/haproxy/` | HAProxy certificates |
| `/var/perdition/` | Perdition popmap |
| `/var/opendkim/` | DKIM keys |
| `/var/named/srvctl/` | DNS zone files |
| `/var/acme/` | ACME challenge files |
| `/var/sshpiper/` | SSHPipeRD user mapping |
| `/var/dyndns/` | Dynamic DNS update files |
| `/glu/srvctl-data/` | GlusterFS brick (sensitive data) |
| `/glu/srvctl-storage/` | GlusterFS brick (bulk storage) |

### Key Environment Variables

| Variable | Description |
|----------|-------------|
| `SRVCTL` | Version string (e.g., `srvctl-3.2.5.9`) |
| `SC_INSTALL_DIR` | Installation directory |
| `SC_INSTALL_BIN` | Path to srvctl.sh |
| `SC_MODULES` | Space-separated module directory list |
| `SC_TTY` | Running in terminal (boolean) |
| `SC_STARTTIME` | Startup timestamp (ms) |
| `SC_USER` | Current user |
| `SC_UID0` | Running as root (boolean) |
| `SC_HOME` | User home directory |
| `SC_LOG` | Log file path |
| `SC_HOSTNET` | Host's unique network ID (16–255) |
| `SC_CLUSTERNAME` | Cluster name |
| `SC_HOSTNAME` | System hostname |
| `SC_COMPANY` | Company name |
| `SC_COMPANY_DOMAIN` | Company domain |
| `SC_ROOTCA_HOST` | Root CA host |
| `SC_ROOTCA_DIR` | Root CA directory |
| `SC_ROOTCA_SUBJ` | Root CA certificate subject |
| `SC_ROOTFS_DIR` | Container rootfs templates directory |
| `SC_MOUNTS_DIR` | Container mounts directory |
| `SC_DATASTORE_RO_DIR` | Read-only datastore |
| `SC_DATASTORE_RW_DIR` | Read-write datastore |
| `SC_BACKUP_PATH` | Backup destination path |
| `SC_BACKUP_HOST` | Remote backup host |
| `SC_DNS_SERVER` | DNS server role (master/slave) |
| `SC_OPENVPN_HOSTNET_SERVER` | OpenVPN hostnet server |
| `SC_VIRT` | Virtualization type (systemd-nspawn, lxc, or empty) |
| `SC_USE_<MODULE>` | Module enabled flag (e.g., `SC_USE_CONTAINERS`) |
| `CMD` | Current command |
| `ARG` | First argument |
| `ARGS` | All arguments |
| `DEBUG` | Debug mode flag |
| `NOW` | Current timestamp |

### Configuration Files

| File | Format | Purpose |
|------|--------|---------|
| `/etc/srvctl/clusters.json` | JSON | Cluster host definitions |
| `/etc/srvctl/hosts.json` | JSON | Generated host data |
| `/etc/srvctl/host.conf` | Bash | Host-specific settings |
| `/etc/srvctl/data/branding.conf` | Bash | Company name and domain |
| `/etc/srvctl/data/ca.conf` | Bash | CA host and subject |
| `/etc/srvctl/debug.conf` | Bash | Debug settings |
| `$SC_DATASTORE_RW_DIR/containers.json` | JSON | All container definitions |
| `$SC_DATASTORE_RW_DIR/users.json` | JSON | All user definitions |
| `/var/local/srvctl/modules.conf` | Bash | Module enable/disable state |

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

---

## Command Reference

### Container Management

| Command | Description |
|---------|-------------|
| `srvctl add-ve <name> [type]` | Create a new container (types: fedora, debian, ubuntu, arch) |
| `srvctl add-network-ve <name> <bridge>` | Create a container on a network bridge |
| `srvctl add-ve-user <name> <user>` | Add a user to a container's cluster |
| `srvctl status [name]` | Display container(s) status |
| `srvctl backup-ve <name>` | Backup a container |
| `srvctl recreate-ve <name>` | Rebuild rootfs preserving data |
| `srvctl destroy-ve <name>` | Permanently delete a container |
| `srvctl remove-ve <name>` | Archive and delete a container |
| `srvctl exec-all <command>` | Execute command on all running containers |
| `srvctl map-port <name> <port>` | Map a TCP/UDP port to host |
| `srvctl regenerate [rootfs\|all]` | Regenerate configuration or rootfs |

### Direct Container Interaction

| Command | Description |
|---------|-------------|
| `srvctl <container> shell` | Open a shell in the container |
| `srvctl <container> login` | Login to the container |
| `srvctl <container> status` | Show container status |
| `srvctl <container> reboot` | Reboot the container |
| `srvctl <container> poweroff` | Power off the container |
| `srvctl <container> kill` | Kill the container |

### Shorthand Commands

| Shorthand | Command |
|-----------|---------|
| `?` | `status` |
| `+` | `start` |
| `-` | `stop` |
| `!` | `restart` |

### User Management

| Command | Description |
|---------|-------------|
| `srvctl add-user <name>` | Create a new user (reseller/root) |
| `srvctl add-reseller <name>` | Create a new reseller (root only) |
| `srvctl add-publickey [keyfile]` | Add SSH public key |

### Application Installation

| Command | Description |
|---------|-------------|
| `srvctl install-wordpress` | Install WordPress (inside container) |
| `srvctl install-odoo` | Install Odoo 14 ERP (inside container) |
| `srvctl add-codepad <name>` | Create a codepad development container |

### Proxy and Redirects

| Command | Description |
|---------|-------------|
| `srvctl http-redirect <container> <target>` | Set HTTP redirect |
| `srvctl https-redirect <container> <target>` | Set HTTPS redirect |
| `srvctl override-in-address <container> <ip>` | Override DNS A record temporarily |

### System Administration

| Command | Description |
|---------|-------------|
| `srvctl update-install [hostname]` | Install or update srvctl system |
| `srvctl diagnose` | Run system diagnostics |
| `srvctl version` | Display version information |
| `srvctl customize <name>` | Create/edit custom commands |
| `srvctl fix-owner` | Fix file ownership recursively |
| `srvctl fix-sshd` | Fix sshd key permissions |
| `srvctl fix-saslauthd` | Restart SASL authentication |
| `srvctl ls` | Recursive file listing by modification date |

### Datastore Operations

| Command | Description |
|---------|-------------|
| `srvctl get <type> <name> <field>` | Retrieve a configuration value |
| `srvctl put <type> <name> <field> <value>` | Set a configuration value |
| `srvctl new <type> <name>` | Create a new entry |
| `srvctl del <type> <name>` | Delete an entry |
| `srvctl out <type> <name>` | Output entry as env-vars or JSON |
| `srvctl cfg <type> <name> <operation>` | Run a configuration operation |
| `srvctl add <type> <name> <field> <value>` | Add to a collection |

### Mail Administration

| Command | Description |
|---------|-------------|
| `srvctl testsaslauthd` | Test SASL authentication |

### Backup

| Command | Description |
|---------|-------------|
| `srvctl backup-ve <name>` | Backup a specific container |

---

## Inter-Module Dependencies

```
                         CA
                    ┌────┴────────────────┐
                    │                     │
                OpenVPN              Certificates
                    │              ┌──────┴──────┐
                    │              │              │
                    │         Let's Encrypt   Wildcards
                    │              │
                    └──────┬───────┘
                           │
                  ┌────────┴────────┐
                  │                 │
               Named            HAProxy
                  │                 │
              DNS Scan         Branding
                                   │
                              Error Pages

         Postfix ←→ saslauthd ←→ Perdition
            │
         OpenDKIM

         SSH ←→ SSHPipeRD ←→ usersonhost ←→ usersonve

         Containers ←→ Datastore ←→ GlusterFS
              │
         ┌────┼────────┬──────────┐
         │    │         │          │
     WordPress Odoo  Codepad   MariaDB
```

---

## Known Issues and Workarounds

From `TODO.txt`:

- **pthread_create** — "Resource temporarily unavailable" kernel issue with containers.
- **Network unreachable** — Requires `systemd-networkd` restart in affected containers.
- **Container restart failure** — May need to remove `--keep-unit` flag from service template.
- **Dovecot key size** — Bug with certain key sizes in older versions.
- **Firewall bridges** — Bridge interfaces must be on the trusted zone.
- **saslauthd threading** — Use `-n 0` flag to avoid threading issues.
