## Srvctl v3 (3.0.98.8)
A remake for 2016 mostly using systemd tools
```

srvctl COMMAND [arguments]              


COMMAND                                 


COMMAND - from root                     

   convert                               A Custom command from root 2016.11.01-02:05:30 
    
     This command does something custom, like running a bash script.
     It might be customized further, depending on the author.
    
   sandbox                               A Custom command from  2016.11.01-23:49:16     
    
     This command does something custom, like running a bash script.
     It might be customized further, depending on the author.
    

COMMAND - from srvctl                   

   add-ve                                Add a fedora container.                        
    
     Generic container for customization.
     Contains basic packages.
    
   adjust-service                        status / start|stop|kill|restart(enable|remove) or ? / +|-|!
    
     This is a shorthand syntax for frequent operations on systemd.
     the following are equivalent:
             systemctl status example.service
             sc example ?
     to query a service with the supershort operator "?" or with "status"
     to restart and enable a service the operator is "!" or "restart"
     to start and enable a service the operator is "+" or "start"
     to stop and disable a service the operator is "-" or "stop"
    
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
    
    
```
