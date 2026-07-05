#!/bin/bash

## @@@ install-qlcplus
## @en QLC+ light controller for dmx on artnet
## &en Controll lighting over the network

## Kiosk installer: QLC+ (Q Light Controller Plus, DMX over Art-Net) for the
## fixed appliance user x created by vnc-desktop. Adds the upstream OBS repo,
## installs qlcplus-qt5, rewrites the kiosk autostart contract
## (/home/x/autostart.sh) to run QLC+ with /home/x/default.qxw, and syncs
## fixture definitions from the host share.

## Guard: refuse to run outside the srvctl dispatcher (module-local exit code).
[[ $SRVCTL ]] || exit 4

ve_only
root_only


msg "Install QLC+ and the required packages"

## Upstream repo: home:mcallegari79 on openSUSE OBS
## (download.opensuse.org/repositories/home:/mcallegari79/).
## FIXME(v4): release hardcoded to Fedora_38 — stale on newer container
## releases; derive it from $VERSION_ID.

mkdir -p /etc/yum.repos.d

cat > /etc/yum.repos.d/mcallegari79.repo << EOF
[home_mcallegari79]
name=Q Light Controller Plus (Fedora_38)
type=rpm-md
baseurl=https://download.opensuse.org/repositories/home:/mcallegari79/Fedora_38/
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/home:/mcallegari79/Fedora_38/repodata/repomd.xml.key
enabled=1

EOF

run dnf -y install qlcplus-qt5
exif

dnf -y install xbindkeys

## Kiosk autostart contract: vnc-desktop's none.desktop and the Ctrl+Alt+Del
## xbindkeys binding both exec this file; overwrite it to launch QLC+.
## FIXME(v4): "[[ /home/x/autostart.sh ]]" is a non-empty-string test
## (missing -f), always true — autostart.sh is unconditionally overwritten,
## clobbering e.g. the CrossOver autostart written by install-crossover.
if [[ /home/x/autostart.sh ]]
then
cat > '/home/x/autostart.sh' << EOF
#!/bin/bash

xbindkeys &

killall qlcplus
exec bash -c '/usr/bin/qlcplus --nowm -o /home/x/default.qxw -p'

EOF

chmod +x /home/x/autostart.sh

fi

## FIXME(v4): created as root with no chown — QLC+ runs as user x and cannot
## save workspaces/configuration into its own config dir.
mkdir -p /home/x/.qlcplus/fixtures

## Copy fixture definitions shared from the host.
## FIXME(v4): iterating over ls output breaks on filenames with spaces and
## errors if the share directory is missing; use a glob in v4.
msg "Sync /var/srvctl3/share/common/qlcplus/fixtures"
for f in $(ls /var/srvctl3/share/common/qlcplus/fixtures)
do
    echo "$f"
    cat "/var/srvctl3/share/common/qlcplus/fixtures/$f" > "/home/x/.qlcplus/fixtures/$f"
done

## default.qxw is the workspace autostart.sh loads; it is never created here.
if [[ -f /home/x/default.qxw ]]
then
    msg "Autostart with /home/x/default.qxw"
else
    msg "Create /home/x/default.qxw"
fi
