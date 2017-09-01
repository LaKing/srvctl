#! /bin/bash

if [[ $SC_REVERSE_PROXY == 'haproxy' ]]
then
    echo true
    return
fi

echo false
return
