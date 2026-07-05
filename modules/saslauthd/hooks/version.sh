#!/bin/bash

## Version hook: intended to print the installed saslauthd version.
## FIXME(v4): dead code — no "run_hook version" call site exists anywhere in
## the tree, so this hook never runs; wire it up or drop it in v4.
saslauthd -v
