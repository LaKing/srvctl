## Srvctl v4 (4.0.0.8)
Under construction, - srvctl is a containerfarm-manager for microsite hosting webservers with fedora as the host operating system. It will help to set up, maintain, and to let a couple of servers work together in order to have solid web-serving services.
Version 3 was the remake in core mostly using systemd tools, thus using systemd-nspawn as the containerfarm manager. Version 4 continues on that base, with the datastore, the runtime and the permission model reworked. Written in the mix of bash and javascript, a modular design allows to extend it with programs. Basically it is a collection of scripts, and fast scripts.
The authoritative version string is the `version` file in the repo root, currently 4.0.0.8. The "3" in runtime paths like /var/srvctl3 is a directory name, not a version claim - those paths are unchanged in v4.

How it works:
After installation there should be a main-command available called srvctl or in short sc. This will trigger srvctl scripts, and process srvctl-commands, with their arguments. Goal is to make easy to use, and easy to remember human-friendly command sets for daily usage. Primary goal is managment of a web-hosting server and containerfarm that hosts microsites. 

Installation:
Srvctl 4 is designed for a standard fedora server edition. It may work on similar distros. Containers may use other distributions. 
A srvctl host as part of a cluster was meant to have glusterfs for data storage. While installing your operating system, create:
- 2GiB XFS partition mounted on /glu/srvctl-data, that will store certificates, passwords, and other sensitive data. 
- 500GiB XFS partition mounted on /glu/srvctl-storage, preferably on a seperate drive for data storage, such as static file service or ftp.
- /var/log 
- /home, separate partitions for directories so that the primary root partition wont get full at any time. 
- /srv, this will be our main directory for containers, therefore it should be a big and fast SSD.

