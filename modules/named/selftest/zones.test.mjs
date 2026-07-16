// Run: node modules/named/selftest/zones.test.mjs

import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { canonicalZoneName, validateZoneOwnership } = require("../lib/zones.js");

assert.equal(canonicalZoneName("example.com"), "example.com");
for (const invalid of [
    "Example.com", "example.com.", "../example.com", "bad_name.example",
    "-bad.example", "bad-.example", "bad example.com", "example\n.com",
]) {
    assert.throws(() => canonicalZoneName(invalid), /zone name/,
        "unsafe/noncanonical name must fail: " + JSON.stringify(invalid));
}

const valid = validateZoneOwnership([
    {
        cluster: "one",
        host: "app1",
        containers: {
            "example.com": { aliases: ["www-example.com"] },
            service: {},
            "company.test": {},
        },
    },
], "company.test");
assert.deepEqual([...valid.keys()], ["example.com", "www-example.com"]);

assert.throws(() => validateZoneOwnership([
    { cluster: "one", host: "app1", containers: {
        "one.example": { aliases: ["collision.example"] },
    } },
    { cluster: "two", host: "app2", containers: {
        "collision.example": {},
    } },
], "company.test"), /declared by both .*alias.*base/,
"alias-to-base collision must fail before rendering");

assert.throws(() => validateZoneOwnership([
    { cluster: "one", host: "app1", containers: {
        "one.example": { aliases: ["shared.example"] },
        "two.example": { aliases: ["shared.example"] },
    } },
], "company.test"), /declared by both/,
"alias-to-alias collision must fail");

assert.throws(() => validateZoneOwnership([
    { cluster: "one", host: "app1", containers: {
        "one.example": { aliases: ["company.test"] },
    } },
], "company.test"), /reserved zone company\.test/);

assert.throws(() => validateZoneOwnership([
    { cluster: "one", host: "app1", containers: {
        "one.example": { aliases: "alias.example" },
    } },
], "company.test"), /must be an array/);

console.log("zones.test: passed");
