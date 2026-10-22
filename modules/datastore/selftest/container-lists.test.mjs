// modules/datastore/selftest/container-lists.test.mjs — users/readers/vncusers
// stay lists. A put once stored users as a string; usersonhost/main.js then
// mounted the container into the homes of m, 1 (bin, /bin), r and 0 (root),
// one more stacked bindfs on every hourly regenerate.
// Run: node modules/datastore/selftest/container-lists.test.mjs

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createStore } from "../lib/store.mjs";
import { migrateToPerEntity } from "../lib/migrate.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LIB = path.join(HERE, "..", "lib.js");
const MAIN = path.join(HERE, "..", "main.mjs");
const FIXTURE = path.join(HERE, "golden", "fixture");

let failed = 0;
function test(name, fn) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sc-lists-"));
    try {
        const src = fs.mkdtempSync(path.join(os.tmpdir(), "sc-lists-mono-"));
        for (const f of ["hosts.json", "users.json", "containers.json"]) fs.copyFileSync(path.join(FIXTURE, f), path.join(src, f));
        migrateToPerEntity(src, createStore(dir, { git: false }));
        fs.rmSync(src, { recursive: true, force: true });
        fn(dir);
        console.log("  ok  " + name);
    } catch (e) {
        failed++;
        console.log("  FAIL " + name + ": " + e.message);
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
}

const env = (dir) => ({
    ...process.env,
    SC_DATASTORE_DIR: dir,
    SC_DATASTORE_RO: "",
    SC_USER: "root",
    SC_HOSTNET: "20",
    SRVCTL_SELFTEST: "true",
    SRVCTL_SELFTEST_CLUSTERS_FILE: path.join(FIXTURE, "cluster-topology.fixture.json"),
    SRVCTL_SELFTEST_HOSTNAME: "node1",
});

function patchContainer(dir, C, fields) {
    const file = path.join(dir, "containers", C + ".json");
    fs.writeFileSync(file, JSON.stringify({ ...JSON.parse(fs.readFileSync(file, "utf8")), ...fields }, null, 2) + "\n");
}

function loadFields(dir, C) {
    const code =
        `const c = require(${JSON.stringify(LIB)}).containers[${JSON.stringify(C)}];` +
        `console.log(JSON.stringify({ users: c.users, readers: c.readers, vncusers: c.vncusers }));`;
    const r = spawnSync(process.execPath, ["-e", code], { env: env(dir), encoding: "utf8" });
    assert.equal(r.status, 0, r.stderr);
    return JSON.parse(r.stdout.trim().split("\n").pop());
}

const C = "site.example.com";

test("lib.js reads a string users/readers/vncusers as one name", (dir) => {
    patchContainer(dir, C, { users: "m1r0", readers: "viewer", vncusers: "vnc" });
    assert.deepEqual(loadFields(dir, C), { users: ["m1r0"], readers: ["viewer"], vncusers: ["vnc"] });
});

test("lib.js leaves arrays untouched", (dir) => {
    patchContainer(dir, C, { users: ["a", "b"] });
    assert.deepEqual(loadFields(dir, C).users, ["a", "b"]);
});

test("put refuses list fields that have a writer, keeps the record", (dir) => {
    for (const field of ["users", "vncusers", "aliases", "mapped_ports"]) {
        const before = fs.readFileSync(path.join(dir, "containers", C + ".json"), "utf8");
        const r = spawnSync(process.execPath, [MAIN, "put", "container", C, field, "m1r0"], { env: env(dir), encoding: "utf8" });
        assert.notEqual(r.status, 0, field + " was accepted");
        assert.match(r.stderr + r.stdout, /IS A LIST, USE:/);
        assert.equal(fs.readFileSync(path.join(dir, "containers", C + ".json"), "utf8"), before, field + " changed the record");
    }
});

test("put still deletes a list field", (dir) => {
    patchContainer(dir, C, { users: ["a"] });
    const r = spawnSync(process.execPath, [MAIN, "put", "container", C, "users"], { env: env(dir), encoding: "utf8" });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(JSON.parse(fs.readFileSync(path.join(dir, "containers", C + ".json"), "utf8")).users, undefined);
});

console.log(failed ? `container-lists: ${failed} failed` : "container-lists: all passed");
process.exit(failed ? 1 : 0);
