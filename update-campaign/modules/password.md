# password — v3 fact sheet (commit 988c38c)

## Purpose
Generates short, human-pronounceable random passwords of the form `Word-Word`
(e.g. `Kelto-Ardu`), built from consonant/vowel alphabets. Provides three parallel
implementations of the same generator: a pure-bash function `get_password`
(libs/get-password.sh), a bash wrapper `new_password` that shells out to Node
(libs/bashlib.sh -> get-password.js), and a Node library `lib.js` that other JS code
`require()`s directly. This is a pure library module — it exposes no CLI commands,
hooks, or configuration; other modules consume it for DB passwords, user account
passwords, and SSL key passphrases.

## Activation
`module-condition.sh` is 3 lines: shebang + `echo true` (module-condition.sh:3).
It is sourced in a command substitution by `test_srvctl_modules`
(commonlib.sh:436), so the module is **unconditionally enabled** on every host and
for every user; `SC_USE_PASSWORD=true` is cached in modules.conf and exported
readonly (commonlib.sh:448, 472-477).

## Commands
-
(No `commands/` directory. `get-password.js` is executable-style (`#!/bin/node`) but is
only invoked via `new_password` in libs/bashlib.sh:8; nothing else in the repo calls it.)

## Hooks
-
(No `hooks/` directory.)

## Libs
| Function / file | Provides | Used by |
|---|---|---|
| `get_password` (libs/get-password.sh:3) | Pure-bash generator using `$RANDOM`; echoes one password to stdout | mariadb (mariadblib.sh:113,150,239), wordpress (install-wordpress.sh:125) |
| `new_password` (libs/bashlib.sh:3) | Runs `/bin/node "$SC_INSTALL_DIR/modules/password/get-password.js"` capturing stdout+stderr, `exif`s on node failure, echoes password | certificates (domaincertlib.sh:133 `ssl_password`), usersonhost (userlib.sh:45), usersonve (add-user.sh:35); commented-out use in ca/calib.sh:165 |
| `lib.js` exports `get_password()` (lib.js:20) | Node generator using `Math.random()` | get-password.js:5, usersonhost/main.js:14 (`require("../password/lib.js")`), main.js:86 |

Both bash functions are auto-sourced into every srvctl shell by `load_libs`
(commonlib.sh:47-66) because the module is always enabled.

Generator shape (identical in JS and bash): each word is either
`UppercaseVowel + consonant(32)` or `UppercaseConsonant(17) + vowel(5) + consonant(17)`,
followed by `vowel + consonant(32) + vowel`; two words joined by `-`.
The bash `ad` array (get-password.sh:7, 32 entries) equals the JS `ad.concat(ar)`
set (lib.js:10-12), so JS and bash produce the same distribution.
Result: 11–15 chars, charset `[A-Za-z-]`, theoretical entropy ~39 bits
(~19.6 bits/word), less in practice due to RNG weaknesses (see Bugs).

## Config & templates
-
(No `conf/` directory; nothing installed anywhere.)

## State touched
- None. All three implementations are side-effect-free generators writing only to
  stdout. Indirect state: `SC_USE_PASSWORD=true` line in
  `/var/local/srvctl/modules.conf` / `~/.srvctl/modules.conf` (written by core,
  commonlib.sh:448).

