# SRVCTL 4 CAMPAIGN — COVERAGE (module disposition + polish matrix)

Base commit: e179f53 (v3.2.5.9). Sizes measured 2026-07-05.

Disposition (set in Phase A, final decision -for-human where marked):
  keep-port | rewrite | absorb | deprecate | undecided
Fact = discovery fact sheet state: [ ] pending | [x] written
Polish = overnight identical-functionality pass: [ ] pending | [x] committed | [-] skipped

## Core (root-level scripts)

| Unit | Lines | Fact | Polish | Notes |
|------|-------|------|--------|-------|
| srvctl.sh | 135 | [ ] | [ ] | entry point |
| init.sh | 192 | [ ] | [ ] | module loading, config sourcing |
| commonlib.sh | 506 | [ ] | [ ] | core functions |
| lablib.sh | 196 | [ ] | [ ] | color/output helpers |
| push.sh | 113 | [ ] | [ ] | dev workflow script |
| claude.sh | 2 | [ ] | [ ] | trivial |
| server.js, lablib.js, encode.mjs | - | [ ] | [ ] | legacy JS, inventory in discovery |
| example-conf/ | - | [ ] | [ ] | templates |

## Modules (37)

| Module | sh files | sh lines | cmds | Disposition | Fact | Polish | Notes |
|--------------|-----|------|----|------------------|------|--------|-------|
| backup | 3 | 413 | 0 | keep-port | [ ] | [ ] | |
| backupdb | 2 | 38 | 0 | keep-port | [ ] | [ ] | |
| branding | 6 | 158 | 0 | keep-port | [ ] | [ ] | |
| ca | 6 | 271 | 0 | keep-port | [ ] | [ ] | |
| certificates | 6 | 445 | 0 | keep-port | [ ] | [ ] | G7 wildcard later |
| codepad | 12 | 324 | 1 | keep-port | [ ] | [ ] | |
| containers | 41 | 2309 | 12 | keep-port | [ ] | [ ] | biggest module |
| datastore | 9 | 328 | 0 | rewrite (G2, later) | [ ] | [ ] | polish now, boilerplate move later |
| default | 2 | 26 | 0 | keep-port | [ ] | [ ] | |
| dns | 4 | 22 | 0 | keep-port | [ ] | [ ] | |
| firewalld | 7 | 230 | 0 | keep-port | [ ] | [ ] | |
| ftp | 3 | 9 | 0 | undecided | [ ] | [ ] | tiny |
| gluster | 5 | 424 | 0 | deprecate (G4) | [ ] | [ ] | polish minimal |
| gui | 4 | 141 | 0 | deprecate (G5) | [ ] | [ ] | cockpit replaces |
| haproxy | 9 | 333 | 2 | keep-port | [ ] | [ ] | |
| letsencrypt | 5 | 100 | 0 | keep-port | [ ] | [ ] | G7 wildcard later |
| mariadb | 3 | 288 | 0 | keep-port | [ ] | [ ] | |
| mozilla | 3 | 42 | 0 | undecided | [ ] | [ ] | |
| named | 10 | 326 | 1 | keep-port | [ ] | [ ] | G7 DNS-01 later |
| nfs | 5 | 70 | 0 | keep-port | [ ] | [ ] | |
| ntp | 2 | 8 | 0 | keep-port | [ ] | [ ] | tiny |
| odoo | 2 | 384 | 1 | keep-port | [ ] | [ ] | |
| opendkim | 7 | 128 | 0 | keep-port | [ ] | [ ] | |
| openvpn | 7 | 371 | 0 | deprecate (G8) | [ ] | [ ] | zerotier replaces |
| password | 3 | 70 | 0 | keep-port | [ ] | [ ] | |
| perdition | 9 | 134 | 0 | deprecate (G9) | [ ] | [ ] | mail proxy replaces |
| postfix | 10 | 173 | 0 | keep-port | [ ] | [ ] | |
| saslauthd | 7 | 111 | 2 | keep-port | [ ] | [ ] | |
| srvctl | 19 | 994 | 7 | keep-port | [ ] | [ ] | self-management module |
| ssh | 8 | 197 | 0 | keep-port | [ ] | [ ] | |
| sshpiperd | 5 | 95 | 0 | keep-port | [ ] | [ ] | |
| static | 5 | 69 | 0 | keep-port | [ ] | [ ] | |
| usersonhost | 9 | 306 | 4 | keep-port | [ ] | [ ] | G6 resellers later |
| usersonve | 7 | 445 | 5 | keep-port | [ ] | [ ] | add-zerotier.sh untouched (user WIP) |
| ve | 3 | 37 | 1 | keep-port | [ ] | [ ] | |
| vncproxy | 23 | 271 | 1 | keep-port | [ ] | [ ] | waf/ + demos/ are VENDORED — do not touch |
| wordpress | 3 | 263 | 1 | keep-port | [ ] | [ ] | |

Deprecation dispositions are provisional (G-numbers per 000-PROMPT); final
call is the user's. Tonight's polish covers ALL modules uniformly per the
scope amendment, except vendored code and user WIP.
