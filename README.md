## Srvctl v3 (3.2.3.4)
Under construction, - srvctl is a containerfarm-manager for microsite hosting webservers with fedora as the host operating system. It will help to set up, maintain, and to let a couple of servers work together in order to have solid web-serving services.
Version 3 is remake in core mostly using systemd tools, thus using systemd-nspawn as the containerfarm manager. Written in the mix of bash and javascript, a modular design allows to extend it with programs. Basically it is a collection of scripts, and fast scripts.

How it works:
After installation there should be a main-command available called srvctl or in short sc. This will trigger srvctl scripts, and process srvctl-commands, with their arguments. Goal is to make easy to use, and easy to remember human-friendly command sets for daily usage. Primary goal is managment of a web-hosting server and containerfarm that hosts microsites. 

Installation:
Srvctl 3 is designed for a standard fedora server edition. It may work on similar distros. Containers may use other distributions. 
A srvctl host as part of a cluster should have glusterfs for data storage. While installing your operating system, create:
- 2GiB XFS partition mounted on /glu/srvctl-data, that will store certificates, passwords, and other sensitive data. 
- 500GiB XFS partition mounted on /glu/srvtl-storage, preferably on a seperate drive for data storage, such as static file service or ftp.
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
To use srvctl as a containerfarm host, the common configuration data has to be written using the JSON format. You may refer to the example-configs.

    cp -R /usr/local/share/srvctl/example-conf/data /etc/srvctl

Most static configuration files reside in /etc/srvctl. Data is stored in BASH formatted, sourcable variable description files, and in JSON files.
The datastore module saves configuration informations, and gluster can be used to sync the data across servers.
Servers can interact with each other over VPN, and containers are on an internal network:

In srvctl3 we use a single class A network 10.x.x.x for communication of containers and hosts.
Each server has to have a unique HOSTNET id between 16..255 for the server cluster.
By convention, each host should be prefixed with a two digit host identifier in your company domain hostname.

10.0.0.0 - 10.14.255.255 - reserved for external networks and openvpn connections outside of srvctl
10.15.x.y - reserved for openvpn hostnet-network - connections from host to host. Openvpn connections created from every server to every server, thus x is the server hostnet y the client hostnet on a particlar host. 

We can divide users and assign them to resellers, so we should.


Using srvctl

Some applications controlled by srvctl need to use certificates in order to communicate securly. Therefore it is recommended to use a host, or better said dedicate a host as CA.

The update_install process can be, and eventually has to be run over and over. The srvctl scripts generate configuration files.

Experts may run certain functions in the context of srvctl, that means with internal variables and settings
    srvctl exec-function SRVCTL_FUNCTION

The main datastore functions may be accessed directly, so instead of writing 
    srvctl exec-function out host t1.test.vm
.. it is possible to write directly
    srvctl out host t1.test.vm

The datastore

Srvctl maintains configuration data in json files. These files may reside at the following locations
/etc/srvctl/data - static configuration files
/var/srvctl3/datastore - readwrite gluster data volume (/var/srvctl3/gluster/srvctl-data as readonly fallback)

Accessing the VE

There are several options for users to access their VE.
- ssh to host, from there to the VE
- ssh to the host and use a container share point
- ssh directly to the VE, for example "ssh charlie_charlie-one.ve_root@192.168.88.13 -p 2222" Note the USER_VE_VEUSER syntax.

Mailing is enabled by default, but mailing should be seperated to containers, thus create containers with the mail. subdomain-prefix to have a dedicated MX.



```

srvctl COMMAND [arguments]              


COMMAND                                 

   add-codepad                           Add a codepad fedora container.                
    
     Generic container for software developmen.
     Contains all packages for collaborative software development.
    
   add-fedora                            Add a fedora container.                        
    
     Generic container for customization.
     Contains basic packages.
    
   add-mail                              Add a mailing container.                       
    
     Mail container for pop3/imap6smtp access.
     Contains dovecot, postfix.
    
   add-ve                                Add a standard fedora container, alias of add-fedora
    
     Generic container for customization.
     This command is an alias for add-fedora.
    
   destroy-ve                            Delete container with all its files            
    
     Delete all files and all records regarding the VE.
    
   exec-all                              Execute a command on all running containers.   
    
     In some cases it might come handy to run a single command on all containers.
    
   map-port                              Map a tcp port to the host.                    
    
     Mapping container tcp or udp ports directly to the host.
     Port number must be between 1 and 65535
    
   regenerate                            Update configuration settings.                 
    
     Get all modules to write and overwrite config files with the actual configurations.
     The argument all-hosts makes the command perform on all hosts.
     The regenerate rootfs command rebuilds the container base images.
    
    
   status                                List container statuses                        
    
    
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
    
   install-odoo                          Run scripts that install odoo community and it's basic dependencies.
    
     Install the odoo ERP and CRM system.
     Community version, installer by m1r0.
    
   fix-saslauthd                         restart saslauthd                              
    
     This command restarts saslauthd to fix mailing.
     It is temporary..
    
   customize                             Create/edit a custom command.                  
    
     It is possible to create a custom command in ~/srvctl-includes
     A custom command should have a name, and will contain a blank help:
     This command does something custom, like running a bash script.
     It might be customized further, depending on the author.
    
   diagnose                              First-aid diagnoistic command.                 
    
     Set of troubleshooting commands, that include information about:
    
         srvctl version and variables
         uptime
         system/kernel version
         boot configs
         inactive services listed in srvctl
         postfix fatal errors since yesterday
         the mail que
         firewall settings
         table of processes
         connected shell users
    
     Notes
         To flush the mail que, use: postqueue -f
         To remove all mail from the mail que use: postsuper -d ALL
    
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
    
   status                                List container status parameters               
    
    
   install-wordpress                     Run scripts that install wordpress and it's basic dependencies.
    
     Install the wordpress dependencies.
    
    
[ srvctl-devel ] ## srvctl-3.2.3.4
```
