#!/bin/bash

cd vncproxy

./waf configure
./waf -v

rsync -av  ./build/vncproxy /bin/vncproxy