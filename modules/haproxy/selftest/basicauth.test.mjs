// modules/haproxy/selftest/basicauth.test.mjs — sc basicauth-ve-port: the port
// key parser, the access user set (twin of codepad/access.js), the logins taken
// from the datastore .password files, and the rendered userlist + backend rules
// (haproxy.js backend functions run in a vm slice, as wellknown.test.mjs does).
// Run: node modules/haproxy/selftest/basicauth.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const basicauth = require("../basicauth.js");
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "basicauth-test-"));
let checks = 0;
const ok = (v, m) => { assert.ok(v, m); checks++; };

function password(u, pw) {
    fs.mkdirSync(path.join(dir, "users", u), { recursive: true });
    fs.writeFileSync(path.join(dir, "users", u, ".password"), pw + "\n");
}

try {
    ok(basicauth.parse_ports("c", "all") === "all", "all ports");
    assert.deepEqual(basicauth.parse_ports("c", "9000,443"), [443, 9000]);
    assert.throws(() => basicauth.parse_ports("c", "443,22"));
    assert.throws(() => basicauth.parse_ports("c", "8.*"));
    checks += 3;

    const users = { alice: {}, bob: {}, rita: { reseller_id: 1 }, staff: { access: "all" }, dan: { reseller: "rita" }, eve: {}, root: { access: "all" } };
    const containers = {
        "shop.example": { user: "dan", users: ["bob", "mal"], readers: ["eve"], basicauth: "443" },
        "ext.example": { user: "alice" },
    };
    assert.deepEqual(basicauth.access_users(containers, users, "shop.example"), ["bob", "dan", "mal", "rita", "staff"]);
    checks++;

    password("dan", "Kelto-Ardu");
    password("bob", "Bad pw#x");
    password("rita", "Rita-Pass");
    password("staff", "Staff-Pass");
    const warnings = [];
    const auth = basicauth.build(containers, users, dir, (w) => warnings.push(w));
    ok(Object.keys(auth).join() === "shop.example", "only containers with the key");
    assert.deepEqual(auth["shop.example"].users, { dan: "Kelto-Ardu", rita: "Rita-Pass", staff: "Staff-Pass" });
    checks++;
    ok(warnings.some((w) => w.includes("mal has no .password")), "missing password reported");
    ok(warnings.some((w) => w.includes("bob has a name or password")), "unsafe password left out, not injected");

    const lists = basicauth.userlists(auth);
    ok(/^userlist basicauth:shop\.example\n {4}user dan insecure-password Kelto-Ardu\n {4}user rita /m.test(lists), "userlist rendered");
    ok(!lists.includes("Bad pw"), "no unsafe value in the cfg");

    const src = fs.readFileSync(new URL("../haproxy.js", import.meta.url), "utf8");
    const slice = (from, to) => src.slice(src.indexOf(from), src.indexOf(to, src.indexOf(from)));
    const ctx = {
        br: "\n", containers, Object,
        datastore: { container_http_port: () => 80, container_https_port: () => 443 },
        basicauth_rule: (c, n) => basicauth.rule(auth, c, n),
        is_codepad_port: () => false,
    };
    vm.runInNewContext(slice("function web_ve(", "\nvar cfg = "), ctx);
    const https = ctx.get_backends_for_https();
    ok(/backend https:shop\.example\n {4}http-request auth realm "shop\.example" unless \{ http_auth\(basicauth:shop\.example\) \}\n {4}http-after-response set-header X-Robots-Tag "noindex, nofollow"\n {4}server /.test(https), "auth rule and X-Robots-Tag before the server line");
    ok(!ctx.get_backends_for_http().includes("X-Robots-Tag"), "no X-Robots-Tag where there is no auth");
    ok(!/backend https:ext\.example\n {4}http-request/.test(https), "unprotected container untouched");
    ok(!ctx.get_backends_for_http().includes("http-request auth"), "port 80 not covered by a 443-only key");
    ok(!ctx.get_backends_for_port(8443, true).includes("http-request auth"), "other ports not covered");
} finally {
    fs.rmSync(dir, { recursive: true, force: true });
}
console.log("basicauth.test: " + checks + " checks passed");
