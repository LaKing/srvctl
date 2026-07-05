# 017 — POP3S/IMAP4S proxy replacing perdition (G9) — decisions folded (D21, D22, D23)

Status: direction DECIDED 2026-07-05 — protocol-aware proxy, NOT a plain
TCP/SNI proxy. The working config is the open risk (D21). Retires perdition.

## Decision (D21, D22, D23)

- The proxy must be **protocol-aware** (authenticate the IMAP/POP3 login,
  route by `user@domain` to the right backend). nginx mail-proxy and haproxy
  are rejected: they proxy TCP/SNI, not the mail login — they can't route by
  user, which is exactly perdition's job.
- **Dovecot in proxy mode** is the chosen fit (D21). The user could not get a
  working config yet — so a proof-of-concept config is the FIRST deliverable
  of this work package, before any module wiring.
- **Secure ports only** (D22): 993 (IMAPS), 995 (POP3S). No 143/110, no
  STARTTLS on plaintext ports.
- **Every mail container runs dovecot** (D23) — so backends speak the dovecot
  proxy protocol natively (login can be forwarded without re-auth).

## Design

Host-side dovecot as an authenticating proxy (perdition's replacement):

- Host dovecot listens on 993/995, TLS-terminated with the **wildcard cert**
  (G7, D18 — all certs are wildcard).
- A **passdb** returns, per `user@domain`: `proxy=y`, `host=<backend
  container IP>`, `port=`, and pass-through so the backend does the real auth
  (dovecot proxy can forward credentials to the backend dovecot).
- The user→backend map is GENERATED from the datastore (which mail container
  serves which domain — `containers/*.json`), regenerated on the same
  trigger perdition used (container regenerate). Concretely: a dovecot
  `passwd-file` or a `checkpassword`/dict lookup emitted by the mail-proxy
  module's regenerate hook — the srvctl-idiomatic "render config from the
  datastore" pattern, replacing perdition's popmap.re.
- Backend: each mail container's dovecot accepts the proxied connection
  (D23), so no host-side mailbox access — the host only routes.

## Open RISK (must resolve first in the work package)
- Produce a MINIMAL working dovecot proxy config: host dovecot 993/995 →
  one test mail container's dovecot, routing by user@domain, TLS with the
  wildcard cert, credentials forwarded (no double password prompt). This is
  the exact thing that didn't work yet — nail it in isolation before
  building the module around it. Decide passdb mechanism here (passwd-file
  generated from datastore vs checkpassword script vs dict).

## Module shape (after the PoC works)
- v4 module `mailproxy` (replaces perdition): install host dovecot in
  proxy-only mode; render the user→backend map from the datastore on
  regenerate; TLS from the wildcard bundle; manage the 993/995 listeners.
- Perdition module removed after the mailproxy passes on a live-equivalent
  test (VM phase, D26), per the deprecation discipline in 013.

## Migration (per 013)
- Stand up host dovecot proxy on the secure ports in the VM test cluster;
  verify with real mailboxes across two mail containers; then, in the live
  phase, cut the 993/995 listeners from perdition to dovecot-proxy per host
  in one service window; remove perdition after.
