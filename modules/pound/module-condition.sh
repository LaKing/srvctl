#! /bin/bash

if [[ $SC_REVERSE_PROXY == 'pound' ]]
then
    echo true
    return
fi

echo false