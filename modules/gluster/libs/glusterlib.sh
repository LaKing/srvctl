#!/bin/bash

function gluster_reset {
    run gluster volume info
    run umount /srvctl/data
    run gluster volume stop srvctl-data force
    run gluster volume remove-brick srvctl-data "$HOSTNAME:/glu/srvctl-data/brick" force
    run gluster volume delete srvctl-data
    
    attr -R -r glusterfs.volume-id .
    setfattr -x trusted.glusterfs.volume-id /glu/srvctl-data/brick
    setfattr -x trusted.gfid /glu/srvctl-data/brick
    
    run rm -fr /glu/srvctl-data/brick #/.glusterfs
    run systemctl stop glusterd
    
    ntc "A reboot is required to reset gluster properly."
}

function gluster_configure {
    
    if [[ -d /glu/srvctl-data ]]
    then
        
        mkdir -p /glu/srvctl-data
        
        sc_install glusterfs-server
        
        firewalld_add_service glusterfs
        
        run systemctl enable glusterd
        run systemctl start glusterd
        run systemctl status glusterd --no-pager
        
        ln -sf /etc/ssl/gluster-ca.crt.pem /etc/ssl/glusterfs.ca
        ln -sf /etc/ssl/gluster-server.crt.pem /etc/ssl/glusterfs.pem
        ln -sf /etc/ssl/gluster-server.key.pem /etc/ssl/glusterfs.key
        
        run gluster peer status
        
        msg "probing for new peers"
        for host in $(cfg system host_list)
        do
            ip="$(get host "$host" host_ip)"
            hs="$(get host "$host" hostnet)"
            
            if [[ ! -z $ip ]] && [[ ! -z $hs ]] && [[ $host != "$HOSTNAME" ]]
            then
                run gluster peer probe "$host"
            fi
        done
        
        run gluster peer status
        
        ## /data/brick is /glu/brick
        ## we want to mount srvctl managed clusters in /srvctl
        
        local list lista
        list=''
        for host in $(cfg system host_list)
        do
            ip="$(get host "$host" host_ip)"
            hs="$(get host "$host" hostnet)"
            
            if [[ ! -z $ip ]] && [[ ! -z $hs ]]
            then
                list="$list $host:/glu/srvctl-data/brick"
            fi
        done
        
        lista=( $list )
        
        if ! run gluster volume status srvctl-data
        then
            
            # shellcheck disable=SC2086
            run gluster volume create srvctl-data replica ${#lista[@]} $list
            
            run gluster volume set srvctl-data client.ssl on
            run gluster volume set srvctl-data server.ssl on
            
            run gluster volume start srvctl-data force
            run gluster volume status srvctl-data
            
            gluster_mount_data
        fi
        ## todo, moumt it permanently
        
        
    else
        ntc "A proper srvctl containerfarm host-installation needs a seperate partition mounted at /glu/srvctl-data for a gluster brick"
    fi
}

function gluster_mount_data() {
    
    run mkdir -p /srvctl/data
    if ! run mount -t glusterfs  -o log-file="/var/log/gluster-mount-$NOW.log" "$HOSTNAME:/srvctl-data" "/srvctl/data"
    then
        if [[ -f "/var/log/gluster-mount-$NOW.log" ]]
        then
            cat "/var/log/gluster-mount-$NOW.log"
        fi
    fi
}


