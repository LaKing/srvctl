Srvctl 4 (4.0.0.8) - the version is the content of the 'version' file in this repo; the runtime exports it as SRVCTL=srvctl-4.0.0.8 (srvctl.sh).
Under construction, - srvctl is a containerfarm-manager for microsite hosting webservers with fedora as the host operating system. It will help to set up, maintain, and to let a couple of servers work together in order to have solid web-serving services.
Version 4 is a rewrite in core mostly using systemd tools, thus using systemd-nspawn as the containerfarm manager. Written in the mix of bash and javascript, a modular design (37 modules under modules/) allows to extend it with programs. Basically it is a collection of scripts, and fast scripts. The on-disk paths still carry the version-3 name, /var/srvctl3.

How it works:
After installation there should be a main-command available called srvctl or in short sc. This will trigger srvctl scripts, and process srvctl-commands, with their arguments. Goal is to make easy to use, and easy to remember human-friendly command sets for daily usage. Primary goal is managment of a web-hosting server and containerfarm that hosts microsites. 

Installation:
Srvctl 4 is designed for a standard fedora server edition. It may work on similar distros. Containers may use other distributions.
A srvctl host as part of a cluster was meant to keep its data on glusterfs. That is inert at this version: modules/gluster/module-condition.sh is a kill-switch - it echoes false even on the "all checks passed" branch - so the module never loads, no volume is created or mounted, the datastore stays on the local /var/srvctl3/datastore and /var/srvctl3/storage is a plain local directory. The two bricks below are only needed if that kill-switch is lifted. While installing your operating system, create:
- 2GiB XFS partition mounted on /glu/srvctl-data, brick of the srvctl-data volume, that will store certificates, passwords, and other sensitive data.
- 500GiB XFS partition mounted on /glu/srvctl-storage, brick of the srvctl-storage volume, preferably on a seperate drive for data storage, such as static file service or ftp.
- /var/log 
- /home, separate partitions for directories so that the primary root partition wont get full at any time. 
- /srv, this will be our main directory for containers, therefore it should be a big and fast SSD.

Users and UID/GID numbers have to be consistent across the clustered servers, therefore, don't create any users outside of srvctl. 
Setting a hostname is mandatory. Needless to say, you mostly have to operate as root. Also, correct DNS entries (forward and reverse) and NTP are essential.

As root, clone the repo and create some symlinks for it.
```
    dnf -y install git
    cd /usr/local/share
    git clone https://github.com/LaKing/srvctl.git && bash srvctl/srvctl.sh
     
```

At this point the srvctl command should be ready to be used.
To use srvctl as a containerfarm host, create the static configuration by hand
(no example files are shipped since 4.0.0.7):

    /etc/srvctl/clusters.json       - canonical cluster topology, the sole topology source (JSON)
    /etc/srvctl/data/branding.conf  - SC_COMPANY and SC_COMPANY_DOMAIN (bash)
    /etc/srvctl/data/ca.conf        - SC_ROOTCA_HOST and SC_ROOTCA_SUBJ (bash)

