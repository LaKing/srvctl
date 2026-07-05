# 019 — Gluster removal (G4) — CONFIRMED

Status: CONFIRMED 2026-07-05 (D8 — "nuke gluster, nothing uses it"). The
removal proceeds; the only remaining safety item is the G4 ORDERING
CONSTRAINT below (de-gluster the datastore+static hooks BEFORE dropping the
module). Nothing replaces gluster's shared-storage role (datastore
replication → G2; static is single-host + backups).

## v3 reality (from modules/gluster.md fact sheet)

- The module is already HARD-DISABLED at baseline (module-condition.sh:39
  — the enabling line is commented out), so no current v3 host should be
  running srvctl-managed gluster. To confirm per server during the 013
  inventory step: glusterd.service state, /glu/* bricks, fuse mounts on
  /var/srvctl3/{datastore,storage}.
- Residue in OTHER modules that removal must clean: SC_USE_GLUSTER
  branches in datastore and static; the read-only brick bind-mount path
  /var/srvctl3/gluster/srvctl-data consumed by ssh/sshpiperd as pubkey/
  datastore RO fallback; CA gluster cert minting; firewalld glusterfs
  service.

### G4 ORDERING CONSTRAINT (hard prerequisite — from 003 ADDENDUM)

The `if $SC_USE_GLUSTER; then ...` hooks in datastore
(hooks/init.sh:15, hooks/update-install-host.sh:12) and static
(hooks/init.sh:3, hooks/update-install-host.sh:3) are UNSAFE against an
unset variable: `if $emptyvar` runs an empty command (status 0 = true) and
takes the gluster branch, calling now-undefined `gluster_*` helpers or
selecting the RO gluster datastore path. Removing the gluster module (or its
config) BEFORE these hooks are rewritten breaks datastore/static init and
host update-install on every server.

Therefore the removal work package MUST, in this order:
1. Rewrite the four hooks to `[[ ${SC_USE_GLUSTER:-false} == true ]]` (or
   delete the gluster branch outright), verified on a host.
2. Only then drop the gluster module and its condition/config.
This is a Stage-2 sequencing rule, not optional cleanup.

## What (if anything) replaces it

- Its two roles were: replicated datastore (srvctl-data) and replicated
  static storage (srvctl-storage). The datastore's replication story in v4
  is G2 (boilerplate source of truth + per-host cache sync) — no shared
  filesystem needed. Static storage: if no production host actually uses
  a replicated /var/srvctl3/storage today (inventory will confirm; module
  is disabled, so presumably not), nothing replaces it; single-host
  storage + the backup module remain.
- The ssh/sshpiperd RO-fallback lookups repoint to the local datastore
  cache path (G2 design keeps a local copy — same guarantee the RO brick
  gave).

## Removal steps (Stage 2 work package, per 013 discipline)

1. Inventory confirms zero gluster usage on all servers (else STOP, ask).
2. v4 code drops the module + SC_USE_GLUSTER branches + repoints the two
   RO-fallback consumers; CA stops minting gluster certs.
3. Per server after v4 cutover: remove leftover certs/symlinks under
   /etc/ssl/gluster*, close firewalld glusterfs service, purge
   glusterfs-server rpm if installed. No data migration expected (bricks
   should not exist); if bricks ARE found non-empty, file -for-human.

Open question: confirm no host was manually re-enabled for gluster outside
srvctl (the inventory step checks this).
