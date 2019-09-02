function install_openvpn() { #net #ip #serverport

#source "/var/srvctl3/share/containers/$HOSTNAME/config"
#echo "$mapped_ports" > /tmp/mapped_ports.json
msg install_openvpn

NET="$HOSTNAME-net"

root_CA_init "$NET"
    
create_ca_certificate client "$NET" root

}