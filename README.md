## Srvctl v3 (3.0.126.5)
A remake for 2016 mostly using systemd tools
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
