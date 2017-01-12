#!/bin/bash

function regenerate_pound_conf {
    
    msg "Regenerate pound configs."
    
    pound_init
    
    local container_list
    container_list="$(cfg system container_list)"
    
    for C in $container_list
    do
        pound_make_config "$C"
    done
    
    restart_pound
}

function pound_init_cfg {
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/$HOSTNAME/http-$1.cfg"
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/$HOSTNAME/https-$1.cfg"
}

function pound_init_add_include { ## file-to-include file-to-add-to
    echo "Include \"/var/pound/$HOSTNAME/http-$1.cfg\"" >> "/var/pound/$HOSTNAME/http-$2.cfg"
    echo "Include \"/var/pound/$HOSTNAME/https-$1.cfg\"" >> "/var/pound/$HOSTNAME/https-$2.cfg"
}

function pound_init {
    
    rm -rf "/var/pound"
    mkdir -p "/var/pound/$HOSTNAME"
    
    ## We will use a sort of layering, with up to 8 layers.
    
    ## We assume that /etc/pound.cfg has two includes ...
    pound_init_cfg includes
    
    ## certificates only for https
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/$HOSTNAME/https-certificates.cfg"
    
    pound_init_cfg domains
    pound_init_cfg dddn-domains
    pound_init_cfg wildcard
    
    ## the number is the count of dots.
    ## with this we try to catch misstyped domains where possible - using wildcards
    ## and redirect them ...
    
    pound_init_cfg 8-domains
    pound_init_cfg 7-domains
    pound_init_cfg 6-domains
    pound_init_cfg 5-domains
    pound_init_cfg 4-domains
    pound_init_cfg 3-domains
    pound_init_cfg 2-domains
    pound_init_cfg 1-domains
    
    pound_init_add_include domains includes
    pound_init_add_include dddn-domains includes
    
    pound_init_add_include 8-domains wildcard
    pound_init_add_include 7-domains wildcard
    pound_init_add_include 6-domains wildcard
    pound_init_add_include 5-domains wildcard
    pound_init_add_include 4-domains wildcard
    pound_init_add_include 3-domains wildcard
    pound_init_add_include 2-domains wildcard
    pound_init_add_include 1-domains wildcard
    
    ## first of all, set up the acme server
    echo '## srvctl generated letsencrypt responder
        Service
            URL "^/.well-known/acme-challenge/*"
            BackEnd
                Address localhost
                Port    1028
            End
        End
    ' > /var/pound/acme-server.cfg
    
    echo '## srvctl generated letsencrypt responder
        Service
            URL "^/.well-known/autoconfig/mail/config-v1.1.xml"
            BackEnd
                Address localhost
                Port    1029
            End
        End
    ' > /var/pound/mozilla-autoconfig-server.cfg
    
    
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/http-includes.cfg"
    echo 'Include "/var/pound/acme-server.cfg"' >> "/var/pound/http-includes.cfg"
    echo 'Include "/var/pound/mozilla-autoconfig-server.cfg"' >> "/var/pound/http-includes.cfg"
    
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/http-wildcard.cfg"
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/https-certificates.cfg"
    
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/https-includes.cfg"
    echo 'Include "/var/pound/https-certificates.cfg"' >> "/var/pound/https-includes.cfg"
    
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/https-wildcard.cfg"
    echo 'Include "/var/pound/server-certificates.cfg"' >> "/var/pound/https-certificates.cfg"
    
    local hosts
    hosts="$(cfg system host_list)"
    for H in $hosts
    do
        echo "Include \"/var/pound/$HOSTNAME/http-includes.cfg\"" >> "/var/pound/$HOSTNAME/http-includes.cfg"
        echo "Include \"/var/pound/$HOSTNAME/http-wildcard.cfg\"" >> "/var/pound/$HOSTNAME/http-wildcard.cfg"
        
        echo "Include \"/var/pound/$HOSTNAME/https-certificates.cfg\"" >> "/var/pound/$HOSTNAME/https-certificates.cfg"
        echo "Include \"/var/pound/$HOSTNAME/https-includes.cfg\"" >> "/var/pound/$HOSTNAME/https-includes.cfg"
        echo "Include \"/var/pound/$HOSTNAME/https-wildcard.cfg\"" >> "/var/pound/$HOSTNAME/https-wildcard.cfg"
    done
    
    echo 'Include "/var/pound/http-wildcard.cfg"' >> "/var/pound/http-includes.cfg"
    echo 'Include "/var/pound/https-wildcard.cfg"' >> "/var/pound/https-includes.cfg"
    
    echo "## srvctl $HOSTNAME generated $NOW" > "/var/pound/server-certificates.cfg"
    
    ## server certificates
    for S in /etc/srvctl/cert/*
    do
        if [[ -f $S/cert.pem ]]
        then
            echo "Cert \"$S/cert.pem\"" >> "/var/pound/server-certificates.cfg"
        fi
    done
    
}

function pound_make_service_config { # host-header address http-port https-port cfg
    ## this is a procedure, we take variables from the one calling
    
cat > "$cfg_file.http-service.cfg" << EOF
    Service
        HeadRequire "Host: $host_header"
        BackEnd
            Address $C
            Port    $http_port
            TimeOut 300
        End
        Emergency
            Address 127.0.0.1
            Port 1280
        End
    End
EOF
    
cat > "$cfg_file.https-service.cfg" << EOF
    Service
        HeadRequire "Host: $host_header"
        BackEnd
            Address $C
            Port    $https_port
            TimeOut 300
            HTTPS
        End
        Emergency
            Address 127.0.0.1
            Port 1280
        End
    End
EOF
    
    echo "Include \"$cfg_file.http-service.cfg\"" >> "/var/pound/$HOSTNAME/http-$cfg.cfg"
    echo "Include \"$cfg_file.https-service.cfg\"" >> "/var/pound/$HOSTNAME/https-$cfg.cfg"
}

function pound_make_config_http_redirect { ## URL
cat > "$cfg_file.https-redirect.cfg" << EOF
        Service
            HeadRequire "Host: $host_header"
            Redirect "$1"
        End
EOF
    echo "Include \"$cfg_file.https-redirect.cfg\"" >> "/var/pound/$HOSTNAME/http-domains.cfg"
}

function pound_make_config_https_redirect { ## URL
cat > "$cfg_file.http-redirect.cfg" << EOF
        Service
            HeadRequire "Host: $host_header"
            Redirect "$1"
        End
EOF
    echo "Include \"$cfg_file.http-redirect.cfg\"" >> "/var/pound/$HOSTNAME/https-domains.cfg"
}

function pound_make_config { # for container C
    
    local C DC
    
    C="$1"
    DC="$(echo "$C" | tr '.' '-')"
    
    if [[ ${C:0:5} == "mail." ]]
    then
        ## mail servers have no domains
        ## TODO - web client?
        return
    fi
    
    mkdir -p "/var/pound/$HOSTNAME/$C"
    
    ## import container certificates
    
    local http_port https_port
    local http_redirect https_redirect redirect no_http no_https
    
    #ip="$(get container "$C" ip)"
    
    http_port="$(get container "$C" http-port)"
    [[ -z $http_port ]] && http_port=80
    
    http_port="$(get container "$C" https-port)"
    [[ -z $https_port ]] && http_port=80
    
    ## DDDN direct acces over the server domain name
    cfg_file="/var/pound/$HOSTNAME/$C/dddn"
    host_header="$DC.$SDN"
    cfg=ddn-domains
    pound_make_service_config
    
    ## Redirects
    http_redirect="$(get container "$C" http-redirect)"
    [[ ! -z $http_redirect ]] && pound_make_config_http_redirect "$http_redirect"
    
    https_redirect="$(get container "$C" https-redirect)"
    [[ ! -z $https_redirect ]] && pound_make_config_http_redirect "$https_redirect"
    
    redirect="$(get container "$C" redirect)"
    if [[ ! -z $redirect ]]
    then
        pound_make_config_http_redirect "$redirect"
        pound_make_config_https_redirect "$redirect"
    fi
    
    no_http="$(get container "$C" no_http)"
    [[ $no_http == true ]] && pound_make_config_http_redirect "https://$C"
    
    no_http="$(get container "$C" no_https)"
    [[ $no_https == true ]] && pound_make_config_https_redirect "http://$C"
    
    ## Aliases
    
    ## Codepad and spec containers
    
}

function restart_pound {
    
    systemctl restart pound.service
    
    test=$(systemctl is-active pound.service)
    
    if [ "$test" == "active" ]
    then
        msg "restarted pound.service"
    else
        ## pound syntax check
        pound -c -f /etc/pound.cfg
        
        err "Pound restart FAILED!"
        systemctl status pound.service --no-pager
    fi
}

