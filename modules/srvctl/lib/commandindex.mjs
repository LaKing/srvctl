// modules/srvctl/lib/commandindex.mjs — parse srvctl command-file help metadata
// into a structured index, to replace the per-file grep storm that
// commonlib.sh's hint_on_file/help_on_file run on every `sc help` / bare `sc`
// (~190 forks over 38 command files — see 010 G1). This module is the parser;
// wiring it into the bash help path is a separate step (needs the srvctl
// runtime / VM to validate byte-identical output — see 100-work-packages WP-D).
//
// Semantics are a FAITHFUL match of commonlib.sh's grep logic (verified by
// selftest/commandindex.test.mjs against the real bash commands):
//   hint    (## @en) : FIRST match within the first 10 lines (head|grep -m1)
//   syntax  (## @@@) : FIRST match in the WHOLE file (bash greps with a file
//                      operand, so the head pipe is ignored — reproduced)
//   dynamic (## &&&) : FIRST match in the WHOLE file (add-ve.sh relies on this
//                      at line 13, beyond head -10)
//   help    (## &en) : ALL matches in the whole file, marker -> 4 spaces
//   perms            : root_only / hs_only / reseller_only substring in the
//                      first 20 lines
// Value extraction mirrors bash ${str:7}: drop the 6-char marker + 1 space.

const HINT = "## @en";
const HEMP = "## @@@";
const HEXE = "## &&&";
const HELP = "## &en";

// bash `${str:7}` — the marker is 6 chars, +1 space; slice from index 7.
function afterMarker(line) {
  return line.slice(7);
}

// Parse one command file's contents into its help metadata.
export function parseCommandFile(content) {
  const lines = content.split("\n");
  const head10 = lines.slice(0, 10);
  const head20 = lines.slice(0, 20);

  const firstContaining = (arr, marker) => arr.find((l) => l.includes(marker));

  const hintLine = firstContaining(head10, HINT);
  const synLine = firstContaining(lines, HEMP);
  const dynLine = firstContaining(lines, HEXE);

  const help = lines
    .filter((l) => l.includes(HELP))
    .map((l) => l.split(HELP).join("    ")); // sed s/## &en/    /g

  const headText = head20.join("\n");

  return {
    hint: hintLine === undefined ? null : afterMarker(hintLine),
    syntax: synLine === undefined ? null : afterMarker(synLine),
    dynamic: dynLine === undefined ? null : afterMarker(dynLine),
    help,
    root_only: headText.includes("root_only"),
    hs_only: headText.includes("hs_only"),
    reseller_only: headText.includes("reseller_only"),
  };
}

// Build the index for a list of command-file paths: { command-name: metadata }.
// `readFile(path)` returns the file's contents (injected so parseCommandFile
// stays dependency-free). The command name is the basename minus ".sh" (bash:
// ${command:0: -3}); passing files in SC_MODULES order makes later modules win
// on duplicate names, matching the bash help path.
export function buildIndex(files, readFile) {
  const index = {};
  for (const p of files) {
    const name = p.replace(/^.*\//, "").replace(/\.sh$/, "");
    index[name] = { file: p, ...parseCommandFile(readFile(p)) };
  }
  return index;
}

// Emit the index in a tab-delimited, path-keyed form for bash to read in ONE
// node call (replacing commonlib.sh's per-file grep storm). One "F" line of
// scalar metadata per file, then one "H" line per help line, in file order:
//   F\t<path>\t<hint>\t<syntax>\t<dynamic>\t<root_only>\t<hs_only>\t<reseller_only>
//   H\t<path>\t<help-line>
// Scalars are empty when the marker is absent; booleans are "1"/"". Command
// files never contain tabs in these markers, so tab is a safe delimiter.
export function formatBash(index) {
  const out = [];
  const b = (v) => (v ? "1" : "");
  for (const path of Object.keys(index)) {
    const m = index[path];
    out.push(["F", path, m.hint ?? "", m.syntax ?? "", m.dynamic ?? "", b(m.root_only), b(m.hs_only), b(m.reseller_only)].join("\t"));
    for (const h of m.help) out.push(["H", path, h].join("\t"));
  }
  return out.join("\n") + (out.length ? "\n" : "");
}

// CLI:
//   node commandindex.mjs --bash <file.sh> ...   -> tab-delimited (bash reader)
//   node commandindex.mjs <file.sh> ...          -> JSON (keyed by command name)
if (import.meta.url === `file://${process.argv[1]}`) {
  const fs = await import("node:fs");
  const argv = process.argv.slice(2);
  const bash = argv[0] === "--bash";
  const files = bash ? argv.slice(1) : argv;
  if (!files.length) {
    console.error("usage: node commandindex.mjs [--bash] <command-file.sh> ...");
    process.exit(2);
  }
  const read = (p) => fs.readFileSync(p, "utf8");
  if (bash) {
    // path-keyed index preserving argv order
    const index = {};
    for (const p of files) index[p] = parseCommandFile(read(p));
    process.stdout.write(formatBash(index));
  } else {
    process.stdout.write(JSON.stringify(buildIndex(files, read), null, 2) + "\n");
  }
}