## Dependencies
- Core helpers: `exif` (lablib.sh:131-145; exits the whole process with the failed
  command's code), `load_libs` sourcing mechanism, `SC_INSTALL_DIR` (srvctl.sh:50).
- External binaries: `/bin/node` (bashlib.sh:8, get-password.js:1 shebang; works on
  Fedora via /bin -> /usr/bin merge).
- Other modules assumed: none. But mariadb, wordpress, certificates, usersonhost,
  usersonve all assume this module's functions exist (safe, since always enabled).

## Bugs & smells
- **high** modules/password/lib.js:5-17 and modules/password/libs/get-password.sh:19-52 —
  Passwords for security-critical credentials (MariaDB users mariadblib.sh:113,150;
  WordPress admin install-wordpress.sh:125; Linux user passwords userlib.sh:45,
  add-user.sh:35, usersonhost/main.js:86; SSL key passphrase domaincertlib.sh:133)
  are generated with non-cryptographic RNGs: V8 `Math.random()` (xorshift128+,
  state recoverable from outputs) and bash `$RANDOM` (15-bit outputs from a small
  internal state). Combined with the ~39-bit theoretical pattern entropy, these
  credentials are feasible offline-cracking targets; the bash variant's effective
  entropy is bounded by the shell RNG seed, well below the pattern space.
- **medium** modules/password/libs/bashlib.sh:8 — `2>&1` merges node's stderr into
  the captured value. Any node warning that does not change the exit code (e.g.
  `NODE_OPTIONS`-induced or Experimental/Deprecation warnings) is silently
  concatenated into the "password", which is then written into DB grants, user
  accounts, or SSL configs — corrupted credential, no error raised.
- **low** modules/password/libs/bashlib.sh:9 — failure message is
  `"SSH-ERROR cfg $* ($?) $__result"`, copy-pasted from an SSH lib; when node is
  missing/broken, srvctl exits with a message about SSH, misleading diagnosis.
- **low** modules/password/libs/get-password.sh:13-17 — `adl aal arl bbl bcl` are
  assigned without `local` (only the arrays and `ra0 ra1 p` are localized at line 5),
  so five global variables leak into every srvctl shell each time a password is
  generated, and would silently clobber same-named caller variables.
- Smell: modules/password/libs/bashlib.sh:8 forwards `$*` to get-password.js, which
  ignores all arguments (get-password.js:5-6) — dead parameter plumbing.
- Smell: three implementations of one generator (lib.js, get-password.sh,
  plus the node-spawning wrapper new_password), with consumers split arbitrarily
  between them; `new_password` pays a full node startup per password for no gain
  over the in-shell `get_password`.
- Smell: neither lib has the `[[ $SRVCTL ]] || exit 10` guard mandated by CLAUDE.md
  (libs/bashlib.sh:1, libs/get-password.sh:1); harmless today since sourcing only
  defines functions.

## Polish risks
- Function names `get_password` and `new_password` are cross-module API, called by
  name from mariadblib.sh:113,150,239; install-wordpress.sh:125; userlib.sh:45;
  add-user.sh:35; domaincertlib.sh:133. Both must remain defined after `load_libs`.
- `require("../password/lib.js")` at usersonhost/main.js:14 pins the file path
  `modules/password/lib.js` and the export name `get_password` (lib.js:20).
- `new_password` invokes exactly `/bin/node "$SC_INSTALL_DIR/modules/password/get-password.js"`
  (bashlib.sh:8) — path is load-bearing until that call site changes too.
- Output contract: a single line on stdout, no whitespace, charset `[A-Za-z-]`,
  pattern `Word-Word` (lib.js:15-17, get-password.sh:24-55). Downstream embeds the
  value unquoted/unescaped in SQL statements and config files, so introducing
  shell-, SQL-, or config-special characters in a rewrite would break consumers.
- Failure contract: on node error `new_password` terminates the whole srvctl run
  via `exif` with node's exit code (bashlib.sh:9, lablib.sh:143); callers do not
  handle failure themselves.
- `module-condition.sh` must emit exactly the string `true` (compared at
  commonlib.sh:437) so `SC_USE_PASSWORD=true` lands in modules.conf; the cached
  variable name `SC_USE_PASSWORD` is derived from the directory name `password`.

## v4 notes
- Collapse the three implementations into one: a single `.mjs` export using
  `crypto.randomInt()` (or `crypto.getRandomValues`), plus optionally a thin bash
  shim if bash-only call sites survive; the JS and bash alphabets are already
  provably identical (bash `ad` == JS `ad.concat(ar)`), so one table suffices.
- Consider a length/entropy parameter — the dead `$*` plumbing in bashlib.sh:8
  suggests one was once intended.
- Decide policy: pronounceable ~39-bit passwords are fine as *initial* throwaway
  credentials but not for long-lived DB/SSL secrets; v4 could offer
  `get_password({strong: true})` and migrate certificates/mariadb call sites.
- Module is a good candidate for absorption into a core `util` library rather than
  remaining a standalone always-on module with a trivial `echo true` condition.
