#!/bin/bash

## constants
readonly SC_NAMED_INCLUDES="/var/named/$SRVCTL-includes.conf"
readonly SC_NAMED_VAR_PATH="/var/named/$SRVCTL"

readonly SC_TODAY="$(date +%y%m%d)"

function procedure_write_named_conf {
cat > "$named_conf" << EOF
## $SRVCTL named main conf $D
zone "$D" {
        type master;
        file "$named_zone";
};
EOF
}

function procedure_write_named_slave {
cat  > "$named_slave" << EOF
## $SRVCTL named slave conf $D
zone "$D" {
        type slave;
        masters { $ip ;};
        file "$named_slave_zone";
};
EOF
}

function procedure_write_dyndns_conf {
cat > "$named_conf" << EOF
## $SRVCTL dyndns named main conf $D
zone "$D" {
        type master;
        file "$named_zone";
        allow-update { key "srvctl."; };
};
EOF
}

function procedure_write_named_zone {
cat > "$named_zone" << EOF
$ttl
@        IN SOA        @ hostmaster.$CDN. (
                                        $serial        ; serial
                                        1D        ; refresh
                                        1H        ; retry
                                        1W        ; expire
                                        3H )        ; minimum
        IN         NS        ns1.$CDN.
        IN         NS        ns2.$CDN.
        IN         NS        ns3.$CDN.
        IN         NS        ns4.$CDN.
*        IN         A        $ip
@        IN         A        $ip
EOF
}

function procedure_append_gsuite_conf {
    echo '
; nameservers for google apps
@    IN    MX    1    ASPMX.L.GOOGLE.COM
@    IN    MX    5    ALT1.ASPMX.L.GOOGLE.COM
@    IN    MX    5    ALT2.ASPMX.L.GOOGLE.COM
@    IN    MX    10    ALT3.ASPMX.L.GOOGLE.COM
@    IN    MX    10    ALT4.ASPMX.L.GOOGLE.COM
    ' >> "$named_zone"
}