Complete copy-paste templates for all three files are in the Initial
Configuration section of documentation/documentation.md.
Note that srvctl sources /etc/srvctl/*.conf, not /etc/srvctl/data/*.conf: the
data directory holds the seeds, and 'srvctl update-install' (or test-modules)
copies every /etc/srvctl/data/*.conf up to /etc/srvctl/ before the modules
initialize. clusters.json is deliberately excluded from that copy - it is read
from /etc/srvctl/clusters.json only.

Most static configuration files reside in /etc/srvctl. Data is stored in BASH formatted, sourcable variable description files, and in JSON files.
The datastore module saves configuration informations. The verbs new, put and del git-commit the changed records inside the read-write datastore (datastore_push, modules/datastore/libs/gitlib.sh); cfg and add mutate without committing. The topology is pushed to the other hosts by publish_data - see The datastore below. Gluster replication of the datastore is disabled, see Installation.
Servers can interact with each other over VPN, and containers are on an internal network:

In srvctl we use a single class A network 10.x.x.x for communication of containers and hosts.
Each server has to have a unique HOSTNET id between 16..255 for the server cluster. It is the "hostnet" key of the host record in clusters.json, projected into /var/srvctl3/host/host.conf as SC_HOSTNET; the range is convention, nothing validates it, and an unset value falls back to 250 (modules/containers/hooks/post-init.sh).
By convention, each host should be prefixed with a two digit host identifier in your company domain hostname.

10.0.0.0 - 10.14.255.255 - reserved for external networks and openvpn connections outside of srvctl
10.15.x.y - reserved for openvpn hostnet-network - connections from host to host. Openvpn connections created from every server to every server, thus x is the server hostnet y the client hostnet on a particlar host. The openvpn module is live, but it is a deprecation candidate for v4.
10.<hostnet>.<user_id>.<c> - container addresses: the hostnet of the host that runs the container, the owning user's sequential user_id (1..255) and a per-user sequential offset.

We can divide users and assign them to resellers, so we should.


Using srvctl

Some applications controlled by srvctl need to use certificates in order to communicate securly. Therefore it is recommended to use a host, or better said dedicate a host as CA. That host is named by SC_ROOTCA_HOST in /etc/srvctl/data/ca.conf; the root CA is created and signs only on the host whose hostname matches it.

The 'srvctl update-install' process can be, and eventually has to be run over and over. The srvctl scripts generate configuration files. 'srvctl regenerate' rewrites those generated files without reinstalling, and 'srvctl regenerate all-hosts' does it on every host of the cluster.

Experts may run certain functions in the context of srvctl, that means with internal variables and settings
    srvctl exec-function SRVCTL_FUNCTION [ARGUMENTS]
This dispatch is genuine-root only: SC_USER must be root AND the uid 0, and at least one argument is required (run_command, commonlib.sh). Plain uid 0 reached through sudo is not enough.

The main datastore functions may be accessed directly, so instead of writing
    srvctl exec-function out host t1.test.vm
.. it is possible to write directly
    srvctl out host t1.test.vm
The read verbs get and out are open to any caller; the mutating verbs new, put, cfg, del and add are dispatched only for genuine root with arguments. get exits 100 when an optional value is simply not defined.

The datastore

Srvctl maintains configuration data in json files. Cluster topology has one
canonical path on each host: /etc/srvctl/clusters.json. It must be identical on
all hosts and must not be copied into /etc/srvctl/data or /var.
/etc/srvctl/data - non-topology static configuration seeds
/var/srvctl3/host - generated per-host projection of the topology (host.conf, hosts.json), never edit
/var/srvctl3/datastore - the read-write datastore, SC_DATASTORE_RW_DIR: a git repository with one file per entity under hosts/, users/ and containers/
/var/srvctl3/gluster/srvctl-data - the readonly replica, SC_DATASTORE_RO_DIR. It is selected only when the gluster module is enabled and its mount FAILS - SC_DATASTORE_RO_USE defaults to true (modules/datastore/hooks/pre-init.sh:24) and is cleared on a successful mount; with gluster disabled it is cleared unconditionally, so the read-write directory is always used.

On the first upgrade to fail-closed topology publication, deploy the same
srvctl version to every configured host while the canonical file still lists
the complete deployed inventory, then run:

    srvctl exec-function initialize_cluster_publication confirm-complete-inventory

Do this before removing or renaming any host: initialization can verify the
hosts still listed, but cannot discover one already deleted from the first
baseline. The publication manifest stores only the verified canonical SHA-256
and ordered hostnames, never a second topology copy.

For normal changes, edit /etc/srvctl/clusters.json, run
`srvctl exec-function publish_data`, then `srvctl regenerate all-hosts`.
Before removing or renaming OLDHOST, drain its workloads and, while it still
answers under that hostname, run from the same publication controller that
initialized and owns the manifest (never from OLDHOST itself):

    srvctl exec-function retire_cluster_host OLDHOST confirm-decommissioned

Only after retirement succeeds may you remove/rename its canonical entry and
publish. Retirement stops and disables its authoritative BIND role before
detaching topology. For a rename, make the machine answer under its new
canonical hostname, publish, then run `srvctl update-install NEWHOST` on that
machine before the final `srvctl regenerate all-hosts`. Publication re-enrolls
the topology; update-install re-enables boot-persistent roles such as BIND.
To retire the publication controller itself, initialize a different current
host against the unchanged complete inventory first, then retire it from there.

Accessing the VE

There are several options for users to access their VE.
- ssh to host, from there to the VE
- ssh to the host and use a container share point - /var/srvctl3/share/containers/VE is bind-mounted read-only into the container
- ssh directly to the VE, for example "ssh charlie_charlie-one.ve_root@192.168.88.13 -p 2222" Note the USER_VE_VEUSER syntax.

Port 2222 is served by sshpiperd (modules/sshpiperd): it splits the composite username on the two underscores, authenticates USER against /var/sshpiper/USER/*.pub plus /var/srvctl3/share/common/authorized_keys, and proxies to VE:22 as VEUSER using USER's mapped private key. Two caveats on a fresh host: update-install installs the unit but never enables or starts it ('sc sshpiperd !' does that), and the vendored /bin/sshpiperd binary is stale - it is built from srvctl 3.1.2.1 and looks for srvctl_id_rsa while srvctl now generates srvctl_id_ecdsa, so key mapping fails until it is rebuilt (modules/sshpiperd/build.sh, itself currently broken). /var/sshpiper is bind-mounted at hook time only, so after a reboot it is empty until the hourly regenerate remounts it.

Mailing is enabled by default, but mailing should be seperated to containers, thus create containers with the mail. subdomain-prefix to have a dedicated MX. Creating mail.DOMAIN switches the MX off on DOMAIN itself; an explicit mx field on the record, or use_gsuite, overrides that.
