// modules/srvctl/selftest/commandindex.test.mjs — differential test for the
// command-index parser (lib/commandindex.mjs) against the ACTUAL bash grep
// logic from commonlib.sh, run over every real command file in the repo.
//
// For each command file we run the exact shell pipelines the bash help path
// uses (head|grep -m1 '## @en'; grep -m1 '## @@@' file; grep -m1 '## &&&'
// file; grep '## &en' file | sed; head -20 | grep -q root_only ...) and assert
// the mjs parser extracts identical values. This proves the parser can replace
// the grep storm without changing what `sc help` would show.
//
// Run: node modules/srvctl/selftest/commandindex.test.mjs   (exit != 0 on fail)

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { parseCommandFile } from "../lib/commandindex.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, "..", "..", "..");

// Every module command file (the bash help path iterates these).
const files = [];
for (const mod of fs.readdirSync(path.join(REPO, "modules"))) {
  const cdir = path.join(REPO, "modules", mod, "commands");
  if (!fs.existsSync(cdir)) continue;
  for (const f of fs.readdirSync(cdir)) if (f.endsWith(".sh")) files.push(path.join(cdir, f));
}

let passed = 0;
const failures = [];
function eq(name, got, want) {
  if (JSON.stringify(got) === JSON.stringify(want)) passed++;
  else failures.push({ name, got, want });
}

// The bash reference: run the exact commonlib.sh pipelines for one file.
function bashRef(file) {
  const sh = `
    f=${JSON.stringify(file)}
    hintstr="$(head "$f" | grep -m 1 '## @en')"
    hintcmd="$(head "$f" | grep -m 1 '## @@@' "$f")"
    hintexec="$(head "$f" | grep -m 1 '## &&&' "$f")"
    printf 'HINT\\t%s\\n' "${'${hintstr:7}'}"
    printf 'SYN\\t%s\\n' "${'${hintcmd:7}'}"
    printf 'DYN\\t%s\\n' "${'${hintexec:7}'}"
    grep '## &en' "$f" | sed 's/## &en/    /g' | while IFS= read -r l; do printf 'HELP\\t%s\\n' "$l"; done
    head -n 20 "$f" | grep -q 'root_only' && echo 'ROOT_ONLY' || true
    head -n 20 "$f" | grep -q 'hs_only' && echo 'HS_ONLY' || true
    head -n 20 "$f" | grep -q 'reseller_only' && echo 'RESELLER_ONLY' || true
  `;
  const out = execFileSync("bash", ["-c", sh], { encoding: "utf8" });
  const ref = { hint: null, syntax: null, dynamic: null, help: [], root_only: false, hs_only: false, reseller_only: false };
  for (const line of out.split("\n")) {
    if (line.startsWith("HINT\t")) ref.hint = line.slice(5) || null;
    else if (line.startsWith("SYN\t")) ref.syntax = line.slice(4) || null;
    else if (line.startsWith("DYN\t")) ref.dynamic = line.slice(4) || null;
    else if (line.startsWith("HELP\t")) ref.help.push(line.slice(5));
    else if (line === "ROOT_ONLY") ref.root_only = true;
    else if (line === "HS_ONLY") ref.hs_only = true;
    else if (line === "RESELLER_ONLY") ref.reseller_only = true;
  }
  // bash's `${var:7}` on an empty (unmatched) grep yields "" -> our parser
  // returns null; normalize "" to null so absent markers compare equal.
  if (ref.hint === "") ref.hint = null;
  if (ref.syntax === "") ref.syntax = null;
  if (ref.dynamic === "") ref.dynamic = null;
  return ref;
}

for (const file of files) {
  const parsed = parseCommandFile(fs.readFileSync(file, "utf8"));
  const ref = bashRef(file);
  const rel = path.relative(REPO, file);
  eq(`hint ${rel}`, parsed.hint, ref.hint);
  eq(`syntax ${rel}`, parsed.syntax, ref.syntax);
  eq(`dynamic ${rel}`, parsed.dynamic, ref.dynamic);
  eq(`help ${rel}`, parsed.help, ref.help);
  eq(`perms ${rel}`, [parsed.root_only, parsed.hs_only, parsed.reseller_only], [ref.root_only, ref.hs_only, ref.reseller_only]);
  // Invariant the bash wiring relies on (commonlib.sh hint_on_file): a PRESENT
  // ## @@@ / ## &&& always has a NON-EMPTY value, so bash can treat an empty
  // SC_IDX_SYNTAX/SC_IDX_DYNAMIC as "marker absent" (the grep path's
  // `[[ -z $hintcmd ]]`). A "## @@@" with no value would break that.
  eq(`syntax non-empty-if-present ${rel}`, parsed.syntax === null || parsed.syntax.length > 0, true);
  eq(`dynamic non-empty-if-present ${rel}`, parsed.dynamic === null || parsed.dynamic.length > 0, true);
}

console.log(`commandindex.test: ${passed} checks passed over ${files.length} command files, ${failures.length} failed`);
for (const f of failures) {
  console.log(`  FAIL ${f.name}`);
  console.log(`    parser: ${JSON.stringify(f.got)}`);
  console.log(`    bash:   ${JSON.stringify(f.want)}`);
}
process.exit(failures.length ? 1 : 0);
