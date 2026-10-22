// modules/haproxy/selftest/siteredirect.test.mjs — set-ve-redirect rendering:
// both names, location (no path appended), 301/302, the .well-known exception,
// refusal of values that would break or inject into haproxy.cfg, and its place
// at the head of both frontends in haproxy.js.
// Run: node modules/haproxy/selftest/siteredirect.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { site_redirect, valid_redirect } = require("../siteredirect.js");
const EX = " !.well-known-acl";

assert.equal(site_redirect("a.example", {}, EX), "", "unset renders nothing");

const temp = site_redirect("kassa.example", { redirect: "https://www.facebook.com/kassaboat", redirect_code: 302 }, EX);
const lines = temp
    .trim()
    .split("\n")
    .map((l) => l.trim());
const want = (host) => "redirect location https://www.facebook.com/kassaboat code 302 if { hdr(host) -i " + host + " } !.well-known-acl";
assert.deepEqual(lines, [want("kassa.example"), want("www.kassa.example")]);
assert.match(site_redirect("b.example", { redirect: "https://new.example/" }, EX), /code 301 /, "default is permanent");
assert.match(site_redirect("b.example", { redirect: "https://new.example/", redirect_code: "302" }, EX), /code 302 /, "datastore string code");

for (const bad of ["ftp://x.example", "https://x.example/a b", "https://x.example/#top", 'https://x.example/"q', "https://x.example/a\nbind *:1", "javascript:alert(1)", ""]) {
    assert.equal(valid_redirect(bad), false, "refused: " + JSON.stringify(bad));
}
for (const good of ["https://www.facebook.com/kassaboat", "http://x.example:8080/p?q=1&r=%20", "https://x.example"]) {
    assert.equal(valid_redirect(good), true, "accepted: " + good);
}
assert.throws(() => site_redirect("c.example", { redirect: "https://x.example/#a" }, EX), /invalid redirect/);
assert.throws(() => site_redirect("c.example", { redirect: "https://x.example/", redirect_code: 307 }, EX), /invalid redirect_code/);

// haproxy.js: called first in each frontend's redirect loop, before the www. redirect
const src = fs.readFileSync(new URL("../haproxy.js", import.meta.url), "utf8");
for (const fe of ["function get_frontend_http", "function get_frontend_https"]) {
    const body = src.slice(src.indexOf(fe), src.indexOf("\n}\n", src.indexOf(fe)));
    const a = body.indexOf("site_redirect(c, containers[c], rule_exeptions)");
    const b = body.indexOf('redirect("http');
    assert.ok(a > 0 && a < b, fe + ": site_redirect first");
}

console.log("siteredirect: all checks passed");
