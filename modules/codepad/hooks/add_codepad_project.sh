#!/bin/bash

if [[ $CMD != add-codepad  ]]
then
    return
fi

C="$ARG"

if [[ ! -d /usr/local/share/boilerplate ]]
then
    return
fi

msg "Adding boilerplate to codepad $C"
#mkdir -p /srv/"$C"
#echo '[Files]
#BindReadOnly=/srv/boilerplate.d250.hu/rootfs/srv/codepad-project/boilerplate:/srv/codepad-project/boilerplate
#' > /srv/"$C"/boilerplate.binds
mkdir -p /srv/"$C"/rootfs/srv/codepad-project
ln -s /usr/local/share/boilerplate/boilerplate /srv/"$C"/rootfs/srv/codepad-project/boilerplate
