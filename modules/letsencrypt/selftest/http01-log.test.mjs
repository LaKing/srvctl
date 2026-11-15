// Run: node modules/letsencrypt/selftest/http01-log.test.mjs
// HTTP-01 issuance does not depend on /srv/<name>: a domain-only record
// (retire-ve) has no container files, and certbot still runs, for the plain
// and the www name, logging into $SC_ACME_DIR/log. certbot is a stub that
// records its arguments; the DNS-01 phases run against empty fixture dirs.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { REPO, tmpdir, makeCert } from "./fixtures.mjs";

const dir = tmpdir("http01-log-");
let checks = 0;
const ok = (actual, expected, what) => { assert.equal(actual, expected, what); checks++; };
try {
    const ds = path.join(dir, "ds");
    fs.mkdirSync(path.join(ds, "cert"), { recursive: true });
    fs.writeFileSync(path.join(dir, "clusters.json"), JSON.stringify({ c1: { [os.hostname()]: { host_ip: "192.0.2.1" } } }));
    fs.writeFileSync(path.join(ds, "users.json"), "{}");
    const placeholder = makeCert({ cn: "placeholder.test", daysAfter: 3650 });
    const containers = {
        "plain.retired.test": { domain_only: true, web_ve: "web.test", dns: { "plain.retired.test": { A: ["192.0.2.1"], NS: [] } } },
        "site.retired.test": {
            domain_only: true, web_ve: "web.test",
            dns: { "site.retired.test": { A: ["192.0.2.1"], NS: [] }, "www.site.retired.test": { A: ["192.0.2.1"], NS: [] } },
        },
    };
    for (const name of Object.keys(containers)) fs.writeFileSync(path.join(ds, "cert", name + ".pem"), placeholder.key + placeholder.cert);
    fs.writeFileSync(path.join(ds, "containers.json"), JSON.stringify(containers));
    const bin = path.join(dir, "bin");
    fs.mkdirSync(bin);
    const calls = path.join(dir, "certbot-calls");
    fs.writeFileSync(path.join(bin, "letsencrypt"), "#!/bin/sh\necho \"$*\" >> '" + calls + "'\necho certbot-ran\nexit 0\n", { mode: 0o755 });
    for (const b of ["dig", "rsync"]) fs.writeFileSync(path.join(bin, b), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
    const srv = path.join(dir, "srv");

    const out = execFileSync("node", [path.join(REPO, "modules/letsencrypt/letsencrypt.js")], {
        encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
        env: {
            ...process.env, PATH: bin + ":" + process.env.PATH, SC_DATASTORE_DIR: ds,
            SRVCTL_SELFTEST: "true", SRVCTL_SELFTEST_CLUSTERS_FILE: path.join(dir, "clusters.json"),
            SRVCTL_SELFTEST_HOSTNAME: os.hostname(),
            SC_ACME_DIR: path.join(dir, "acme"), SC_CLUSTERS_FILE: path.join(dir, "clusters.json"),
            SC_LE_LIVE_DIR: path.join(dir, "live"), SC_SRV_ROOT: srv,
            SC_ACME_HOOK_LOCK: path.join(dir, "hook.lock"), SC_LETSENCRYPT_BIN: path.join(bin, "letsencrypt"),
            SC_DIG_BIN: path.join(bin, "dig"), SC_RSYNC_BIN: path.join(bin, "rsync"),
        },
    });
    const ran = fs.existsSync(calls) ? fs.readFileSync(calls, "utf8") : "";
    ok((out.match(/Letsencrypt certonly success for /g) || []).length, 2, "certbot succeeds for both records");
    ok(/ -d plain\.retired\.test( |$)/m.test(ran) && !/www\.plain/.test(ran), true, "the plain name is requested alone");
    ok(/-d site\.retired\.test -d www\.site\.retired\.test/.test(ran), true, "the www name is requested with it");
    const log = path.join(dir, "acme", "log");
    ok(fs.readFileSync(path.join(log, "http01-plain.retired.test.log"), "utf8").includes("certbot-ran"), true, "plain log under SC_ACME_DIR/log");
    ok(fs.readFileSync(path.join(log, "http01-www.site.retired.test.log"), "utf8").includes("certbot-ran"), true, "www log under SC_ACME_DIR/log");
    ok(fs.existsSync(srv), false, "no /srv/<name> is created");
    console.log("http01-log: " + checks + " checks passed");
} finally {
    fs.rmSync(dir, { recursive: true, force: true });
}
