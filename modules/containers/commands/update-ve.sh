#!/bin/bash

## @@@ update-ve VE
## @en Not implemented: see upgrade-ve and rebuild-ve
## &en A container is updated from inside with its package manager (dnf update).
## &en A release upgrade is done by root: upgrade-ve VE, or rebuild-ve VE.

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container-name
owner_only container "$ARG"

## Kept as a name users know, so that typing it explains where the real
## commands are. It must not touch the container: nothing here upgrades it.
err "update-ve is not implemented and changes nothing. Update packages inside the container with dnf; a release upgrade is root's upgrade-ve or rebuild-ve."
exit 1
