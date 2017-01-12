#!/bin/bash

for sourcefile in /etc/srvctl/data/*.conf
do
    [[ -f $sourcefile ]] && cat "$sourcefile" > /etc/srvctl/"${sourcefile:17}"
done

