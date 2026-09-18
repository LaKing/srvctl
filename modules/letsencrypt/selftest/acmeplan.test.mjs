// modules/letsencrypt/selftest/acmeplan.test.mjs — classification, mapping,
// certbot argument vectors and the node side of the shared wildcard gate.
// P3: the gate called from node with an environment reduced to PATH (as
// letsencrypt.js calls it) gives the same answers as the standalone bash
// gate (P2 in certificates/selftest/wildcard-gate.test.sh).
// Run: node modules/letsencrypt/selftest/acmeplan.test.mjs

import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { REPO, makeCert, makeBundle, tmpdir, write } from "./fixtures.mjs";

const require = createRequire(import.meta.url);
const plan = require("../acmeplan.js");
let checks = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); checks++; };

// --- classification from DNS-scan NS results ------------------------------
eq(plan.classifyNS(["ns1.d250.hu", "ns2.d250.hu"], "d250.hu"), "ours", "both ours");
eq(plan.classifyNS(["NS1.D250.HU.", "ns2.d250.hu."], "d250.hu"), "ours", "case and trailing dot");
eq(plan.classifyNS(["ns1.d250.hu", "ns.other.net"], "d250.hu"), "external", "mixed is external");
eq(plan.classifyNS(["a.iana-servers.net"], "d250.hu"), "external", "external");
eq(plan.classifyNS([], "d250.hu"), "undetermined", "empty scan");
eq(plan.classifyNS(undefined, "d250.hu"), "undetermined", "no scan");
eq(plan.classifyNS(["", " "], "d250.hu"), "undetermined", "blank entries");

eq(plan.classifyDomain({ state: "issued" }, [], "d250.hu").class, "ours/dns01", "issued index entry");
eq(plan.classifyDomain({ state: "not-dns01", reason: "customer _acme-challenge record" },
    ["ns1.d250.hu", "ns2.d250.hu"], "d250.hu").class, "ours/no-cname", "our DNS, no CNAME");
eq(plan.classifyDomain({ state: "not-dns01" }, ["x.example"], "d250.hu").class, "external", "external not-dns01");
eq(plan.classifyDomain(null, ["ns1.d250.hu"], "d250.hu").class, "ours/no-cname", "host name on our DNS without CNAME");
eq(plan.classifyDomain(null, ["x.example"], "d250.hu").class, "external", "host name on external DNS");
eq(plan.classifyDomain(null, undefined, "d250.hu").class, "undetermined", "unscanned host name");

// --- index-name mapping (one label below) ---------------------------------
const names = ["x.test", "a.x.test", "y.test"];
eq(plan.indexNamesFor("x.test", names), ["x.test"], "apex");
eq(plan.indexNamesFor("www.x.test", names), ["x.test"], "www under x.test");
eq(plan.indexNamesFor("b.a.x.test", names), ["a.x.test"], "one label below a.x.test only");
eq(plan.indexNamesFor("c.b.a.x.test", names), [], "two labels below: none");
eq(plan.indexNamesFor("WWW.Y.TEST.", names), ["y.test"], "normalized");

// --- certbot argument vectors ---------------------------------------------
eq(plan.certbotDns01Args("a.test", "/h.sh", false), ["certonly", "--non-interactive", "--agree-tos",
    "--manual", "--preferred-challenges", "dns", "--manual-auth-hook", "/h.sh auth",
    "--manual-cleanup-hook", "/h.sh cleanup", "--cert-name", "srvctl-wildcard-a.test",
    "--keep-until-expiring", "-d", "a.test", "-d", "*.a.test"], "DNS-01 args, dedicated lineage, no --expand/--webroot");
eq(plan.certbotDns01Args("a.test", "/h.sh", true).slice(-1), ["--test-cert"], "staging flag");
eq(plan.certbotDns01Args("a.test", "/h.sh", false, "/etc/letsencrypt/srvctl-dns01.ini").slice(0, 3), ["-c", "/etc/letsencrypt/srvctl-dns01.ini", "certonly"],
    "dedicated certbot config first (-c replaces cli.ini, whose authenticator = webroot conflicts with --manual)");
eq(plan.certbotHostArgs("r2.test", false), ["certonly", "--non-interactive", "--agree-tos", "--keep-until-expiring",
    "--webroot", "--webroot-path", "/var/acme/", "--cert-name", "r2.test", "-d", "r2.test"], "host http-01 args");
