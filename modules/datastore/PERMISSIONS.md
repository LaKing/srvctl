# Datastore permissions

Unprivileged commands such as `srvctl status` read inventory directly from
the filesystem. The datastore root and the `hosts`, `users`, and `containers`
directories therefore use mode `0755`; their entity JSON records use `0644`.
Inventory must not contain private keys or other secrets.

`lib/permissions.js` owns the writer policy for these three public types.
The storage engine applies the record mode to the open temporary file before
fsync and rename. This covers ordinary writes, transactions, migration and
host reconciliation, including callers running with umask `077`. The legacy
per-entity writer uses the same policy. Other record types retain `0600`.
Directory preparation touches only the datastore root and the selected type
directory, never nested key directories or certificate material.

After deploying this change, run `sudo srvctl regenerate` to repair previously
written `0600` inventory records. The datastore regeneration hook applies the
same policy to existing inventory, including legacy monolithic files, without
descending into private directories or following symlinks. It skips the
read-only fallback datastore. The existing `srvctl update-install` permission
normalization also repairs inventory. Updating an individual record repairs
its mode. Reads remain non-mutating.

Regression checks: `node modules/datastore/selftest/store.test.mjs` covers
creation, replacement, transactions, migration, restrictive umasks and private
material. When run as root it additionally verifies reads from another uid.
