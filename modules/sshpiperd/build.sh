#!/bin/bash

## ssh piperd re-install

[[ -f /bin/sshpiperd ]] && rm -fr /bin/sshpiperd

if [[ -f workingdir.go ]]
then
    echo "workingdir.go - patch file missing"
fi

wd="$(pwd)"
echo "Building in $wd"
ver="$(cat /usr/local/share/srvctl/version)"

echo "installing go"
dnf -y install golang

export GOPATH=/root/go

echo "getting sourcefiles"
go get github.com/tg123/sshpiper/sshpiperd

echo "building sshpiperd $ver"

cat workingdir.go > /root/go/src/github.com/tg123/sshpiper/sshpiperd/workingdir.go

sed -i -- "s|@SRVCTL_VERSION|$ver|g" /root/go/src/github.com/tg123/sshpiper/sshpiperd/workingdir.go
sed -i -- "s|@SRVCTL_INSTALL_DIR|/usr/local/share/srvctl|g" /root/go/src/github.com/tg123/sshpiper/sshpiperd/workingdir.go

run cd /root/go/src/github.com/tg123/sshpiper/sshpiperd
run go build -o "$wd/sshpiperd"

if [[ ! -f "$wd/sshpiperd" ]]
then
    echo "sshpiperd build failed"
else
    cp "$wd/sshpiperd" /bin/sshpiperd
    sshpiperd --version
    
    ## this is really just for me - the author
    # rsync -avze ssh "$wd/sshpiperd" root@r2.d250.hu:/srv/srvctl-devel/rootfs/srv/codepad-project/modules/sshpiperd
    
    sc sshpiperd !
    journalctl -u sshpiperd
fi
