// modules/datastore/selftest/list.test.mjs — the list verb: every record of a
// type in one process, each field exactly as `get` returns it.
// Run: node modules/datastore/selftest/list.test.mjs

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createStore } from "../lib/store.mjs";
import { migrateToPerEntity } from "../lib/migrate.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MAIN = path.join(HERE, "..", "main.mjs");
const FIXTURE = path.join(HERE, "golden", "fixture");

let failed = 0;
function test(name, fn) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sc-list-"));
    try {
        const src = fs.mkdtempSync(path.join(os.tmpdir(), "sc-list-mono-"));
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

function verb(dir, ...args) {
    const env = {
        ...process.env,
        SC_DATASTORE_DIR: dir,
        SC_USER: "root",
        SC_HOSTNET: "20",
        SRVCTL_SELFTEST: "true",
        SRVCTL_SELFTEST_CLUSTERS_FILE: path.join(FIXTURE, "cluster-topology.fixture.json"),
        SRVCTL_SELFTEST_HOSTNAME: "node1",
    };
    return spawnSync(process.execPath, [MAIN, ...args], { env, encoding: "utf8" });
}

function rows(dir, ...args) {
    const r = verb(dir, "list", ...args);
    assert.equal(r.status, 0, r.stderr);
    return r.stdout === "" ? [] : r.stdout.replace(/\n$/, "").split("\n").map((line) => line.split("\t"));
}

function patchContainer(dir, C, fields) {
    const file = path.join(dir, "containers", C + ".json");
    fs.writeFileSync(file, JSON.stringify({ ...JSON.parse(fs.readFileSync(file, "utf8")), ...fields }, null, 2) + "\n");
}

const C = "site.example.com";

test("every cell equals what get returns, stored and derived", (dir) => {
    const fields = ["user", "ip", "host", "user_ip_match", "hostnet", "reseller", "quota"];
    const listed = rows(dir, "container", ...fields);
    assert.equal(listed.length, 3);
    for (const [id, ...cells] of listed) {
        fields.forEach((field, i) => {
            const got = verb(dir, "get", "container", id, field);
            assert.equal(got.status, 0, id + " " + field + ": " + got.stderr);
            assert.equal(cells[i], got.stdout.trimEnd(), id + " " + field);
        });
    }
});

test("without fields it prints the ids, in container_list order", (dir) => {
    const ids = rows(dir, "container").map((row) => row[0]);
    assert.deepEqual(ids, verb(dir, "get", "cluster", "container_list").stdout.trim().split(" "));
});

test("an unset value is a dash, so no cell is empty", (dir) => {
    patchContainer(dir, C, { cpu_quota: "200%" });
    const byId = Object.fromEntries(rows(dir, "container", "memory_max", "cpu_quota").map(([id, ...cells]) => [id, cells]));
    assert.deepEqual(byId[C], ["-", "200%"]);
    assert.deepEqual(byId["shop.example.com"], ["-", "-"]);
});

test("a list field is one JSON cell", (dir) => {
    const byId = Object.fromEntries(rows(dir, "container", "aliases").map(([id, cell]) => [id, cell]));
    assert.equal(byId["shop.example.com"], '["store.example.com"]');
});

test("a multi-line field is refused per cell with a warning, the rows stay", (dir) => {
    const r = verb(dir, "list", "container", "nspawn", "ip");
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stderr, /LIST-WARNING: container site\.example\.com nspawn/);
    assert.ok(r.stdout.split("\n").includes([C, "-", "10.20.1.5"].join("\t")), r.stdout);
});

test("a record whose field cannot be derived does not hide the others", (dir) => {
    patchContainer(dir, C, { user: "nobody-here" });
    const r = verb(dir, "list", "container", "user_ip_match");
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stderr, /LIST-WARNING: container site\.example\.com user_ip_match/);
    const byId = Object.fromEntries(r.stdout.trimEnd().split("\n").map((line) => line.split("\t")));
    assert.equal(byId[C], "-");
    assert.equal(byId["shop.example.com"], "true");
});

test("users and hosts are listable, other types are refused", (dir) => {
    const users = rows(dir, "user", "uid", "user_id");
    assert.equal(users.length, 3);
    for (const [id, uid] of users) assert.equal(uid, verb(dir, "get", "user", id, "uid").stdout.trimEnd());
    assert.ok(rows(dir, "host", "hostnet").length >= 1);
    const refused = verb(dir, "list", "cluster");
    assert.equal(refused.status, 110);
    assert.equal(refused.stdout, "");
});

test("an empty type prints nothing", (dir) => {
    for (const f of fs.readdirSync(path.join(dir, "containers"))) fs.rmSync(path.join(dir, "containers", f));
    assert.deepEqual(rows(dir, "container", "ip"), []);
});

console.log(failed ? `list: ${failed} failed` : "list: all passed");
process.exit(failed ? 1 : 0);
