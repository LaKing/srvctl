// modules/letsencrypt/selftest/deploy-rootfs.test.mjs — the wildcard deploy
// into a container rootfs (acmerun deployRootfs) against a hostile container
// root: etc, pki, tls, certs or private replaced by a symlink to a host
// directory, symlinks planted at the temporary file names an earlier
// tmp+rename deploy used, and a FIFO at certs/localhost.crt. Each case runs a
// real wildcard install (primary + serve, fake certbot) in a child process
// and checks that nothing outside the rootfs changed, that the run reported
// an error and that it did not block.
// Run: node modules/letsencrypt/selftest/deploy-rootfs.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { tmpdir, write, writeClusters, fakeCertbot } from "./fixtures.mjs";

const DRIVER = new URL("./acmerun-driver.mjs", import.meta.url).pathname;
const OURS = ["ns1.cdn.test", "ns2.cdn.test"];
const FILES = { private: ["localhost.key"], certs: ["localhost.crt", "a.test.pem", "localhost.pem"] };
let checks = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); checks++; };
const ok = (v, m) => { assert.ok(v, m); checks++; };

function world() {
    const dir = tmpdir("dr-");
    const env = {
        PATH: process.env.PATH,
        SC_ACME_DIR: path.join(dir, "acme"),
        SC_DATASTORE_DIR: path.join(dir, "ds"),
        SC_ADMIN_CERT_DIR: path.join(dir, "admin"),
        SC_LE_LIVE_DIR: path.join(dir, "live"),
        SC_SRV_ROOT: path.join(dir, "srv"),
        SC_CLUSTERS_FILE: writeClusters(dir),
        SC_ACME_HOOK_CONF: path.join(dir, "hook.conf"),
        SC_ACME_HOOK_LOCK: path.join(dir, "hook.lock"),
        SC_ACME_CERTBOT_INI: path.join(dir, "dns01.ini"),
        SC_ACME_KEY_FILE: path.join(dir, "acme.key"),
        SC_LETSENCRYPT_BIN: fakeCertbot(dir),
        SC_DIG_BIN: "/bin/false",
        SC_COMPANY_DOMAIN: "cdn.test",
        SC_ACME_COMMAND: "regenerate",
        FAKE_LE_LOG: path.join(dir, "le.log"),
        SC_TEST_HOSTNAME: "r2.test",
        SC_TEST_SERVED: "a.test",
        SC_TEST_STEPS: "primary,serve",
    };
    write(path.join(env.SC_ACME_DIR, "manifest.snapshot.json"),
        JSON.stringify({ confSha256: "c0ffee", active: true, zones: [{ zone: "a.test", container: "a.test", dns01: true, ns: OURS }] }));
    write(path.join(env.SC_ACME_DIR, "manifest.live.sha256"), "c0ffee  -\n");
    const rootfs = path.join(env.SC_SRV_ROOT, "a.test/rootfs");
    const outside = path.join(dir, "outside");
    return { dir, env, rootfs, pki: path.join(rootfs, "etc/pki/tls"), outside };
}

// A host-side tree that looks like etc/pki/tls with sentinel files, so a
// deploy that followed a symlink into it would find everything it needs.
function hostTree(root) {
    for (const [dir, names] of Object.entries(FILES)) {
        fs.mkdirSync(path.join(root, dir), { recursive: true });
        for (const n of names) write(path.join(root, dir, n), "host sentinel " + n + "\n", 0o640);
    }
}

// path -> { type, mode, size, ino, mtime, text } for everything below dir
function snapshot(dir) {
    const out = {};
    (function walk(d) {
        for (const n of fs.readdirSync(d)) {
            const f = path.join(d, n);
            const st = fs.lstatSync(f);
            out[path.relative(dir, f)] = {
                type: st.isDirectory() ? "dir" : st.isFile() ? "file" : "other",
                mode: st.mode, uid: st.uid, gid: st.gid, ino: st.ino, mtime: st.mtimeMs,
                text: st.isFile() ? fs.readFileSync(f, "utf8") : null,
            };
            if (st.isDirectory()) walk(f);
        }
    })(dir);
    return out;
}

// plant: optional [[file, target]]: symlinks made at <file>.tmp.<pid of the
// child> before the driver runs, the names the tmp+rename deploy used.
function drive(w, plant) {
    const pre = "const fs = require('node:fs');" +
        "for (const [f, t] of JSON.parse(process.env.SC_TEST_PLANT || '[]')) fs.symlinkSync(t, f + '.tmp.' + process.pid);" +
        "import(process.env.SC_TEST_DRIVER);";
    const r = spawnSync("node", ["-e", pre], {
        env: Object.assign({}, w.env, { SC_TEST_DRIVER: DRIVER, SC_TEST_PLANT: JSON.stringify(plant || []) }),
        encoding: "utf8", timeout: 60000,
    });
    return { code: r.status, signal: r.signal, error: r.error, out: r.status === 0 ? JSON.parse(r.stdout) : null, stderr: r.stderr };
}

function alerts(r) {
    const n = r.out && r.out.status.names["a.test"];
    return n ? n.alerts.filter((a) => a.level === "error").map((a) => a.text) : [];
}

function installed(w, r, label) {
    eq(r.code, 0, label + ": run exits 0 without blocking (" + (r.signal || r.error || r.stderr) + ")");
    eq(r.out.states["a.test"].state, "WILDCARD", label + ": wildcard installed");
}

