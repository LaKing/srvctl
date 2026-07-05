#!/bin/bash

## @@@ install-crossover
## @en Crossover/wine for user x with VNC and ratpoison
## &en You can access the application over phones and mobile devices over VNC

## Kiosk installer: CrossOver (Wine) for the fixed appliance user x created
## by vnc-desktop. Installs the codeweavers rpm plus its 32/64-bit library
## stack, links shared license files from the host share, and points the
## kiosk autostart contract (/home/x/autostart.sh, .ratpoisonrc) at crossover.

## Guard: refuse to run outside the srvctl dispatcher (module-local exit code).
[[ $SRVCTL ]] || exit 4

ve_only
root_only


msg "install crossover and the required packages"
sc_install http://crossover.codeweavers.com/redirect/crossover.rpm
sc_install --best gtk3 python3-gobject
sc_install --best perl-File-Copy
sc_install --best vte291

sc_install --best -y fontconfig.i686 gstreamer1-plugins-base.i686 gstreamer1-plugins-good.i686 gstreamer1-plugins-bad-free.i686 gstreamer1-plugins-ugly-free.i686 gstreamer1.i686  libXcomposite.i686 libXinerama.i686 libtiff.i686 libxml2.i686 libxslt.i686 openldap.i686 sane-backends-libs.i686 vulkan-loader.i686 nss-mdns.i686 pcsc-lite-libs.i686

sc_install --best -y fontconfig.x86_64 gstreamer1-plugins-base.x86_64 gstreamer1-plugins-good.x86_64 gstreamer1-plugins-bad-free.x86_64 gstreamer1-plugins-ugly-free.x86_64 gstreamer1.x86_64 libXcomposite.x86_64 libXinerama.x86_64 libtiff.x86_64 libxml2.x86_64 libxslt.x86_64 openldap.x86_64 sane-backends-libs.x86_64 vulkan-loader.x86_64 nss-mdns.x86_64 pcsc-lite-libs.x86_64


msg "Copy crossover files"
## FIXME(v4): ln -s without -f — re-runs warn "File exists" and cannot update
## the links (idempotency broken, cosmetic); applies to all three links below.
if [[ -f /opt/cxoffice/bin/crossover ]]
then
    run ln -s /opt/cxoffice/bin/crossover /bin/crossover
fi

## Shared CrossOver license, bind-mounted from the host share.
if [[ -f /var/srvctl3/share/common/crossover/license.sig ]] && [[ -f /var/srvctl3/share/common/crossover/license.txt ]]
then
    run ln -s /var/srvctl3/share/common/crossover/license.sig /opt/cxoffice/etc/license.sig
    run ln -s /var/srvctl3/share/common/crossover/license.txt /opt/cxoffice/etc/license.txt
fi

msg "Create .ratpoisonrc to start crossover automatically in ratpoison desktop"

## FIXME(v4): unquoted heredoc delimiter — the "$@" inside the generated
## comment line expands at install time against the sourcing context's
## positional parameters, so the written file can vary; quote the delimiter.
cat > /home/x/.ratpoisonrc << EOF
## exec "/opt/cxoffice/bin/wine" --bottle "Xtouch" --check --wait-children --start "C:/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Xilica/XTouch.lnk" "$@"
exec bash -c "/opt/cxoffice/bin/crossover"
EOF

## Note: To start xterm in ratpoison use ctrl-t then '!'

msg "Crossover installation complete."

## Kiosk autostart contract: vnc-desktop's none.desktop and the Ctrl+Alt+Del
## xbindkeys binding both exec this file; overwrite it to launch crossover.
cat > '/home/x/autostart.sh' << EOF
#!/bin/bash

xbindkeys &

## run crossover
exec /opt/cxoffice/bin/crossover

## Example, run the XTouch.exe crossover file via XTouch bottle
## XTouch can run only once
# killall XTouch.exe
# exec "/opt/cxoffice/bin/wine" --bottle "XTouch" --check --wait-children --start "C:/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Xilica/XTouch.lnk"
EOF

chown x:x /home/x/autostart.sh
chmod +x /home/x/autostart.sh
