#!/bin/bash

## @@@ vnc-desktop [DESKTOP]
## @en Add user x with a virtual desktop:0 with gnome, ratpoison, ...
## &en Create a workspace with VNC server as a remote desktop.
## &en The argument can be used to specify a desktop type. Run ls /usr/share/xsessions to see available desktops after installation.
## &en  gnome | LXDE | awesome | budgie-desktop | cinnamon | cinnamon2d | gnome-classic | i3 | lxqt | mate | openbox | ratpoison | xfce | xmonad | fluxbox

## Kiosk provisioner: creates the fixed appliance user x and an UNAUTHENTICATED
## TigerVNC remote desktop on display :0 (securitytypes=none, firewall opened
## permanently), wired to the /home/x/autostart.sh contract that
## install-crossover / install-qlcplus later overwrite with their app.

## Guard: refuse to run outside the srvctl dispatcher (module-local exit code).
[[ $SRVCTL ]] || exit 4

ve_only
root_only

msg "We are on VE: $SC_ON_VE"

## Default is the bare kiosk session (the none.desktop xsession written below).
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

## Note: no VNC password is set up — access control is securitytypes=none in
## the .vnc/config written below (see the FIXME at the firewall opening).
mkdir -p /home/x/.vnc

## The "none" xsession: a bare kiosk session that just execs the autostart
## contract, so the VNC session works without any desktop environment.
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
    ## FIXME(v4): unimplemented branch exits 0 — requesting gnome silently
    ## succeeds while doing nothing.
    exit
    ## Sketch of the intended implementation:
    #dnf -y group install "Basic Desktop" gnome --exclude=NetworkManager
    #dnf -y install @basic-desktop-environment @workstation-product-environment
else
    msg 'The appropriate full desktop group: dnf -y group install "Basic Desktop"'
    dnf group list --available '*desktop'
    msg '.. or the one from Available Environment Groups'

    ## its either a group, or a package
    if [[ $DESKTOP != "none" ]]
    then
        dnf -y install "$DESKTOP"
    fi

fi


## FIXME(v4): securitytypes=none (in .vnc/config below) plus this permanently
## opened vnc-server firewall service = unauthenticated remote desktop;
## intentional kiosk design, but security-sensitive — must be a conscious
## decision in v4.
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

## Bind Ctrl+Alt+Del to the autostart contract (kiosk "restart the app" key).
## FIXME(v4): the generated defaults are immediately thrown away by the
## truncating echo below — dead work; the resulting file only holds the
## Ctrl+Alt+Del binding.
xbindkeys --defaults > /home/x/.xbindkeysrc
echo '' > /home/x/.xbindkeysrc
echo '"/home/x/autostart.sh"' >> /home/x/.xbindkeysrc
echo '  Control + Alt + Delete' >> /home/x/.xbindkeysrc
chown x:x /home/x/.xbindkeysrc

## Seed the kiosk autostart contract (xbindkeys only); install-crossover /
## install-qlcplus overwrite this file with their application exec.
cat > '/home/x/autostart.sh' << EOF
#!/bin/bash

xbindkeys &
EOF

chmod +x /home/x/autostart.sh

msg "Create vncserver.service"

## Forking unit around vncsession-start for display :0 (mapped to user x in
## vncserver.users above); the SELinuxContext is required for vnc_session_t.
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
