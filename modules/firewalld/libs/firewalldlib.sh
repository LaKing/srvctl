#!bin/bash

function firewalld_add_service() { ## name proto port hint
    
    systemctl start firewalld.service
    
    local zone name proto port
    
    name="$1"
    proto="$2"
    port="$3"
    hint="$4"
    
    if ! [[ $hint ]]
    then
        hint="$SC_USER"
    fi
    
    zone=$(firewall-cmd --get-default-zone)
    
    if [[ "$(firewall-cmd --zone="$zone" --permanent --query-service="$name")" == yes ]]
    then
        ntc "firewalld: $name is enabled already."
        return
    fi
    
    if [[ -f /usr/lib/firewalld/services/$name.xml ]] && [[ -z $proto ]] && [[ -z $port ]]
    then
        msg "Service $name already defined in firewalld"
        run firewall-cmd  --zone="$zone" --permanent --add-service="$name"
    else
        msg "Creating /etc/firewalld/services/$name.xml"
        
cat > "/etc/firewalld/services/$name.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>$name</short>
  <description>$name $proto $port (srvctl added for $hint)</description>
  <port protocol="$proto" port="$port"/>
</service>
EOF
        
        run firewall-cmd --reload
        run firewall-cmd --zone="$zone" --permanent --add-service="$name"
    fi
    
    run firewall-cmd --reload
    
}

function firewalld_offline_add_service() { ## name proto port ## must be called with a hook
    
    local zone rootfs name proto port
    
    ## rootfs_base comes from parent containers mkrootfslib: mkrootfs_fedora_base
    # shellcheck disable=SC2154
    rootfs="$rootfs_base"
    name="$1"
    proto="$2"
    port="$3"
    
    msg "firewalld_offline_add_service $rootfs $name $proto $port"
    zone=$(chroot "$rootfs" firewall-offline-cmd --get-default-zone)
    
    if [[ "$(chroot "$rootfs" firewall-offline-cmd --zone="$zone" --query-service="$name")" == yes ]]
    then
        ntc "firewalld-offline: $name is enabled already."
        return
    fi
    
    if [[ -f $rootfs/usr/lib/firewalld/services/$name.xml ]] && [[ -z $proto ]] && [[ -z $port ]]
    then
        msg "Service $name defined in firewalld"
        run chroot "$rootfs" firewall-offline-cmd  --zone="$zone" --add-service="$name"
    else
        msg "Creating $rootfs/etc/firewalld/services/$name.xml"
        
cat > "$rootfs/etc/firewalld/services/$name.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>$name</short>
  <description>$name $proto $port (added by srvctl)</description>
  <port protocol="$proto" port="$port"/>
</service>
EOF
        
        run chroot "$rootfs" firewall-offline-cmd --zone="$zone" --add-service="$name"
    fi
    
}
