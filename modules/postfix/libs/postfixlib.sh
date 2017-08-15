#!/bin/bash

function regenerate_etc_postfix_relaydomains() {
    if [[ -d /etc/postfix/ ]]
    then
        cfg cluster postfix_relaydomains
    fi
}

function write_ve_postfix_main {
    
    local container to cf isMX hasMX
    
    container="$1"
    to=/dev/null
    cf=/dev/null
    isMX=false
    hasMX=false
    
    
    if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
    then
        to="/etc/postfix/srvctl.main.cf"
        cf="/etc/postfix/main.cf"
    else
        to="/srv/$container/rootfs/etc/postfix/srvctl.main.cf"
        cf="/srv/$container/rootfs/etc/postfix/main.cf"
    fi
    
    if [ "${container:0:5}" == "mail." ]
    then
        isMX=true
        hasMX=true
    fi
    
    if [ -d "/srv/mail.$container/rootfs" ]
    then
        hasMX=true
    fi
    
    ## TODO test.$myhostname, dev.$myhostname, sys.$myhostname, www.$myhostname, log, .. etc
    {
        echo "#srvctl $SRVCTL"
        cat "$SC_INSTALL_DIR/modules/postfix/conf/ve-main.cf"
        
        echo "# INTERNET OR INTRANET"
        echo "relayhost = 10.$((SC_HOSTNET * 16)).0.1"
        
    } >> "$to"
    
    if $hasMX
    then
        
        if $isMX
        then
            ## this is mail.
            {
                echo "## we need to change myhostname"
                echo "myorigin = ${container:5}"
                
                echo '## set localhost.localdomain in mydestination to enable local mail delivery'
                # shellcheck disable=SC2016
                echo 'mydestination = $myhostname, '"${container:5}"', localhost, localhost.localdomain'
            } >> "$to"
            
        else
            ## this is not the mail
            {
                echo '## set localhost.localdomain in mydestination to enable local mail delivery'
                echo 'mydestination = localhost, localhost.localdomain'
                
            } >> "$to"
        fi
        
    else
        
        ## no seperate mail.
        {
            echo '## set localhost.localdomain in mydestination to enable local mail delivery'
            # shellcheck disable=SC2016
            echo 'mydestination = $myhostname, mail.$myhostname, localhost, localhost.localdomain'
        } >> "$to"
        
    fi
    
    if [[ -f "$cf" ]]
    then
        if ! cmp "$to" "$cf" >/dev/null 2>&1
        then
            ntc "Postfix configuration update on $container"
            cat "$cf" > "$cf.$NOW.bak"
            cat "$to" > "$cf"
        fi
    else
        cat "$to" > "$cf"
    fi
    
    #rm -rf $to
}
