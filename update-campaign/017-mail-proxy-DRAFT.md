# 017 — POP3S/IMAP4S reverse proxy replacing perdition (G9) — DRAFT for review

Status: DRAFT written session 1 (autonomous). Not approved.

## v3 reality (from modules/perdition.md fact sheet)

- Perdition proxies IMAP4/IMAP4S/POP3S on hosts, routing user logins to
  the right mail.<domain> container's dovecot via popmap.re regenerated
  from containers.json.
- The module is HALF-ABANDONED in v3: install_perdition is disabled from
  update-install-host, config contradictions (no_lookup vs popmap), dead
  units — matching the deprecation decision (G9).
- Routing key: the USER's login domain (user@domain), not SNI alone.

## Candidates

1. nginx mail proxy (mail module + auth_http): mature, routes by login
   (auth_http returns backend per user@domain), TLS termination with the
   wildcard cert (G7 synergy), tiny config template from containers.json.
   RECOMMENDED.
2. haproxy SNI passthrough: no login-based routing; works only if every
   mail domain has a distinct SNI name AND containers terminate TLS
   themselves; haproxy already fronts the farm (module exists) — lowest
   new-component count but couples mail routing to cert layout.
3. dovecot proxy/director: full-featured but heaviest; introduces a host
   dovecot instance just to proxy.
4. sslh: protocol demultiplexer, not a mail router — not fit.

## Proposed shape (pending user pick)

- v4 module `mailproxy`: installs nginx (mail context only, distinct
  ports/unit), renders upstream map from containers.json on regenerate
  (same trigger as perdition's popmap hook), auth_http as a ~40-line
  endpoint in the datastore service or a static map file generator.
- TLS: wildcard bundle from G7; per-domain certs supported via SNI certs
  directory as fallback.
- Migration per 013: run on alternate ports first, verified with real
  mailboxes, then swap the 993/995 (and 143 if kept) listeners from
  perdition to mailproxy in one service window per host; perdition module
  removed after all hosts switch.

## Open questions (for the user)

1. Confirm candidate 1 (nginx mail proxy) or argue for haproxy-only.
2. Is plaintext IMAP4 (143, STARTTLS?) still needed, or S-only ports?
3. Do all mail containers run dovecot with user@domain logins as perdition
   assumed? Any POP3 (110) legacy clients left?
