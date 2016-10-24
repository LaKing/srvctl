#!/bin/bash

##
## This script is NOT part of the srvctl functions, it is used for development of srvctl.
##

## get project directory - this file should reside in the project root folder
wd=/srv/codepad-project

log=/var/codepad/project.log
pid=/var/codepad/project.pid

chown -R codepad:codepad $wd
chmod -R +X $wd
NOW=$(date +%Y.%m.%d-%H:%M:%S)


## enforce codepad user
if [ "$USER" != codepad ]
then
    su codepad -s /bin/bash -c "$0"
    sc
    exit
fi

cd $wd

mkdir -p /srv/push-backup
rsync -av /srv/codepad-project /srv/push-backup


## INCREMENT VERSION

if ! [ -f "$wd/version" ]
then
    echo 0.0.0 > $wd/version
fi

## current version
cv=$(awk -F. -v OFS=. 'NF==1{print ++$NF}; NF>1{if(length($NF+1)>length($NF))$(NF-1)++; $NF=sprintf("%0*d", length($NF), ($NF+1)%(10^length($NF))); print}' < $wd/version)
## in cv'

echo "$cv" > $wd/version
echo "PUSH VERSION $cv of $HOSTNAME:$wd $NOW"
echo "PUSH VERSION $cv of $HOSTNAME:$wd $NOW" > $log



find "$wd" > /tmp/srvctl-bash-beautify
while read file
do
    if [[ "${file:0, -3 }" == ".sh" ]]
    then
        echo "@ $file" >> $log
        shellcheck "$file" >> $log
        shellcheck "$file"
        echo /bin/python /srv/beautify_bash.py "$file"
        /bin/python /srv/beautify_bash.py "$file"
        rm -fr "$file~"
    fi
done < /tmp/srvctl-bash-beautify


## push to local
if [ -d "$wd/.git" ]
then
    echo "## git push"
    ## add files to repo
    git add -A .
    ## commit them
    git commit -m "codepad-auto $cv"
    ## push them
    git push  >> $log
fi

if [ ! -z "$(find . -name '*.ts')" ]
then
    if [ ! -f $wd/tsconfig.json ]
    then
        tsc --init >> $log
    fi
    ## run the typescript compiler
    tsc >> $log
fi

if [ -f "$wd/server.js" ]
then
    
    echo "PUSH - RESTARTING server.js" >> $log
    
    kill "$(cat $pid)"
    
    /bin/node $wd/server.js >> $log 2>&1 &
    echo $! > $pid
fi

echo "PUSH - OK."
