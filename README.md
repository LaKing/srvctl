## Srvctl v3 (3.0.127.2)
srvctl is a containerfarm-manager for microsite hosting webservers. It will help to set up, maintain, and to let a couple of servers work together in order to have a solid web-serving service.
Version 3 is remake for 2016 mostly using systemd tools, thus using systemd-nspawn as the containerfarm manager. The core is written in bash and javascript, and a modular design allows to extend it with programs.

How it works:
After installation there should be a main-command available called srvctl or in short sc. This will trigger srvctl scripts, and process srvctl-commands, and their arguments. Goal is to make easy to use, and easy to remember human-friendly command sets for daily usage.  

Installation:
Srvctl 3 is designed for a standard fedora server edition. It may work on similar distros. containers may have other distributions. 
A srvctl host should have glusterfs for data storage. While installing your operating system, create an XFS partition mounted on /glu/srvctl/data
Setting a hostname is mandatory. Needless to say, you mostly have to operate as root. 
As root, clone the repo and create some symlinks for it.
```
    dnf -y install git
    cd /usr/local/share
    git clone https://github.com/LaKing/srvctl.git && bash srvctl/srvctl.sh
     
```

At this point the srvctl command should be ready to be used.
To use srvctl as a containerfarm host, the common configuration data has to be written using the JSON format. You may refer to the example-configs.

    cp -R /usr/local/share/srvctl/example-conf/data /etc/srvctl

Most static configuration files reside in /etc/srvctl
    
```

srvctl COMMAND [arguments]              


COMMAND                                 


COMMAND - from root                     

   custom-command                        A Custom command from root 2017.01.07-12:23:11 
    
     This command does something custom, like running a bash script.
     It might be customized further, depending on the author.
    

COMMAND - from srvctl                   

   add-ve                                Add a fedora container.                        
    
     Generic container for customization.
     Contains basic packages.
    
   destroy-ve                            Delete container with all its files            
    
     Delete all files and all records regarding the VE.
    
   regenerate-rootfs                     Create the container base.                     
    
     Download container filesystems that will be used as base when creating containers.
    
    
   regenerate                            Write all config files with the current settings.
    
     Get all modules to write and overwrite config files with the actual configurations.
    
    
   status                                List container statuses                        
    
    
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
    
   update-install                        Run the installation/update script.            
    
     Update/Install all components
     On host systems install the containerfarm
    
   version                               List software versions installed.              
    
     Contact the package manager, and query important packages
    
    
   add-user                              Add user to the systems                        
    
     Add user to database and create it on the system.
     users will have default passwords, certificates, etc, ..
    
```
