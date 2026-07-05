#!/bin/bash

## @@@ fix-owner
## @en Set user and group on all content to parent owner.
## &en Useful for transfers of files across systems.
## &en Recursive chown based on parent directory.

## FIXME(v4): this command is a silent no-op — its only action below is
## commented out, while the help still promises a recursive chown. Users
## running it believe ownership was fixed. Kept as-is: uncommenting would
## be a behavior change (and the unquoted substitutions need review).
# run chown -R $(stat -c '%U' .):$(stat -c '%G' .) .

