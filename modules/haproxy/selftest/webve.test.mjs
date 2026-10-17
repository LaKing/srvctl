// modules/haproxy/selftest/webve.test.mjs — web_ve (set-ve-web-ve) moves only
// the server line of a VE's http/https backends to the target, with the
// target's ports; backend names (the ACL targets) stay the VE's, and an unknown
// target falls back to the VE itself. Rendered from the real haproxy.js
// functions (vm slices, as wellknown.test.mjs does).
// Run: node modules/haproxy/selftest/webve.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const src = fs.readFileSync(new URL("../haproxy.js", import.meta.url), "utf8");
const slice = (from, to) => {
    const a = src.indexOf(from);
    const b = src.indexOf(to, a);
    assert.ok(a >= 0 && b > a, "slice " + from);
    return src.slice(a, b);
};

const containers = {
    "site.example": { web_ve: "host.example" },
    "host.example": { http_port: 8081, https_port: 8443 },
    "lost.example": { web_ve: "gone.example" },
};
const ctx = {
    br: "\n",
    containers,
    datastore: { container_http_port: (c) => containers[c].http_port || 80, container_https_port: (c) => containers[c].https_port || 443 },
    basicauth_rule: () => "",
    Object,
};
vm.runInNewContext(slice("function web_ve(", "\nfunction get_backends_for_port("), ctx);

const http = ctx.get_backends_for_http();
const https = ctx.get_backends_for_https();
assert.match(http, /backend http:site\.example\n {4}server http:site\.example host\.example:8081\n/, "http goes to the target with its port");
assert.match(https, /backend https:site\.example\n {4}server https:site\.example host\.example:8443 ssl/, "https goes to the target with its port");
assert.match(http, /server http:host\.example host\.example:8081\n/, "the target keeps its own backend");
assert.match(http, /server http:lost\.example lost\.example:80\n/, "unknown target falls back to the VE");
assert.match(https, /server https:lost\.example lost\.example:443 ssl/, "unknown target falls back to the VE (https)");

console.log("webve.test: passed");
