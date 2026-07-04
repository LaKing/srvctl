#!/bin/bash

## @@@ install-qlcplus
## @en QLC+ light controller for dmx on artnet
## &en Controll lighting over the network

## run only with srvctl? or with bash?
[[ $SRVCTL ]] || exit 4

ve_only
root_only


msg "Install QLC+ and the required packages"

## dnf config-manager --add-repo https://download.opensuse.org/repositories/home:mcallegari79/Fedora_38/home:mcallegari79.repo

## curl https://download.opensuse.org/repositories/home:/mcallegari79/Fedora_38/home:mcallegari79.repo

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

mkdir -p /home/x/.qlcplus/fixtures

msg "Sync /var/srvctl3/share/common/qlcpuls/fixtures"
for f in $(ls /var/srvctl3/share/common/qlcplus/fixtures)
do
	echo "$f"
	cat "/var/srvctl3/share/common/qlcpuls/fixtures/$f" > "/home/x/.qlcplus/fixtures/$f"
done

if [[ -f /home/x/default.qxw ]]
then
	msg "Autostart with /home/x/default.qxw"
else 
	msg "Create /home/x/default.qxw"
fi
