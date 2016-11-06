#!/bin/bash

## run only with srvctl
[[ $SRVCTL ]] || exit 4

root_only || return 244

## @en Run the installation/update script.
## &en Update/Install all components
## &en On host systems install the containerfarm

sc_update

## install mc if we dont have it
[[ -f /bin/mc ]] || sc_install mc
[[ -f /bin/node ]] || sc_install nodejs

## source custom configurations
if [[ ! -f /etc/srvctl/config ]]
then
    cat "$SC_INSTALL_DIR/config" > /etc/srvctl/config
fi

if $SC_ON_HS
then
    msg "srvctl host installation"
    
    ## srvctl3 sudo functions
    sc_install sudo
    echo '## srvctl v3 sudo file' > /etc/sudoers.d/srvctl
    echo 'ALL ALL=(ALL) NOPASSWD: /usr/share/srvctl/srvctl.sh diagnose' >> /etc/sudoers.d/srvctl
    
    ## srvctl3 database
    if ! [[ -f /etc/srvctl/containers.json ]]
    then
        echo '{}' > /etc/srvctl/containers.json
    fi
    
    if ! [[ -f /etc/srvctl/users.json ]]
    then
        echo '{}' > /etc/srvctl/users.json
    fi
    
    ## network configuration
    systemctl is-active network && ntc 'network.service is active'
    systemctl is-active NetworkManager && ntc 'NetworkManager is active'
    
    systemctl enable systemd-networkd
    systemctl start systemd-networkd
    
    msg "It is recommended to create systemd-networkd configurations for ethernet cards."
    networkctl | grep ' en' | grep ether | grep routable | grep unmanaged
    
    ## Recommended way for DNS resolution with systemd
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
    systemctl enable systemd-resolved
    systemctl start systemd-resolved
    
    ###
    msg "Containerfarm host installation"
    ###
    
    ## this option allows machinectl to see our custom machines
    ln -s "$SRV" /var/lib/container
    
    ## disable selinux
    msg 'disabling SELinux'
    echo 'SELINUX=disabled' > /etc/selinux/config
    ## TODO enable it when we are there
    
    sc_install systemd-container
    
    ## CREATE BASE IMAGES
    msg "Create base images"
    mkrootfs_fedora_base fedora "mc httpd mod_ssl openssl postfix mailx sendmail unzip rsync nfs-utils dovecot wget"
    mkrootfs_fedora_base apache "mc httpd mod_ssl openssl unzip rsync nfs-utils"
    mkrootfs_fedora_base codepad "mc httpd mod_ssl openssl postfix mailx sendmail unzip rsync nfs-utils dovecot gzip git-core curl python openssl-devel postgresql-devel wget mariadb-server ShellCheck"
    
fi



