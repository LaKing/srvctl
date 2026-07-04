#!/bin/bash

## @@@ vnc-desktop [DESKTOP]
## @en Add user x with a virtual desktop:0 with gnome, ratpoison, ...
## &en Create a workspace with VNC server as a remote desktop.
## &en The argument can be used to specify a desktop type. Run ls /usr/share/xsessions to see available desktops after installation.
## &en  gnome | LXDE | awesome | budgie-desktop | cinnamon | cinnamon2d | gnome-classic | i3 | lxqt | mate | openbox | ratpoison | xfce | xmonad | fluxbox


## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

ve_only
root_only

msg "We are on VE: $SC_ON_VE"

DESKTOP="none"

if [[ $ARG ]]
then
	DESKTOP="$ARG"
fi

msg "Install $DESKTOP Desktop VNC for user x"

sc_install tigervnc-server
exif

msg "Create user x"
run adduser x

#msg "please enter the password for your VNC server instance"
#run su x -c "vncpasswd"
mkdir -p /home/x/.vnc

#combined="D250$HOSTNAME"
#password=${combined:0:8}
#echo "$password" | vncpasswd -f > /home/x/.vnc/passwd

#chown x:x /home/x/.vnc/passwd
#chmod 600 /home/x/.vnc/passwd

cat > /usr/share/xsessions/none.desktop << EOF
[Desktop Entry]
Type=Application
Name=Kiosk
Exec=/home/x/autostart.sh
Terminal=false
Comment=Custom
EOF



if [[ $DESKTOP == "gnome" ]]
then
	msg "unimplemented: Installing the Basic Desktop Group"
    exit
	#dnf -y group install "Basic Desktop" gnome --exclude=NetworkManager
	#dnf -y install @basic-desktop-environment @workstation-product-environment
else
	msg 'The appropriate full desktop group: dnf -y group install "Basic Desktop"'
    dnf group list --available *desktop
    msg '.. or the one from Available Environment Groups'
	#dnf -y group install "$DESKTOP Desktop"
    
    ## its either a group, or a package
	if [[ $DESKTOP != "none" ]]
	then
		dnf -y install "$DESKTOP"
	fi
    
fi




#exif
run firewall-cmd --add-service=vnc-server --permanent
run firewall-cmd --reload


msg "Create VNC config"



cat > /home/x/.vnc/config << EOF
## To use a password, use
#securitytypes=vncauth

desktop="D250 Laboratories"
session=$DESKTOP
securitytypes=none
geometry=1920x1080

EOF

chown x:x /home/x/.vnc

msg "Create VNC user config"

cat > /etc/tigervnc/vncserver.users << EOF
#
# This file assigns users to specific VNC display numbers.
# The syntax is <display>=<username>. E.g.:
#
:0=x
EOF

dnf -y install xbindkeys

xbindkeys --defaults > /home/x/.xbindkeysrc
# echo '' >> /home/x/.xbindkeysrc
echo '' > /home/x/.xbindkeysrc
echo '"/home/x/autostart.sh"' >> /home/x/.xbindkeysrc
echo '  Control + Alt + Delete' >> /home/x/.xbindkeysrc
chown x:x /home/x/.xbindkeysrc

cat > '/home/x/autostart.sh' << EOF
#!/bin/bash

xbindkeys &
EOF

chmod +x /home/x/autostart.sh

#msg "Create .ratpoisonrc"
#
#cat > /home/x/.ratpoisonrc << EOF
#exec bash -c "/opt/cxoffice/bin/crossover"
#EOF

## run systemctl enable --now vncserver@:1

msg "Create vncserver.service"

cat > /etc/systemd/system/vncserver.service << EOF

[Install]
WantedBy = multi-user.target

[Unit]
Description=VNC-$DESKTOP-desktop
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/usr/libexec/vncsession-start :0
PIDFile=/run/vncsession-:0.pid
SELinuxContext=system_u:system_r:vnc_session_t:s0
Restart=always
RestartSec=1s

EOF

msg "Start vncserver.service"

run systemctl daemon-reload
run systemctl enable vncserver 
run systemctl restart vncserver
run systemctl status vncserver

msg "VNC $DESKTOP Desktop installation complete. Available installed xsessions:"
run ls /usr/share/xsessions

#msg "mcedit /home/x/.vnc/config to use a default password $password"
