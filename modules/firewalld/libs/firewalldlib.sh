#!bin/bash

function firewalld_add_service() { ## name proto port
    
    local zone
    zone=$(firewall-cmd --get-default-zone)
    
    name="$1"
    proto="$2"
    port="$3"
    
    if [[ "$(firewall-cmd --zone="$zone" --permanent --query-service="$name")" == yes ]]
    then
        ntc "firewalld: $name is enabled already."
        return
    fi
    
    if [[ -f /usr/lib/firewalld/services/$name.xml ]] && [[ -z $proto ]] && [[ -z $port ]]
    then
        run firewall-cmd  --zone="$zone" --permanent --add-service="$name"
    else
        
cat > "/etc/firewalld/services/$name.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>$name</short>
  <description>$name $proto $port (added by srvctl)</description>
  <port protocol="$proto" port="$port"/>
</service>
EOF
        
        run firewall-cmd --reload
        run firewall-cmd --zone="$zone" --permanent --add-service="$name"
    fi
    
    run firewall-cmd --reload
    
}
