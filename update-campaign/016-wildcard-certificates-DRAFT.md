# 016 — Let's Encrypt wildcard certificates via DNS-01 (G7) — DRAFT for review

Status: DRAFT written session 1 (autonomous). Not approved.

## v3 reality (from modules/letsencrypt.md + named.md fact sheets)

- Per-domain http-01 via a bespoke acme-server.js (port 1028) behind
  haproxy; letsencrypt.js drives certbot per container domain, bundles
  privkey+fullchain+ca into one .pem into the datastore and container
  rootfs. Known hazards: vendored EXPIRED letsencrypt-ca.pem appended to
  bundles; fs.R_OK deprecation; per-domain issuance means one cert+renewal
  per microsite.
- named module: BIND authoritative for all microsite domains, zone files
  regenerated from containers.json cluster-wide; masters/slaves supported.
  We RUN the authoritative DNS — the key enabler for DNS-01.

## Target shape

- Wildcard cert per hosting domain (*.domain + domain) via DNS-01,
  replacing per-microsite certs where subdomain-based sites allow it;
  per-domain certs remain only for customer vanity domains (those can stay
  http-01 or move to DNS-01 with delegated zones).
- Challenge automation without third-party DNS APIs: since named is ours,
  use RFC2136/nsupdate with a TSIG key scoped to _acme-challenge zones
  (certbot-dns-rfc2136 plugin), or a small hook writing the TXT record
  through the named regeneration path. RFC2136 is standard and avoids
  regenerating whole zones per renewal — preferred.
- Renewal: certbot timer; post-renewal hook redistributes bundles to
  haproxy/containers (same .pem bundle format and locations as v3 so
  consumers don't change — drop the expired static CA append).
- acme-server.js/port 1028 path retires once nothing uses http-01.

## Migration

1. Enable RFC2136 (TSIG) on masters for _acme-challenge updates only.
2. Issue wildcard for the primary hosting domain alongside existing certs;
   deploy to a test container + haproxy backend; verify SNI serving.
3. Switch microsite deployment to the wildcard bundle; keep per-domain
   renewals running until each domain's consumers are switched; then
   disable per-domain issuance.

## Open questions (for the user)

1. Inventory: which of the ~5 servers' hosted domains are subdomain-based
   (wildcard-eligible) vs customer-owned domains?
2. Rate limits/SAN strategy: one wildcard per domain, or combined SANs?
3. Where should the single renewal authority live — one host per domain
   (the DNS master) distributing bundles cluster-wide?
