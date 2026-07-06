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

// CLI: node commandindex.mjs <command-file.sh> ...  ->  JSON index on stdout.
if (import.meta.url === `file://${process.argv[1]}`) {
  const fs = await import("node:fs");
  const files = process.argv.slice(2);
  if (!files.length) {
    console.error("usage: node commandindex.mjs <command-file.sh> ...");
    process.exit(2);
  }
  const index = buildIndex(files, (p) => fs.readFileSync(p, "utf8"));
  process.stdout.write(JSON.stringify(index, null, 2) + "\n");
}
