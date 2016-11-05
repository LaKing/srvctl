#!/bin/bash

##
## This script is NOT part of the srvctl functions, it is used for development of srvctl.
##

## get project directory - this file should reside in the project root folder
wd=/srv/codepad-project

log=/var/codepad/project.log
pid=/var/codepad/project.pid
rmd=/srv/codepad-project/README.md

chown -R codepad:codepad $wd
chmod -R +X $wd
NOW=$(date +%Y.%m.%d-%H:%M:%S)


## enforce codepad user
if [ "$USER" != codepad ]
then
    su codepad -s /bin/bash -c "$0"
    sc
    
    echo "## Srvctl v3 ($(cat $wd/version))" > $rmd
    echo "A remake for 2016 mostly using systemd tools" >> $rmd
    
    
    # shellcheck disable=SC2016
    echo '```' >> $rmd
    
    bash "$wd/srvctl.sh" help | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" >> $rmd
    # shellcheck disable=SC2016
    
    echo '```' >> $rmd
    
    ## push to local
    if [ -d "$wd/.git" ] && [ "$1" == '!' ]
    then
        cd "$wd"
        echo "## git push"
        ## add files to repo
        echo "git add -A ."
        git add -A .
        ## commit them
        echo "git commit -m $(cat $wd/version)"
        git commit -m "$(cat $wd/version)"
        ## push them
        echo git push
        git push  >> $log
    fi
    
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
        #echo /bin/python /srv/beautify_bash.py "$file"
        /bin/python /srv/beautify_bash.py "$file"
        rm -fr "$file~"
    fi
done < /tmp/srvctl-bash-beautify



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
