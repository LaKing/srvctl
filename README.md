## Srvctl v3 (3.1.0.8)
Under construction, - srvctl is a containerfarm-manager for microsite hosting webservers with fedora as the host operating system. It will help to set up, maintain, and to let a couple of servers work together in order to have a solid web-serving service.
Version 3 is remake for 2016 mostly using systemd tools, thus using systemd-nspawn as the containerfarm manager. The core is written in bash and javascript, and a modular design allows to extend it with programs. Basically it is a collection of scripts.

How it works:
After installation there should be a main-command available called srvctl or in short sc. This will trigger srvctl scripts, and process srvctl-commands, with their arguments. Goal is to make easy to use, and easy to remember human-friendly command sets for daily usage. Primary goal is managment of a web-hosting server and containerfarm that hosts microsites. 

Installation:
Srvctl 3 is designed for a standard fedora server edition. It may work on similar distros. Containers may use other distributions. 
A srvctl host should have glusterfs for data storage. While installing your operating system, create one extra XFS partition mounted on /glu/srvctl-data, that will store certificates, passwords, and littée other sensitive data. 
Beside that smaller partition create an extra partition, preferably on a seperate drive for data storage, such as static file service or ftp. It should be mounted on /glu/srvtl-storage 
It is advisable to create separate partitions for directories such as /var/log and /home so that the primary root partition wont get full at any time.
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
The so called datastore saves configuration informations, and gluster can be used to sync the data across servers.
Servers can interact with each other over VPN, and containers are on an internal network:

In srvctl3 we use a single class A network 10.x.x.x for communication of containers and hosts.
This network is devided to 16 subnets. netmask: 255.240.0.0 or /12

10.0.0.0 - 10.15.255.255 - reserved for external networks and openvpn connections outside of srvctl
10.16.0.0 - 10.31.255.255 - HOSTNET 1
10.32.0.0 - 10.47.255.255 - HOSTNET 2
...
10.240.0.0 - 10.255.255.255 - HOSTNET 15

Bridges use a 10.b.b.x/24 (255.255.255.0) address space. That means 4080 bridges per hostnet. 

We divide users and assign them to 16 resellers.
That means we can have up to 16 servers, each hosting for 16 resellers.
Resellers have ~250 users on each server. Each user can have ~200 containers on each server.

Therfore IP 10.a.b.c can be calculated as, 
a = HOSTNET * 16 + RESELLER_ID
b = RESELLERS-USER
c = CONTAINER 20..200

Container netblock IP's are assigned as follows:

0: network address
1: host-bridge ip
...
16: host-bridge ip
20: containers
200 containers
201: vpn-clients
250: vpn-clients
255: broadcast address

[...]


Using srvctl

Some applications controlled by srvctl need to use certificates in order to communicate securly. Therefore it is recommended to use a host, or better said dedicate a host as CA.

The update_install process can be, and eventually has to be run over and over. The srvctl scripts generate configuration files.

Experts may run certain functions in context of srvctl, that means with internal variables and settings
    srvctl exec-function SRVCTL_FUNCTION
The main datastore functions may be accessed directly, so instead of writing 
    srvctl exec-function out host t1.test.vm
.. it is possible to write directly
    srvctl out host t1.test.vm

The datastore

Srvctl maintains configuration data in json files. These files may reside at the following locations
/etc/srvctl/data - static configuration files
/var/srvctl3/datastore/ro - readonly, fallback 
/var/srvctl3/datastore/rw - readwrite gluster data volume





```
# 11 @conf /etc/srvctl/debug.conf 
# 13 @conf /etc/srvctl/modules.conf 
# 14 init@run_hook pre-init 
# 18 @hook srvctl pre-init 
# 20 @hook ve pre-init 

srvctl COMMAND [arguments]              


COMMAND                                 


COMMAND - from root                     

   /root/srvctl-includes/custom-command.sh      
   custom-command                        A Custom command from root 2017.01.07-12:23:11 
    
     This command does something custom, like running a bash script.
     It might be customized further, depending on the author.
    

COMMAND - from srvctl                   

   /srv/codepad-project/modules/containers/commands/add-ve.sh
   add-ve                                Add a fedora container.                        
    
     Generic container for customization.
     Contains basic packages.
    
   /srv/codepad-project/modules/containers/commands/destroy-ve.sh
   destroy-ve                            Delete container with all its files            
    
     Delete all files and all records regarding the VE.
    
   /srv/codepad-project/modules/containers/commands/regenerate.sh
   regenerate                            Update configuration settings.                 
    
     Get all modules to write and overwrite config files with the actual configurations.
     The argument all-hosts makes the command perform on all hosts.
     The regenerate rootfs command rebuilds the container base images.
    
    
   /srv/codepad-project/modules/containers/commands/status.sh
   status                                List container statuses                        
    
    
   /srv/codepad-project/modules/srvctl/commands/customize.sh
   customize                             Create/edit a custom command.                  
    
     It is possible to create a custom command in ~/srvctl-includes
     A custom command should have a name, and will contain a blank help:
     This command does something custom, like running a bash script.
     It might be customized further, depending on the author.
    
   /srv/codepad-project/modules/srvctl/commands/diagnose.sh
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
    
   /srv/codepad-project/modules/srvctl/commands/ls.sh
   ls                                    List all files recursive, sorted by last modified date
    
     List all files recursive, sorted by last modified date
    
    
   /srv/codepad-project/modules/srvctl/commands/update-install.sh
   update-install                        Run the installation/update script.            
    
     Update/Install all components
     On host systems install the containerfarm
    
   /srv/codepad-project/modules/srvctl/commands/version.sh
   version                               List software versions installed.              
    
     Contact the package manager, and query important packages
    
    
   /srv/codepad-project/modules/users/commands/add-reseller.sh
   add-reseller                          Add user to the systems                        
    
     Add user to database and create it on the system.
     users will have default passwords, certificates, etc, ..
    
   /srv/codepad-project/modules/users/commands/add-user.sh
   add-user                              Add user to the systems                        
    
     Add user to database and create it on the system.
     users will have default passwords, certificates, etc, ..
    
   /srv/codepad-project/modules/ve/commands/status.sh
   status                                List container status parameters               
    
    
# 93 srvctl-3.1.0.8 
```