// ------------------------------------------- (1) symlinked directories
const chains = { etc: "", pki: "etc", tls: "etc/pki", private: "etc/pki/tls", certs: "etc/pki/tls" };
for (const comp of ["etc", "pki", "tls", "certs", "private"]) {
    const w = world();
    // the real rootfs tree, then comp swapped for a symlink to a host tree
    const parent = path.join(w.rootfs, chains[comp]);
    for (const dir of Object.keys(FILES)) fs.mkdirSync(path.join(w.pki, dir), { recursive: true });
    const target = path.join(w.outside, comp);
    const below = { etc: "pki/tls", pki: "tls", tls: "", private: "..", certs: ".." }[comp];
    hostTree(path.join(target, below));
    fs.rmSync(path.join(parent, comp), { recursive: true, force: true });
    fs.symlinkSync(target, path.join(parent, comp));
    const before = snapshot(w.outside);

    const r = drive(w);
    installed(w, r, comp + " symlink");
    eq(snapshot(w.outside), before, comp + " symlink: nothing outside the rootfs written, chowned, chmodded or renamed");
    ok(alerts(r).some((t) => /rootfs deploy/.test(t) && /ELOOP|ENOTDIR/.test(t)), comp + " symlink: error reported: " + JSON.stringify(alerts(r)));
    if (comp === "certs") ok(!fs.existsSync(path.join(w.pki, "private/localhost.key")), "certs symlink: no key deployed without its certificate");
}

// ------------------------------------------- (2) symlinks at the temp names
{
    const w = world();
    for (const dir of Object.keys(FILES)) fs.mkdirSync(path.join(w.pki, dir), { recursive: true });
    hostTree(w.outside);
    const plant = [];
    for (const [dir, names] of Object.entries(FILES)) {
        for (const n of names) plant.push([path.join(w.pki, dir, n), path.join(w.outside, dir, n)]);
    }
    const before = snapshot(w.outside);
    const r = drive(w, plant);
    installed(w, r, "temp symlinks");
    eq(snapshot(w.outside), before, "temp symlinks: not followed, nothing outside the rootfs changed");
    for (const [dir, names] of Object.entries(FILES)) {
        for (const n of names) {
            const f = path.join(w.pki, dir, n);
            ok(fs.lstatSync(f).isFile(), "temp symlinks: " + dir + "/" + n + " deployed as a regular file");
        }
    }
    ok(fs.readFileSync(path.join(w.pki, "private/localhost.key"), "utf8").includes("PRIVATE KEY"), "temp symlinks: key deployed inside the rootfs");
    eq((fs.statSync(path.join(w.pki, "private/localhost.key")).mode & 0o777).toString(8), "600", "temp symlinks: key 0600");
    eq((fs.statSync(path.join(w.pki, "certs/localhost.crt")).mode & 0o777).toString(8), "644", "temp symlinks: certificate 0644");
    ok(!fs.readFileSync(path.join(w.pki, "certs/localhost.pem"), "utf8").includes("PRIVATE KEY"), "temp symlinks: certs copy carries no key");

    // and the target names themselves as symlinks to host files
    const w2 = world();
    for (const dir of Object.keys(FILES)) fs.mkdirSync(path.join(w2.pki, dir), { recursive: true });
    hostTree(w2.outside);
    for (const [dir, names] of Object.entries(FILES)) {
        for (const n of names) fs.symlinkSync(path.join(w2.outside, dir, n), path.join(w2.pki, dir, n));
    }
    const before2 = snapshot(w2.outside);
    const r2 = drive(w2);
    installed(w2, r2, "file symlinks");
    eq(snapshot(w2.outside), before2, "file symlinks: not followed, nothing outside the rootfs changed");
    ok(alerts(r2).some((t) => /localhost\.(key|crt)/.test(t) && /ENOTREG|ELOOP/.test(t)), "file symlinks: error reported: " + JSON.stringify(alerts(r2)));
}

// ------------------------------------------- (3) FIFO at certs/localhost.crt
{
    const w = world();
    for (const dir of Object.keys(FILES)) fs.mkdirSync(path.join(w.pki, dir), { recursive: true });
    const fifo = path.join(w.pki, "certs/localhost.crt");
    const mk = spawnSync("mkfifo", [fifo]);
    eq(mk.status, 0, "mkfifo");
    const started = Date.now();
    const r = drive(w);
    installed(w, r, "fifo");
    ok(Date.now() - started < 60000, "fifo: run did not block");
    ok(fs.lstatSync(fifo).isFIFO(), "fifo: left in place, not replaced");
    ok(alerts(r).some((t) => /rootfs deploy skipped/.test(t) && /localhost\.crt/.test(t) && /ENOTREG/.test(t)), "fifo: reported: " + JSON.stringify(alerts(r)));
    ok(!fs.existsSync(path.join(w.pki, "private/localhost.key")), "fifo: deploy skipped, no key written");
}

// ------------------------------------------- (4) normal deploy, no directories created
{
    const w = world();
    fs.mkdirSync(path.join(w.rootfs, "etc"), { recursive: true });
    const r = drive(w);
    installed(w, r, "no pki tree");
    eq(fs.readdirSync(path.join(w.rootfs, "etc")), [], "no pki tree: no directory created inside the rootfs");
    eq(alerts(r), [], "no pki tree: nothing to report");
}

console.log("deploy-rootfs.test.mjs: " + checks + " checks passed");