eq(plan.certbotDns01Args("a.test", "/h.sh").includes("--expand"), false, "never --expand");

// --- lineage names never collide with the legacy lookup (letsencrypt.js get_le_dir)
const legacy = (domain) => new RegExp("^(www\\.)?" + domain.replace(/\./g, "\\.") + "(-\\d+)?$");
eq(legacy("a.test").test("srvctl-wildcard-a.test"), false, "dedicated lineage invisible to get_le_dir");
eq(legacy("a.test").test("a.test-0001"), true, "legacy lineages still found");

// --- backoff and renewal due ----------------------------------------------
eq(plan.backoffUntil(0, 5), 0, "no failures");
eq(plan.backoffUntil(1, 0), 3600000, "1 h");
eq(plan.backoffUntil(3, 0), 4 * 3600000, "4 h");
eq(plan.backoffUntil(10, 0), 24 * 3600000, "capped at 24 h");
eq(plan.renewalDue(null), true, "no bundle");
eq(plan.renewalDue({ servable: true, daysLeft: 40, lifetimeDays: 90 }), false, "more than a third left");
eq(plan.renewalDue({ servable: true, daysLeft: 29, lifetimeDays: 90 }), true, "less than a third");

// --- P3: node gate with a PATH-only environment == standalone bash gate ----
const dir = tmpdir("p3-");
const ADMIN = path.join(dir, "admin");
const DS = path.join(dir, "ds");
const c1 = makeCert({ cn: "*.x.test", daysAfter: 30 });
write(path.join(ADMIN, "x.test/x.test.pem"), c1.cert + c1.key);
const c2 = makeCert({ cn: "*.old.test", daysBefore: 400, daysAfter: -1 });
write(path.join(ADMIN, "old.test/old.test.pem"), c2.cert + c2.key);
write(path.join(DS, "cert/wildcard/m.test.pem"), makeBundle("m.test"));
write(path.join(DS, "cert/wildcard/short.test.pem"), makeBundle("short.test", { daysAfter: 0.5 }));
const domains = ["x.test", "a.x.test", "a.b.x.test", "old.test", "www.old.test", "m.test", "www.m.test", "short.test"];
const env = { PATH: process.env.PATH, SC_ADMIN_CERT_DIR: ADMIN, SC_DATASTORE_DIR: DS };
const fromNode = plan.wildcardCoveringMany(domains, env);
const gate = path.join(REPO, "modules/certificates/libs/wildcardgatelib.sh");
const fromBash = {};
for (const d of domains) {
    let file = null;
    try {
        file = execFileSync("env", ["-i", "PATH=" + process.env.PATH, "SC_ADMIN_CERT_DIR=" + ADMIN, "SC_DATASTORE_DIR=" + DS,
            "bash", "--noprofile", "--norc", "-uc", 'source "$1"; wildcard_covering "$2"', "_", gate, d],
            { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
    } catch (error) {
        file = null;
    }
    fromBash[d] = file || null;
}
eq(fromNode, fromBash, "P3 node gate equals the standalone bash gate");
eq(Object.keys(fromNode).filter((d) => fromNode[d]).sort(), ["a.x.test", "m.test", "www.m.test", "x.test"],
    "covered set: 30-day admin and servable managed only");
// regression: the old letsencrypt.js check (is_wildcard_certificate) only
// looked for '*' in the subject, so an expired admin wildcard blocked http-01
eq(fromNode["old.test"], null, "expired admin wildcard no longer blocks http-01");
eq(plan.wildcardCovering("x.test", { PATH: process.env.PATH, SC_ADMIN_CERT_DIR: ADMIN }), path.join(ADMIN, "x.test/x.test.pem"),
    "PATH + admin dir only (no SC_DATASTORE_DIR) works");
eq(plan.servableManaged(path.join(DS, "cert/wildcard/m.test.pem"), { PATH: process.env.PATH }), "m.test", "servableManaged");
eq(plan.servableManaged(path.join(DS, "cert/wildcard/short.test.pem"), { PATH: process.env.PATH }), false, "short-lived not servable");

console.log("acmeplan.test: " + checks + " checks passed");
