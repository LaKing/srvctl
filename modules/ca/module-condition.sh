#! /bin/bash

if [[ $SC_ROOTCA_HOST == "$HOSTNAME" ]]
then
    echo true
    return
fi

echo false
