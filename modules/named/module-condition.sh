#! /bin/bash

if [[ $SC_DNS_SERVER == 'named' ]]
then
    echo true
    return
fi

echo false