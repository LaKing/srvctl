#!/bin/bash

## Build the vendored C++ vncproxy (vncproxy/, waf build system) and install
## the binary to /bin/vncproxy — the path start.sh and the service rely on.
## Manual step, run from this module directory: bash build.sh
## Needs python (for waf) and a C++ toolchain — neither installed by dnf.sh.

cd vncproxy || exit

./waf configure
./waf -v

rsync -av ./build/vncproxy /bin/vncproxy
