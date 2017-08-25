#!/bin/bash

function gluster_reset { ## datadir
    local datadir
    datadir="$1"
    run gluster volume info
    run umount /srvctl/data
    run gluster volume stop "$datadir" force
    run gluster volume remove-brick "$datadir" "$HOSTNAME:/glu/$datadir/brick" force
    run gluster volume delete "$datadir"
    
    attr -R -r glusterfs.volume-id .
    setfattr -x trusted.glusterfs.volume-id /glu/"$datadir"/brick
    setfattr -x trusted.gfid /glu/"$datadir"/brick
    
    run rm -fr /glu/"$datadir"/brick #/.glusterfs
    run systemctl stop glusterd
    
    ntc "A reboot is required to reset gluster properly."
}

function gluster_install {
    
    sc_install glusterfs-server
    
    ln -sf /etc/ssl/gluster-ca.crt.pem /etc/ssl/glusterfs.ca
    ln -sf /etc/ssl/gluster-server.crt.pem /etc/ssl/glusterfs.pem
    ln -sf /etc/ssl/gluster-server.key.pem /etc/ssl/glusterfs.key
    touch /var/lib/glusterd/secure-access
    firewalld_add_service glusterfs
    
    run systemctl enable glusterd
    run systemctl start glusterd
    run systemctl status glusterd --no-pager
    
    run gluster peer status
}

function gluster_configure { ## datadir mountdir
    
    local datadir mountdir
    datadir="$1"
    mountdir="$2"
    
    if ! systemctl is-active glusterd > /dev/null
    then
        err "gluster inactive"
        return 0
    fi
    
    if [[ -d "/glu/$datadir" ]]
    then
        
        msg "probing gluster peers"
        for host in $(cfg cluster host_list)
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
        for host in $(cfg cluster host_list)
        do
            ip="$(get host "$host" host_ip)"
            hs="$(get host "$host" hostnet)"
            
            if [[ ! -z $ip ]] && [[ ! -z $hs ]]
            then
                list="$list $host:/glu/$datadir/brick"
            fi
        done
        
        lista=( $list )
        
        if ! run gluster volume status "$datadir"
        then
            
            ## /glu/"$datadir"/brick - the existance of this directory prevents volume creation, but attemting to create the volume creates the directory
            if [[ -d "/glu/$datadir/brick" ]] && [[ ! -d "/glu/$datadir/brick/.glusterfs" ]]
            then
                rm -fr /glu/"$datadir"/brick
            fi
            
            msg "start volume $datadir"
            
            # shellcheck disable=SC2086
            if run gluster volume create "$datadir" replica ${#lista[@]} $list force
            then
                
                run gluster volume set "$datadir" client.ssl on
                run gluster volume set "$datadir" server.ssl on
                
                run gluster volume start "$datadir" force
                run gluster volume status "$datadir"
                
                gluster_mount_data "$datadir" "$mountdir"
                return $?
            fi
            
        else
            msg "gluster volume $datadir ok"
            return 0
        fi
        
        ## todo, moumt it permanently
        
        ## okay this command will bring back all bricks, if for some reason one should be offline.
        run gluster volume start "$datadir" force
        
        
    else
        ntc "A srvctl module needs /glu/$datadir for a gluster brick"
        return 1
    fi
}

## running at init
function gluster_mount_data() { ## datadir mountdir
    
    [[ $USER == root ]] || return
    
    local datadir mountdir check
    datadir="$1"
    mountdir="$2" ## SC_DATASTORE_RW_DIR
    
    ## first of all make sure there is a brick
    if [[ ! -d "/glu/$datadir/brick" ]]
    then
        err "There is no brick for $datadir"
        return
    fi
    
    if [[ ! -s /etc/ssl/glusterfs.ca ]]
    then
        err "Missing /etc/ssl/glusterfs.ca"
        return
    fi
    if [[ ! -s /etc/ssl/glusterfs.pem ]]
    then
        err "Missing /etc/ssl/glusterfs.pem"
        return
    fi
    if [[ ! -s /etc/ssl/glusterfs.key ]]
    then
        err "Missing /etc/ssl/glusterfs.key"
        return
    fi
    
    ## make sure all bricks are online
    check="$(gluster volume status "$datadir" | grep 'N/A       N/A        N       N/A')"
    if [[ ! -z "$check" ]]
    then
        
        run gluster volume status "$datadir"
        run gluster volume start "$datadir" force
        eyif
    fi
    
    ## we create the ro bindmount to access data, even if gluster is not working for some reason, files will reside here if they were before
    if mount | grep " on /var/srvctl3/gluster/$datadir" > /dev/null
    then
        debug "The readonly brick for $datadir is mounted"
    else
        run mkdir -p "/var/srvctl3/gluster/$datadir"
        run mount "/glu/$datadir/brick" "/var/srvctl3/gluster/$datadir" -o bind,ro
        run mount "/var/srvctl3/gluster/$datadir" -o remount,ro,bind
    fi
    
    
    ## assumes that datastore is initialized first
    
    if ! mount | grep "$HOSTNAME:/$datadir on $mountdir type fuse.glusterfs" > /dev/null
    then
        run mkdir -p "$mountdir"
        if run mount -t glusterfs  -o log-file="/var/log/gluster-$datadir-mount-$NOW.log" "$HOSTNAME:/$datadir" "$mountdir"
        then
            msg "[ OK ] Gluster mounted $datadir"
        else
            if [[ -f "/var/log/gluster-$datadir-mount-$NOW.log" ]]
            then
                run cat "/var/log/gluster-$datadir-mount-$NOW.log"
            fi
        fi
    fi
    
    if mount | grep "$HOSTNAME:/$datadir on $mountdir type fuse.glusterfs" > /dev/null
    then
        debug "$mountdir is mounted"
        # shellcheck disable=SC2034
        return 0
    else
        err "Could not mount $datadir on $mountdir"
        return 1
    fi
}


