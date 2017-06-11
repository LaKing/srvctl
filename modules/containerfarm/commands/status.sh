#!/bin/bash

## @en List container statuses

local list
if [[ $SC_USER == root ]]
then
    list="$(cfg system container_list)" || exit
else
    list="$(cfg user container_list)" || exit
fi

echo ''
printf "${YELLOW}%-10s${CLEAR}" "STATUS"
printf "${YELLOW}%-48s${CLEAR}" "HOSTNAME"
printf "${YELLOW}%-14s${CLEAR}" "IP-INTERNAL"
printf "${YELLOW}%-16s${CLEAR}" "RESELLER"
printf "${YELLOW}%-16s${CLEAR}" "USERNAME"

echo ''

for C in $list
do
    local ip ping_ms user reseller
    ip="$(get container "$C" ip)"
    exif "Could not get IP for $C"
    
    #if systemctl is-active "srvctl-nspawn@$C" > /dev/null
    #then
    if ping_ms=$(ping -W 1 -c 1 "$ip" | grep rtt)
    then
        printf "${GREEN}%-10s${CLEAR}" "${ping_ms:23:5}ms"
    else
        printf "${RED}%-10s${CLEAR}" "ERROR"
    fi
    #else
    #    printf "${RED}%-10s${CLEAR}" "INACTIVE"
    #fi
    
    if [[ -d /srv/$C ]]
    then
        printf "${GREEN}%-48s${CLEAR}" "$C"
    else
        printf "${YELLOW}%-48s${CLEAR}" "$C"
    fi
    
    printf "${GREEN}%-14s${CLEAR}" "$ip"
    printf "${YELLOW}%-16s${CLEAR}" "$(get container "$C" reseller)"
    printf "${YELLOW}%-16s${CLEAR}" "$(get container "$C" user)"
    
    echo ''
done

echo ''
