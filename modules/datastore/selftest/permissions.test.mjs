import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { execFileSync, spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../../../", import.meta.url));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sc-permissions-"));
const root = path.join(tmp, "store");
const mode = (file) => fs.statSync(file).mode & 0o777;
const hook = path.join(repo, "modules/datastore/hooks/regenerate.sh");
const env = { ...process.env, SC_INSTALL_DIR: repo, SC_DATASTORE_DIR: root,
  SC_DATASTORE_RO_USE: "false", SC_DATASTORE_RO: "false" };
const run = (overrides = {}) => execFileSync("bash", ["-c", 'source "$1"', "test", hook],
  { env: { ...env, ...overrides } });
try {
  fs.mkdirSync(root, { mode: 0o700 });
  const secret = path.join(tmp, "private.key");
  fs.writeFileSync(secret, "secret", { mode: 0o600 });
  for (const type of ["hosts", "users", "containers"]) {
    const dir = path.join(root, type);
    fs.mkdirSync(dir, { mode: 0o700 });
    fs.writeFileSync(path.join(dir, "sample.json"), "{}\n", { mode: 0o600 });
    fs.writeFileSync(path.join(root, `${type}.json`), "{}\n", { mode: 0o600 });
    fs.mkdirSync(path.join(dir, "sample"), { mode: 0o700 });
    fs.writeFileSync(path.join(dir, "sample/key.json"), "secret", { mode: 0o600 });
    fs.writeFileSync(path.join(dir, ".pending.json"), "private", { mode: 0o600 });
    fs.symlinkSync(secret, path.join(dir, "link.json"));
  }
  for (const flag of ["SC_DATASTORE_RO_USE", "SC_DATASTORE_RO"]) {
    run({ [flag]: "true" });
    assert.equal(mode(root), 0o700);
    assert.equal(mode(path.join(root, "hosts/sample.json")), 0o600);
  }
  run();
  run(); // idempotent
  assert.equal(mode(root), 0o755);
  assert.equal(mode(secret), 0o600);
  for (const type of ["hosts", "users", "containers"]) {
    const dir = path.join(root, type);
    assert.equal(mode(dir), 0o755);
    assert.equal(mode(path.join(dir, "sample.json")), 0o644);
    assert.equal(mode(path.join(root, `${type}.json`)), 0o644);
    assert.equal(fs.readFileSync(path.join(dir, "sample.json"), "utf8"), "{}\n");
    assert.equal(mode(path.join(dir, "sample")), 0o700);
    assert.equal(mode(path.join(dir, "sample/key.json")), 0o600);
    assert.equal(mode(path.join(dir, ".pending.json")), 0o600);
  }
  const failed = spawnSync("bash", ["-c", 'source "$1"', "test", hook],
    { env: { ...env, SC_DATASTORE_DIR: path.join(tmp, "missing") } });
  assert.equal(failed.status, 113);
  console.log("permissions.test: regeneration repair, idempotence, RO guards, private material and error propagation passed");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
