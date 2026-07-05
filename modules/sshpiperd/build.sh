#!/bin/bash

##
##   modules/sshpiperd/build.sh — developer-only rebuild script.
##
##   Not wired into srvctl dispatch (no help metadata, not executable);
##   run by hand from this module directory to rebuild the vendored
##   sshpiperd binary from the patched tg123/sshpiper source
##   (workingdir.go), install it to /bin/sshpiperd and restart the
##   service. FIXME(v4): the script cannot currently complete — it uses
##   the 'run' helper without sourcing lablib, and the GOPATH 'go get'
##   workflow below is dead under module-mode Go; replace vendoring with
##   a pinned, checksum-verified upstream release.
##

[[ -f /bin/sshpiperd ]] && rm -fr /bin/sshpiperd

## FIXME(v4): inverted test — warns "patch file missing" when the file
## exists, and continues silently when it is actually missing (the cat
## below then truncates the upstream file to empty).
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

## overwrite the upstream file with the srvctl-patched version and
## substitute the version token
cat workingdir.go > /root/go/src/github.com/tg123/sshpiper/sshpiperd/workingdir.go

sed -i -- "s|@SRVCTL_VERSION|$ver|g" /root/go/src/github.com/tg123/sshpiper/sshpiperd/workingdir.go
## FIXME(v4): no-op — the @SRVCTL_INSTALL_DIR token no longer exists in
## workingdir.go.
sed -i -- "s|@SRVCTL_INSTALL_DIR|/usr/local/share/srvctl|g" /root/go/src/github.com/tg123/sshpiper/sshpiperd/workingdir.go

## FIXME(v4): 'run' is undefined in this standalone script (lablib is
## never sourced), so both commands fail with "command not found" and
## the build below can never succeed.
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
