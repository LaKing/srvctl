# SRVCTL 4 CAMPAIGN — COVERAGE (module disposition + polish matrix)

Base commit: e179f53 (v3.2.5.9). Sizes measured 2026-07-05.

Disposition (set in Phase A, final decision -for-human where marked):
  keep-port | rewrite | absorb | deprecate | undecided
Fact = discovery fact sheet state: [ ] pending | [x] written
Polish = overnight identical-functionality pass: [ ] pending | [x] committed | [-] skipped

## Core (root-level scripts)

| Unit | Lines | Fact | Polish | Notes |
|------|-------|------|--------|-------|
| srvctl.sh | 135 | [x] | [ ] | entry point |
| init.sh | 192 | [x] | [ ] | module loading, config sourcing |
| commonlib.sh | 506 | [x] | [ ] | core functions |
| lablib.sh | 196 | [x] | [ ] | color/output helpers |
| push.sh | 113 | [x] | [ ] | dev workflow script |
| claude.sh | 2 | [x] | [ ] | trivial |
| server.js, lablib.js, encode.mjs | - | [x] | [ ] | legacy JS, inventory in discovery |
| example-conf/ | - | [x] | [ ] | templates |

## Modules (37)

| Module | sh files | sh lines | cmds | Disposition | Fact | Polish | Notes |
|--------------|-----|------|----|------------------|------|--------|-------|
| backup | 3 | 413 | 0 | keep-port | [x] | [ ] | |
| backupdb | 2 | 38 | 0 | keep-port | [x] | [ ] | |
| branding | 6 | 158 | 0 | keep-port | [x] | [ ] | |
| ca | 6 | 271 | 0 | keep-port | [x] | [ ] | |
| certificates | 6 | 445 | 0 | keep-port | [x] | [ ] | G7 wildcard later |
| codepad | 12 | 324 | 1 | keep-port | [x] | [ ] | |
| containers | 41 | 2309 | 12 | keep-port | [x] | [ ] | biggest module |
| datastore | 9 | 328 | 0 | rewrite (G2, later) | [x] | [ ] | polish now, boilerplate move later |
| default | 2 | 26 | 0 | keep-port | [x] | [ ] | |
| dns | 4 | 22 | 0 | keep-port | [x] | [ ] | |
| firewalld | 7 | 230 | 0 | keep-port | [x] | [ ] | |
| ftp | 3 | 9 | 0 | undecided | [x] | [ ] | tiny |
| gluster | 5 | 424 | 0 | deprecate (G4) | [x] | [ ] | polish minimal |
| gui | 4 | 141 | 0 | deprecate (G5) | [x] | [ ] | cockpit replaces |
| haproxy | 9 | 333 | 2 | keep-port | [x] | [ ] | |
| letsencrypt | 5 | 100 | 0 | keep-port | [x] | [ ] | G7 wildcard later |
| mariadb | 3 | 288 | 0 | keep-port | [x] | [ ] | |
| mozilla | 3 | 42 | 0 | undecided | [x] | [ ] | |
| named | 10 | 326 | 1 | keep-port | [x] | [ ] | G7 DNS-01 later |
| nfs | 5 | 70 | 0 | keep-port | [x] | [ ] | |
| ntp | 2 | 8 | 0 | keep-port | [x] | [ ] | tiny |
| odoo | 2 | 384 | 1 | keep-port | [x] | [ ] | |
| opendkim | 7 | 128 | 0 | keep-port | [x] | [ ] | |
| openvpn | 7 | 371 | 0 | deprecate (G8) | [x] | [ ] | zerotier replaces |
| password | 3 | 70 | 0 | keep-port | [x] | [ ] | |
| perdition | 9 | 134 | 0 | deprecate (G9) | [x] | [ ] | mail proxy replaces |
| postfix | 10 | 173 | 0 | keep-port | [x] | [ ] | |
| saslauthd | 7 | 111 | 2 | keep-port | [x] | [ ] | |
| srvctl | 19 | 994 | 7 | keep-port | [x] | [ ] | self-management module |
| ssh | 8 | 197 | 0 | keep-port | [x] | [ ] | |
| sshpiperd | 5 | 95 | 0 | keep-port | [x] | [ ] | |
| static | 5 | 69 | 0 | keep-port | [x] | [ ] | |
| usersonhost | 9 | 306 | 4 | keep-port | [x] | [ ] | G6 resellers later |
| usersonve | 7 | 445 | 5 | keep-port | [x] | [ ] | add-zerotier.sh untouched (user WIP) |
| ve | 3 | 37 | 1 | keep-port | [x] | [ ] | |
| vncproxy | 23 | 271 | 1 | keep-port | [x] | [ ] | waf/ + demos/ are VENDORED — do not touch |
| wordpress | 3 | 263 | 1 | keep-port | [x] | [ ] | |

Deprecation dispositions are provisional (G-numbers per 000-PROMPT); final
call is the user's. Tonight's polish covers ALL modules uniformly per the
scope amendment, except vendored code and user WIP.
