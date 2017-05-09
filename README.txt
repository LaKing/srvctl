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
    