function create_named_zone {
    
    ## argument domain ($C or alias)
    D="$1"
    
    local named_conf named_zone named_slave named_slave_zone mail_server spf_string ve_host_ip_list ip use_gsuite use_dyndns
    
    named_conf="$SC_NAMED_VAR_PATH/$D.conf"
    named_zone="$SC_NAMED_VAR_PATH/$D.zone"
    named_slave="$SC_NAMED_VAR_PATH/$D.slave"
    named_slave_zone="$SC_NAMED_VAR_PATH/$D.slave.zone"
    
    ip="$(get container "$D" host_ip)"
    use_dyndns=false
    
    if [[ "$(get container "$D" type)" == "dyndns" ]]
    then
        use_dyndns=true
    fi
    if [[ "$(get container "$D" host)" == "$HOSTNAME" ]]
    then
        procedure_write_named_slave
        return 0
    fi
    
    mail_server="mail"
    spf_string="v=spf1"
    
    ve_host_ip_list="$(cfg system ve_host_ip_list)" || exit
    
    for host_ip in $ve_host_ip_list
    do
        spf_string="$spf_string ip4:$host_ip"
    done
    
    spf_string="$spf_string a mx"
    
    use_gsuite=false
    if [[ "$(get container "$D" use_gsuite)" == true ]]
    then
        use_gsuite=true
    fi
    
    if $use_gsuite
    then
        spf_string="$spf_string include:_spf.google.com ~all"
    else
        spf_string="$spf_string -all"
    fi
    
    procedure_write_named_conf
    
    local serial_file serial
    serial_file="/var/$SRVCTL/named-serial/$SC_TODAY"
    mkdir -p "/var/$SRVCTL/named-serial"
    serial=0
    
    if [[ ! -f $serial_file ]]
    then
        serial=$SC_TODAY'0000'
        echo "$serial" > "$serial_file"
    else
        serial=$(($(cat "$serial_file")+1))
        echo "$serial" > "$serial_file"
    fi
    
    if $use_dyndns
    then
        
        local dyndns_ip ttl
        
        # shellcheck disable=SC2016
        ttl='$TTL 1D';
        
        dyndns_ip="$ip"
        
        if [[ -f /var/dyndns/$D.ip ]]
        then
            dyndns_ip="$(cat "/var/dyndns/$D.ip")"
        fi
        
        ## TODO add IPv6 support
        ## Create Basic Zonefile
        ## We require to have 4 nameservers.
        
        if [[ "${dyndns_ip:0:7}" == '::ffff:' ]]
        then
            procedure_write_dyndns_conf
            # shellcheck disable=SC2016
            ttl='$TTL 60';
            ip="${dyndns_ip:7}"
        fi
        
    fi
    
    procedure_write_named_zone
    
    
    if $use_gsuite
    then
        
        ## Use google apps mailservers
        procedure_append_gsuite_conf
        
        ## Use the dkim string if found
        if $use_gsuite
        then
            local gsuite_dkim_record
            gsuite_dkim_record="$(get container "$D" gsuite_dkim_record)"
            if [[ $gsuite_dkim_record != undefined ]]
            then
                echo 'google._domainkey    IN    TXT    ( "'"$gsuite_dkim_record"'" ) ; -- custom gsuite DKIM' >> "$named_zone"
            fi
        fi
    else
        ## use custom / standard mail
        echo "@        IN        MX        10        ${mail_server,,}" >> "$named_zone"
    fi
    
    ## add SPF
    echo '@    IN    TXT    "'"$spf_string"'"' >> "$named_zone"
    
    local selector
    selector="default"
    
    if [[ -d /var/$SRVCTL/opendkim/$D ]]
    then
        ## Add DKIM
        for i in "/var/$SRVCTL/opendkim/$D"/*.txt
        do
            selector="$(basename "$i")"
            selector="${selector:0:-4}"
            cat "/var/$SRVCTL/opendkim/$D/$selector.txt" >> "$named_zone"
        done
    fi
    
    if [[ -d /var/$SRVCTL/opendkim/mail.$D ]]
    then
        ## Add DKIM of the seperate mailserver
        for i in "/var/$SRVCTL/opendkim/mail.$D"/*.txt
        do
            selector="$(basename "$i")"
            selector="${selector:0:-4}"
            cat "/var/$SRVCTL/opendkim/mail.$D/$selector.txt" >> "$named_zone"
        done
    fi
    
    ## TODO IPv6
    #'        AAAA        ::1'
    
    ## named zone written.
    msg "named-zone created for $D"
    return 0
}




function regenerate_dns {
    
    msg "Regenerate DNS - named/bind configs"
    
    ## dir might not exist
    mkdir -p "$SC_NAMED_VAR_PATH"
    
    ## has to be empty for regeneration
    rm -rf "${SC_NAMED_VAR_PATH:?}"/*
    
    
    ## the main include file
    named_local_includes="/var/named/$SRVCTL-local.conf"
    
    ## the secondary file
    named_slave_includes="/var/named/$SRVCTL-slave.conf"
    
    echo "## $SRVCTL named includes" > "$SC_NAMED_INCLUDES"
    if [ -f /var/named/srvctl-include-key.conf ]
    then
        echo 'include "/var/named/srvctl-include-key.conf";' >> "$SC_NAMED_INCLUDES"
    fi
    
    echo "## $SRVCTL named primary local on $HOSTNAME" > "$named_local_includes"
    echo "## $SRVCTL named slaves on $HOSTNAME" > "$named_slave_includes"
    
    local container_list named_conf named_slave
    container_list="$(cfg system container_list)"
    
    for C in $container_list
    do
        ## skip local domains
        if [ "${C: -6}" == "-devel" ] || [ "${C: -6}" == ".devel" ] || [ "${C: -6}" == "-local" ] || [ "${C: -6}" == ".local" ]
        then
            continue
        fi
        
        ## skip mail-only servers
        if [ "${C:0:5}" == "mail." ]
        then
            continue
        fi
        
        create_named_zone "$C"
        
        named_conf="$SC_NAMED_VAR_PATH/$D.conf"
        named_slave="$SC_NAMED_VAR_PATH/$D.slave"
        
        if [[ -f $named_conf ]]
        then
            echo 'include "'"$named_conf"'";' >> "$named_local_includes"
        fi
        if [[ -f $named_slave ]]
        then
            echo 'include "'"$named_slave"'";' >> "$named_slave_includes"
        fi
        ## in srvctl3 aliases are seperate domains - with the same IP as the container
    done
    
    echo 'include "'"$named_local_includes"'";' >> "$SC_NAMED_INCLUDES"
    echo 'include "'"$named_slave_includes"'";' >> "$SC_NAMED_INCLUDES"
    
    chown root:named "$SC_NAMED_INCLUDES"
    chmod 640 "$SC_NAMED_INCLUDES"
    
    chown -R root:named "$SC_NAMED_VAR_PATH"
    chmod -R 640 "$SC_NAMED_VAR_PATH"
    chmod 650 "$SC_NAMED_VAR_PATH"
    
    ## all preparations done, activate!
    systemctl restart named.service
    test=$(systemctl is-active named.service)
    if ! [ "$test" == "active" ]
    then
        err "Error loading DNS settings."
        run systemctl status named.service --no-pager
        exit
    else
        msg "DNS server OK"
    fi
    
}

