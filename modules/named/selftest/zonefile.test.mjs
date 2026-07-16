// Run: node modules/named/selftest/zonefile.test.mjs

import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const {
    SERIAL_PLACEHOLDER,
    planZoneUpdate,
    serialFromZone,
} = require("../lib/zonefile.js");

function template(address = "192.0.2.1") {
    return [
        "$TTL 1D",
        "@ IN SOA @ hostmaster.example. (",
        "    " + SERIAL_PLACEHOLDER + " ; serial",
        "    15M ; refresh",
        "    5M ; retry",
        "    1W ; expire",
        "    3H ) ; minimum",
        "@ IN A " + address,
        "",
    ].join("\n");
}

const initial = planZoneUpdate(template(), undefined, 1_800_000_000);
assert.equal(initial.changed, true);
assert.equal(initial.serial, 1_800_000_000);
assert.equal(serialFromZone(initial.content), 1_800_000_000);

const unchanged = planZoneUpdate(template(), initial.content, 1_800_000_100);
assert.equal(unchanged.changed, false);
assert.equal(unchanged.serial, initial.serial);
assert.equal(unchanged.content, initial.content,
    "unchanged content must preserve the installed file byte-for-byte");

const sameSecond = planZoneUpdate(template("192.0.2.2"), initial.content, 1_800_000_000);
assert.equal(sameSecond.changed, true);
assert.equal(sameSecond.serial, 1_800_000_001,
    "a same-second content change must still advance the serial");

const clockRollback = planZoneUpdate(template("192.0.2.3"), sameSecond.content, 1_700_000_000);
assert.equal(clockRollback.serial, 1_800_000_002,
    "clock rollback must not lower or reuse the installed serial");

const laterEpoch = planZoneUpdate(template("192.0.2.4"), clockRollback.content, 1_900_000_000);
assert.equal(laterEpoch.serial, 1_900_000_000,
    "epoch time remains the readable lower bound when it is ahead");

assert.throws(() => planZoneUpdate("not a zone", undefined, 1),
    /no recognizable SOA serial line/);

console.log("zonefile.test: passed");