Those two are brick locations, not mountpoints: the gluster module puts the brick in /glu/DATADIR/brick, bind-mounts it read-only on /var/srvctl3/gluster/DATADIR and fuse-mounts the volume (srvctl-data, srvctl-storage) on /var/srvctl3/datastore and /var/srvctl3/storage. Be aware that the module is hard-disabled at this version: every branch of modules/gluster/module-condition.sh echoes false, including the one that has passed all checks (the "#echo true" line kept next to it is the record of the kill-switch). Nothing therefore creates, mounts or replicates a volume, /var/srvctl3/gluster/* stays empty, and both trees live on local disk. Create the partitions anyway if you expect the module to come back.

Users and UID/GID numbers have to be consistent across the clustered servers, therefore, don't create any users outside of srvctl. 
Setting a hostname is mandatory. Needless to say, you mostly have to operate as root. Also, correct DNS entries (forward and reverse) and NTP are essential.

As root, clone the repo and run it once; on the standard path srvctl.sh creates the /bin/sc and /bin/srvctl symlinks and the /etc/bash_completion.d/srvctl-completion link by itself (init.sh), there is nothing to link by hand. Node.js is needed as well - the datastore, the help index and the config tooling all shell out to /bin/node.
```
    dnf -y install git nodejs
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
The files under /etc/srvctl/data are seeds: on `srvctl update-install` (and
`test-modules`) init.sh copies every /etc/srvctl/data/*.conf to
/etc/srvctl/*.conf, and it is that copy which gets sourced on every run.

Most static configuration files reside in /etc/srvctl. Data is stored in BASH formatted, sourcable variable description files, and in JSON files.
The datastore module saves configuration informations, and gluster was the way to sync the data across servers - with that module disabled every host keeps its own copy under /var/srvctl3/datastore.
Servers can interact with each other over VPN, and containers are on an internal network:

For its internal traffic - containers, and hosts talking to each other - srvctl3 uses the single class A network 10.x.x.x. That is on top of the ordinary LAN or public address of the machine (host_ip in clusters.json, 192.168.88.13 in the ssh example further down), which is what sshd, sshpiperd and haproxy listen on and what the outside world connects to.
Each server has to have a unique HOSTNET id between 16..255 for the server cluster. Nothing enforces that range: the cluster-config validator checks key names and reserved keys only, so an out-of-range, duplicate or missing hostnet is accepted and simply yields colliding or unroutable addresses.
By convention, each host should be prefixed with a two digit host identifier in your company domain hostname.

10.0.0.0 - 10.14.255.255 - reserved for external networks and openvpn connections outside of srvctl
10.15.x.y - reserved for openvpn hostnet-network - connections from host to host. Openvpn connections created from every server to every server, thus x is the server hostnet y the client hostnet on a particlar host. 
10.HOSTNET.USER_ID.N - containers. The second octet is the hostnet of the host running the VE, the third is the owning user's user_id, so a container address tells you both its host and its owner.

We can divide users and assign them to resellers, so we should.


Using srvctl

Some applications controlled by srvctl need to use certificates in order to communicate securly. Therefore it is recommended to use a host, or better said dedicate a host as CA.

The update-install process can be, and eventually has to be run over and over. The srvctl scripts generate configuration files.

Experts may run certain functions in the context of srvctl, that means with internal variables and settings
    srvctl exec-function SRVCTL_FUNCTION

exec-function is dispatched for genuine root only - SC_USER root AND uid 0 - so it is not reachable by running srvctl under sudo from an ordinary account.

The main datastore functions may be accessed directly, so instead of writing 
    srvctl exec-function out host t1.test.vm
.. it is possible to write directly
    srvctl out host t1.test.vm

The read verbs get and out are open to any caller; the writing verbs new, put, cfg, del and add need root as well.

The datastore

Srvctl maintains configuration data in json files. Cluster topology has one
canonical path on each host: /etc/srvctl/clusters.json. It must be identical on
all hosts and must not be copied into /etc/srvctl/data or /var.
/etc/srvctl/data - non-topology static configuration seeds
/var/srvctl3/host - generated per-host projection of the topology (host.conf, hosts.json); regenerated by srvctl, never edit
/var/srvctl3/datastore - the readwrite datastore (SC_DATASTORE_RW_DIR), also the mountpoint of the srvctl-data gluster volume when that module is on
/var/srvctl3/gluster/srvctl-data - the readonly fallback (SC_DATASTORE_RO_DIR); it is only ever populated by the gluster module, so at this version the readwrite directory is always the one in use

On the first upgrade to fail-closed topology publication, deploy the same
srvctl version to every configured host while the canonical file still lists
the complete deployed inventory, then run:

```
srvctl exec-function initialize_cluster_publication confirm-complete-inventory
```

Do this before removing or renaming any host: initialization can verify the
hosts still listed, but cannot discover one already deleted from the first
baseline. The publication manifest stores only the verified canonical SHA-256
and ordered hostnames, never a second topology copy. It lives on the host that
ran the initialization - that host is the publication controller - as
/var/srvctl3/cluster-config/publication/publication-inventory.v1 (the directory
is overridable with SC_CLUSTER_PUBLICATION_STATE_DIR), with retirement receipts
beside it in retired/HOST.sha256.

For normal changes, edit `/etc/srvctl/clusters.json`, run
`srvctl exec-function publish_data`, then `srvctl regenerate all-hosts`.
Before removing or renaming `OLDHOST`, drain its workloads and, while it still
answers under that hostname, run from the same publication controller that
initialized and owns the manifest (never from `OLDHOST` itself):

```
srvctl exec-function retire_cluster_host OLDHOST confirm-decommissioned
```

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
- ssh to the host and use a container share point
- ssh directly to the VE, for example "ssh charlie_charlie-one.ve_root@192.168.88.13 -p 2222" Note the USER_VE_VEUSER syntax. The address is the host's own LAN/public address, never a 10.x one; port 2222 is sshpiperd, which splits the composite username on the underscores and proxies the session to VEUSER@VE:22 (modules/sshpiperd/workingdir.go).

That third option needs attention on a fresh host: update-install deploys /bin/sshpiperd, its unit and the tcp/2222 firewalld service, but never enables or starts it (use `sc sshpiperd !`), and the vendored binary is a stale build that still reads <user>/srvctl_id_rsa while srvctl writes srvctl_id_ecdsa - see the FIXME notes in modules/sshpiperd/hooks/update-install-host.sh.

Mailing is enabled by default, but mailing should be seperated to containers, thus create containers with the mail. subdomain-prefix to have a dedicated MX. Creating mail.VE switches the MX off on VE itself automatically; an explicit mx field or use_gsuite on the container record overrides both.

The listing below is the output of "srvctl help" at this version. That full listing deliberately applies neither the module-enabled filter nor the permission filter (see the FIXME in help_commands, commonlib.sh), so it documents every shipped command file, including ones inactive or root-only on the machine you type it on - which is why add-user and status each appear twice, once from usersonhost and containers, once from usersonve and ve. A bare "sc" prints the filtered list instead, with each command's argument syntax.
The texts come from the command files themselves, so a stale help line is reproduced verbatim here: remove-ve does not write a 7z archive into home/.srvctl any more, it rsyncs /srv/VE to $SC_BACKUP_PATH/srvctl-containers/VE/TIMESTAMP (default /backup), and remote backups over SC_BACKUP_HOST are broken at this version.

```

srvctl COMMAND [arguments]              


COMMAND                                 

   add-codepad                           Add a fedora container with codepad preinstalled.
    
     Codepad container for software development.
     Contains the collaborative software development environment.
    
   add-network-ve                        Add a VE for a application in a container on br-BRIDGE.
    
     Networking will be based on a DHCP client
    
   add-ve                                Add a VE under a domain name, by instantiating from TYPE
    
     Generic container for customization.
     Contains basic packages.
    
   add-ve-user                           Add user to the current cluster                
    
     Create the user in the current cluster datastore and create it on the system.
     users will have default passwords, certificates, etc, ..
    
   backup-ve                             backup container with all its files            
    
     Create a system-backup of the container
    
   destroy-ve                            Delete container with all its files            
    
     Delete all files and all records regarding the VE.
    
   exec-all                              Execute a command on all running containers.   
    
     In some cases it might come handy to run a single command on all containers.
    
   map-port                              Map a tcp port to the host.                    
    
     Mapping container tcp or udp ports directly to the host.
     Port number must be between 1 and 65535
    
   recreate-ve                           Recreate the rootfs                            
    
     The rootfs is removed, recreated, and user-data restored as good as possible
    
   regenerate                            Update configuration settings.                 
    
     Get all modules to write and overwrite config files with the actual configurations.
     The argument all-hosts makes the command perform on all hosts.
     The regenerate rootfs command rebuilds the container base images.
    
    
   remove-ve                             Remove container with all its files            
    
     All files will be in a 7z format archive in the users home/.srvctl directory.
    
   status                                List container statuses                        
    
    
   update-ve                             Update container operating system              
    
     The distro will be update with it's package manager.
    
   http-redirect                         Redirect http traffic of a given VE to a given URL or protocol
    
     Place a redirect rule on the VE within the proxy configuration. IPv4 only, on the default port.
     The URL should contain the protocol and/or the domain name.
     If neither a keyword nor an URL is given the redirect is removed.
     If the keyword is 'none' the redirect is removed as well.
    
   https-redirect                        Redirect https traffic of a given VE to a given URL or protocol
    
     Place a redirect rule on the VE within the proxy configuration. IPv4 only, on the default port.
     The URL should contain the protocol and/or the domain name.
     If neither a keyword nor an URL is given the redirect is removed.
     If the keyword is 'none' the redirect is removed as well.
    
   override-in-address                   Override the IN A of the container in named DNS server zone file
    
     Temporary redirect the IN A record.
    
   install-odoo                          Run scripts that install odoo community and it's basic dependencies.
    
     Install the odoo ERP and CRM system.
     Community version, installer by m1r0.
    
   fix-saslauthd                         restart saslauthd                              
    
     This command restarts saslauthd to fix mailing.
     It is temporary..
    
   testsaslauthd                         test a given user of a container for email-functionality
    
     This command runs the testsaslauthd command, with the password automatically filled in..
    
   customize                             Create/edit a custom command.                  
    
     It is possible to create a custom command in ~/srvctl-includes
     A custom command should have a name, and will contain a blank help:
     This command does something custom, like running a bash script.
     It might be customized further, depending on the author.
    
   diagnose                              First-aid diagnostic command.                  
    
     Set of troubleshooting commands, that include information about:
    
         srvctl version and variables
         uptime
         system/kernel version
         boot configs
         inactive services listed in srvctl
         postfix fatal errors since yesterday
         the mail queue
         firewall settings
         table of processes
         connected shell users
    
     Notes
         To flush the mail queue, use: postqueue -f
         To remove all mail from the mail queue use: postsuper -d ALL
    
   fix-owner                             Set user and group on all content to parent owner.
    
     Useful for transfers of files across systems.
     Recursive chown based on parent directory.
    
   fix-sshd                              Fixing sshd permissions on keyfiles.           
    
     A temporary script to fix sshd permissions on keyfiles.
    
   ls                                    List all files recursive, sorted by last modified date
    
     List all files recursive, sorted by last modified date
    
    
   update-install                        Run the installation/update script.            
    
     Update/Install all components.
     On host systems install the containerfarm. and additionally use [HOSTNAME] as additional argument to select a host from a cluster.
    
   version                               List software versions installed.              
    
     Contact the package manager, and query important packages
    
    
   add-publickey                         Add an ssh publickey to the current cluster    
    
     Create the file as user defined publickey in the current cluster datastore and save it on the system.
     Without argiument, the command will open the mcedit program, so the key can be pasted inside.
    
   add-reseller                          Add user as reseller to the host cluster       
    
     Add user to the current cluster datastore and create it on the system.
     users will have default passwords, certificates, etc, ..
    
   add-user                              Add user to the current cluster                
    
     Create the user in the current cluster datastore and create it on the system.
     users will have default passwords, certificates, etc, ..
    
   change-user                           Move container to a different user             
    
     Move container to be owned by a different user. This invoves a change in the IP adress, thus requires a restart of the container.
    
   add-user                              Add user to the container                      
    
     Add user to the container, so that they have their own files, email accouns, and so on.
     users will have a default password, and a directory structure in the container home.
    
   add-zerotier                          Install ZeroTier and add a network             
    
     You can access the container over your ZeroTier network
    
   install-crossover                     Crossover/wine for user x with VNC and ratpoison
    
     You can access the application over phones and mobile devices over VNC
    
   install-qlcplus                       QLC+ light controller for dmx on artnet        
    
     Controll lighting over the network
    
   vnc-desktop                           Add user x with a virtual desktop:0 with gnome, ratpoison, ...
    
     Create a workspace with VNC server as a remote desktop.
     The argument can be used to specify a desktop type. Run ls /usr/share/xsessions to see available desktops after installation.
      gnome | LXDE | awesome | budgie-desktop | cinnamon | cinnamon2d | gnome-classic | i3 | lxqt | mate | openbox | ratpoison | xfce | xmonad | fluxbox
    
   status                                List container status parameters               
    
    
   add-vnc-user                          Add user to the vnc server                     
    
     Create the user for remote vnc access.
     use name, email, phone number
    
   install-wordpress                     Run scripts that install wordpress and it's basic dependencies.
    
     Install the wordpress dependencies.
    
    
[ srvctl-devel ] ## srvctl-4.0.0.8
```
