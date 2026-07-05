# 014 — Datastore → boilerplate srvctl-modules/datastore (G2) — DRAFT for review

Status: DRAFT written session 1 (autonomous). Not approved.

## v3 reality (from modules/datastore.md fact sheet)

- Three JSON files (hosts.json, users.json, containers.json) + verb API
  (get/put/out/cfg/del/new/add) as bash functions that spawn a fresh node
  process per call — ~159 call sites, so hot paths fork node constantly
  (a big chunk of the G1 slowness).
- lib.js is the real brain: derives UID bases, bridges, gateways, IPs,
  nspawn config, /etc/hosts, firewall commands, port maps, postfix relay
  domains from the raw JSON.
- datastore-server.js (port 1030) serves ACME validation files and a
  public containers.json snapshot behind haproxy; rsync syncs data
  between hosts.

## Target shape (G2)

- A boilerplate 4 module collection `srvctl-modules` with a `datastore`
  module, running in the d250.hu container's boilerplate instance (with
  the d250 app) as the authoritative store + admin surface.
- The HOST still needs container/network derivation data at command time
  (also when the d250.hu container itself is down/being created — the
  chicken-and-egg case). Proposal: boilerplate instance is the SOURCE OF
  TRUTH + UI + sync hub; each host keeps a local read cache (the same
  three JSON files, pulled/pushed) that the v4 mjs core reads directly.
  Bootstrap and disaster paths work from the local cache alone.
- The v4 core gets a datastore client lib (lib/datastore.mjs): in-process
  reads (no per-call node spawn — G1 win is immediate), writes go through
  one API with the RO-guard enforced in the writer (fixes the dead
  SC_DATASTORE_RO guard found in discovery).
- API between host core and boilerplate instance: needs the user's call —
  HTTP on the internal mesh (zerotier, G8) with mutual auth, vs. file-sync
  only (rsync as today). Suggest starting file-sync-compatible (zero new
  failure modes), adding the HTTP API for the admin UI second.

## Migration steps (later work packages)

1. v4 core reads the SAME v3 JSON files in-process (no schema change —
   v3/v4 coexistence per 013).
2. Verb CLI (get/put/...) kept as thin wrappers over the mjs lib,
   byte-identical output (159 call sites keep working; ported gradually).
3. boilerplate srvctl-modules/datastore stood up in d250.hu container,
   snapshot-synced, read-only first.
4. Write-path cutover host by host; rsync sync replaced last.

## Open questions (for the user)

1. Transport/auth for host<->boilerplate API (zerotier-internal HTTP?
   ssh? keep rsync?).
2. Does the d250 app already have datastore-like models to reuse, or is
   srvctl-modules/datastore built fresh on boilerplate's collection
   conventions?
3. Multi-host: one boilerplate instance for the whole cluster (d250.hu),
   or one per host with sync?
