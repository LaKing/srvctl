// modules/letsencrypt/selftest/acmerun-driver.mjs — runs the acmerun phases
// in a child process (so crash points can kill it), like letsencrypt.js does.
//   SC_TEST_HOSTNAME  host name        SC_TEST_SERVED  comma separated names
//   SC_TEST_STEPS     comma separated: primary, serve, leave, host
//   SC_TEST_HOST_IP   host_ip for the host step
// Prints a JSON summary on stdout.

import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const acmerun = require("../acmerun.js");

const run = new acmerun.AcmeRun(process.env, { hostname: process.env.SC_TEST_HOSTNAME, log: function () {} });
const served = (process.env.SC_TEST_SERVED || "").split(",").filter(Boolean);
const steps = (process.env.SC_TEST_STEPS || "serve").split(",");

run.begin();
for (const step of steps) {
    if (step === "primary") run.primaryPhase();
    if (step === "serve") {
        run.refresh(served);
        run.evaluateNames(served);
        run.computeGate(served);
    }
    if (step === "leave") run.finishLeaving(served);
    if (step === "host") run.hostPath(process.env.SC_TEST_HOST_IP || null);
}
run.writeStatus();
process.stdout.write(JSON.stringify({
    status: run.status,
    states: run.store.data.names,
    pending: run.store.data.pending,
    bypass: Array.from(run.bypassNames),
    suppressed: Object.fromEntries(served.map((d) => [d, run.suppressed(d)])),
}));
