# 015 — OpenVPN → ZeroTier cluster mesh (G8) — DRAFT for review

Status: DRAFT written session 1 (autonomous). Not approved.
User WIP exists: modules/usersonve/commands/add-zerotier.sh (uncommitted)
— this plan must absorb its direction, not override it.

## v3 reality (from modules/openvpn.md fact sheet)

- Hub-less full mesh: every host runs a UDP/1101 server (tun-hostnet,
  10.15.$SC_HOSTNET.0/24) + one client tunnel per peer host. Certs minted
  by the CA module on SC_ROOTCA_HOST, fetched over ssh/rsync ("grab only
  if missing" — stale-cert bug class).
- Config is aging: comp-lzo (deprecated/insecure), AES-256-CBC, Fedora<28
  compat branches, a dormant "usernet" TCP/1100 concept (certs minted,
  server never configured).
- Consumers of 10.15.x.y addressing: nfs mounts, ssh known-hosts,
  datastore host sync, named peer fetches — the migration must enumerate
  and repoint each (grep for 10.15. in Phase A data: nfs, ssh, datastore,
  named fact sheets).

## Target shape

- One ZeroTier network joins all cluster hosts; managed routes replace the
  per-peer tunnel fan-out. No per-host cert distribution at all — that
  whole CA/ssh/rsync sync path (a discovery security finding) shrinks.
- Addressing: keep a deterministic per-host address. Suggest mapping
  HOSTNET id -> static ZeroTier-managed IP so consumers (nfs, ssh,
  datastore) can migrate by address swap; whether to reuse 10.15.x.y
  inside ZeroTier (possible, avoids config churn) is an open question.
- Module shape: a v4 `zerotier` module (install zerotier-one, join
  network, assert address, expose `mesh_ip <host>` helper) replacing the
  openvpn module's mesh role. usersonve's add-zerotier command (user WIP)
  covers per-container/user access — separate concern, same network or a
  second network.

## Migration (per 013 discipline: add new, verify, then remove old)

1. Install ZeroTier on all hosts, join network — OpenVPN untouched. Both
   meshes run in parallel (different subnets — zero interference).
2. Repoint consumers one by one (nfs, ssh known-hosts, datastore sync,
   named fetches) to the ZeroTier addresses; verify each.
3. Soak; then disable OpenVPN mesh units host by host; remove module last.
   Never leave a host with neither mesh up (checklist gate per host).

## Decisions folded (D15, D16, D17)

- **D15** — a fully **srvctl-managed, self-contained ZeroTier controller** on
  a cluster host (ztncui/zerotier controller). No my.zerotier.com dependency;
  srvctl provisions the network and members.
- **D16** — addressing: reuse 10.15.x.y, or possibly move to **10.16.x.y**
  (tentative). Either way, one deterministic per-host address mapped from
  HOSTNET id; the migration repoints nfs/ssh/datastore/named consumers to it.
  (Pick 10.15 vs 10.16 in the work package — 10.16 gives a clean break from
  the OpenVPN range during the parallel-run window, avoiding any overlap.)
- **D17** — ZeroTier replaces BOTH v3 mesh networks: the OpenVPN **hostnet**
  (host-to-host mesh) AND the **usernet** (the never-finished user/container
  access path). `add-zerotier.sh` (user WIP) is for containers and external
  services — i.e. the usernet successor lives on ZeroTier too. So: internal
  ZeroTier = hostnet successor; add-zerotier = usernet/container/external
  successor. Decide in the work package whether these are one network with
  managed routes/rules or two networks (host mesh vs user/container access).

## Consequence for the openvpn deprecation
Because ZeroTier now subsumes usernet as well, the openvpn module's dormant
usernet TODO (certs minted, no server) is NOT revived — it's retired with the
rest of openvpn. The G8 removal covers both hostnet and usernet in one go.
