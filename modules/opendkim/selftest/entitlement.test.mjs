// modules/opendkim/selftest/entitlement.test.mjs — the signing-entitlement
// tables (lib/entitlement.js): entitled container/domain pairs are in,
// cross-tenant pairs are out, loopback gets only the host's own domains, and
// the output is deterministic.
// Run:  node modules/opendkim/selftest/entitlement.test.mjs   (exit != 0 on fail)

import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { entitlement, tables, selector } = require("../lib/entitlement.js");

const ctx = {
  hosts: { "r2.example.net": {}, "p2.example.net": {} },
  SC_COMPANY_DOMAIN: "example.net",
  containers: {
    "a.test": { ip: "10.20.1.2", aliases: ["www.a.test", "b.test"] },  // b.test: B's own name
    "b.test": { ip: "10.20.1.3" },
    "mail.c.test": { ip: "10.20.1.4" },                                 // owns c.test
    "c.test": { ip: "10.20.1.5", mail_ve: "mx.test" },                  // hands c.test to mx.test
    "mx.test": { ip: "10.20.1.6" },
    "Upper.Test": { ip: "10.20.1.7" },
    "shop.devel": { ip: "10.20.1.8" },                                  // no key: never signed
    "noip.test": {},                                                    // no ip: no line
    "example.net": { ip: "10.20.1.9" },                                 // company domain
    "r2.example.net": { ip: "10.20.1.10" },                             // a host name with a key
  },
};

const e = entitlement(ctx);
const has = (l) => e.entitled.includes(l);

// AC2: a container signs what it owns ...
assert.ok(has("10.20.1.2/a.test"), "A signs its own name");
assert.ok(has("10.20.1.3/b.test"), "B signs its own name");
assert.ok(has("10.20.1.4/mail.c.test"), "mail.C signs its own name");
assert.ok(has("10.20.1.4/c.test"), "mail.X owns X");
assert.ok(has("10.20.1.6/c.test"), "mail_ve target owns the handed-over domain");
assert.ok(has("10.20.1.5/c.test"), "the handing container keeps its own name");
assert.ok(has("10.20.1.7/upper.test"), "names are lowercased");
// ... and nothing else
assert.ok(!has("10.20.1.2/b.test"), "an alias never grants another container's own name (cross-tenant)");
assert.ok(!has("10.20.1.3/a.test"), "B does not sign A");
assert.ok(!has("10.20.1.2/c.test") && !has("10.20.1.3/c.test"), "nobody else signs c.test");
assert.ok(!e.entitled.some((l) => l.endsWith("/shop.devel")), "devel containers have no key and no line");
assert.ok(!e.entitled.some((l) => l.endsWith("/noip.test")), "a container without ip gets no line");
assert.ok(!e.entitled.some((l) => l.endsWith("/www.a.test")), "an alias without a key is never signable");
const of = (ip) => e.entitled.filter((l) => l.startsWith(ip + "/")).map((l) => l.split("/")[1]);
assert.deepEqual(of("10.20.1.2"), ["a.test"], "A signs only a.test");
assert.deepEqual(of("10.20.1.3"), ["b.test"], "B signs only b.test");
assert.deepEqual(of("10.20.1.6"), ["c.test", "mx.test"], "mail_ve target: own name plus the hand-over");

// AC5: loopback (pickup, root) signs the host's own domains only
assert.deepEqual(e.host, ["example.net", "r2.example.net"]);
assert.ok(has("127.0.0.1/example.net") && has("::1/example.net"), "loopback signs the company domain");
assert.ok(has("127.0.0.1/r2.example.net"), "loopback signs a host name that has a key");
assert.ok(!has("127.0.0.1/a.test") && !has("::1/b.test"), "loopback does not sign tenant domains");
assert.ok(!e.signable.includes("p2.example.net"), "a host name without a key is not signable");

// files
const t = tables(e);
assert.match(t.HostSigningTable, /^\*@example\.net default\._domainkey\.example\.net$/m);
assert.doesNotMatch(t.HostSigningTable, /a\.test/);
assert.match(t.EntitledSigners, /^10\.20\.1\.2\/a\.test$/m);
assert.doesNotMatch(t.EntitledSigners, /^10\.20\.1\.2\/b\.test$/m);
assert.equal(t.InternalHosts.split("\n").filter((l) => l && !l.startsWith("#")).join(","), "127.0.0.1,::1");
assert.equal(t.EmptySigningTable.split("\n").filter((l) => l && !l.startsWith("#")).length, 0);
assert.ok(t.SignableDomains.includes("\nmail.c.test\n"));
assert.equal(selector("mail.c.test"), "mail");
assert.equal(selector("c.test"), "default");

// AC6: deterministic, independent of record order
const shuffled = { ...ctx, containers: Object.fromEntries(Object.entries(ctx.containers).reverse()) };
assert.deepEqual(tables(entitlement(shuffled)), t, "same tables for the same records");
assert.deepEqual(tables(entitlement(ctx)), t, "byte-identical second generation");

console.log("All opendkim entitlement tests passed.");
