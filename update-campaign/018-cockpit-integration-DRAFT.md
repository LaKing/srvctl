# 018 — Cockpit as the srvctl GUI (G5) — POSTPONED

Status: POSTPONED 2026-07-05 (D24, D25). Cockpit implementation is deferred;
NOT in the current v4 work scope. Two things still hold from the decisions:
1. The v3 gui daemon module is RETIRED regardless (D7 — "nuke the gui
   module"); only make_commands_spec (JSON command metadata) survives, and
   with the D10 permission model, `sc` itself is the interface (plain `sc`
   shows role-available commands). So no GUI is required for v4.
2. When cockpit is revisited, exposure (D24) and build priority (D25) are the
   open calls — kept below as reference, not active work.

The rest of this doc is retained as reference for the eventual cockpit work;
it is not part of the approved plan set.

---

## (reference only — original draft)

## v3 reality (from modules/gui.md fact sheet)

- The srvctl GUI module is DORMANT: its entire install hook is wrapped in
  `if false` for the whole v3 line — nothing installs the daemon, certs, or
  firewall rule. Only make_commands_spec (command menu metadata) is live.
  Any running srvctl-gui is srvctl2-era leftover.
- Stack would be EOL anyway (AngularJS 1.x, Bootstrap 3, socket.io v2,
  root HTTPS daemon with TLS client-cert auth, exec-over-ssh).
- Retiring it loses nothing users currently have. Decision effectively
  reduces to "what do we build on cockpit".

## Target shape

- Host admin: stock cockpit (Fedora-supported) + cockpit-machines gives
  systemd/journal/storage/network views for free.
- srvctl cockpit package(s), thin by design — cockpit pages are static
  JS/HTML calling cockpit.spawn():
  1. `cockpit-srvctl`: farm overview (containers list from datastore,
     start/stop/login links, per-container status) — wraps `sc` commands;
     policy enforcement stays in srvctl (012), cockpit just runs as the
     logged-in Unix user.
  2. In-container: cockpit installed in containers (or cockpit-bridge via
     `machinectl shell` loopback) so users manage their own VE through the
     host cockpit's remote-host switcher — needs the G11 user model.
- The command-spec generator survives as JSON (one header parser shared
  with sc help, per gui fact sheet v4 note) and feeds the cockpit pages'
  command menus.
- Boilerplate admin UI (datastore browsing/editing, farm-wide views) rides
  the G2 srvctl-modules/datastore instance — complementary, not required
  for v4.0.

## Open questions (for the user)

1. Confirm retiring the v3 gui daemon module (dormant → safe).
2. Cockpit exposure: bind to mesh/VPN only, or public 9090 with auth?
3. Priority: host-admin package first, or user-facing in-container
   management first (affects whether G11 must land before G5)?
