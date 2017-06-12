#!/bin/bash

## argument host
local D IP

D="$1"
IP=$(cat "/var/dyndns/$D.ip")

if [[ -f "/var/dyndns/$D.lock" ]]
then
    LIP=$(cat "/var/dyndns/$D.lock")
    if [[ "$IP" == "$LIP" ]]
    then
        echo "Nothing to do."
        exit 0
    fi
fi

if [[ ${IP:0:7} == '::ffff:' ]]
then
    
    local ip update
    
    ip=${IP:7}
    update="/var/dyndns/$D.updt"
    
    echo "nsupdate $D to $ip on $HOSTNAME"
    
cat > "$update" << EOF
server localhost
debug yes
update delete $D A
update delete $D MX
update delete $D AAAA
update add $D 60 A $ip
send
EOF
    
    nsupdate -k /var/dyndns/srvctl-include-key.conf -v "$update"
    
    echo -n "$IP" > "/var/dyndns/$D.lock"
else
    echo "Dyndns is not implemented for IPV6 yet"
fi

