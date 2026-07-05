# 005 — Polish agent brief (session 1)

The exact working instructions given to every module polish agent. The
binding rules live in 002-polish-conventions.md; this adds the mechanics
and the position-sensitivity constraints discovered in core.

## Read order (mandatory)

1. update-campaign/002-polish-conventions.md — binding contract
2. CLAUDE.md — codebase conventions
3. update-campaign/modules/<module>.md — fact sheet: "Polish risks" =
   must-not-change; "Bugs & smells" = FIXME(v4) candidates
4. every file of modules/<module>/ (respecting exclusions)

## Position-sensitivity rules (CRITICAL — learned from core analysis)

- In commands/*.sh and command.sh: add NOTHING above the existing help
  metadata block. `## @en` must stay within the first 10 lines; permission
  markers (root_only / hs_only / reseller_only / ve_only) must stay within
  the first 20 lines — both as markers AND as function calls.
- hint_on_file greps some markers across the WHOLE file: never write the
  literal sequences `## @@@`, `## &&&`, `## @en`, `## &en` inside any
  comment you add (describe them in words instead). A stray `## &&&` line
  gets EXECUTED during help listing.
- Never write the words root_only / hs_only / reseller_only / ve_only in
  added comments within the first 20 lines of a command file that does not
  already use them (they would hide the command from hints).

## Verification (every agent, before returning)

- bash -n on every changed .sh
- shellcheck (scratchpad binary, path given in the task) on the module's
  .sh files BEFORE and AFTER — issue count must not increase
- node --check on any .js/.mjs touched (comment-only changes allowed there)

## Hard exclusions

- modules/vncproxy/waf/, modules/vncproxy/vncproxy/, any demos/ or
  node_modules (vendored)
- modules/usersonve/commands/add-zerotier.sh (user WIP)
- anything outside your assigned module directory
- git state changes; running srvctl; anything that touches the live system
