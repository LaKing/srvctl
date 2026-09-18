"use strict";

/*
 * srvctl letsencrypt module — acmeplan.js
 *
 * Lives in the module root, not libs/ (commonlib.sh sources every file under
 * libs/ as bash).
 *
 * The decisions of the hybrid certificate scheme, kept free of side effects
 * except for the two bash calls into the shared wildcard rule:
 *
 *   classifyNS / classifyDomain   ours (our DNS serves it) | external |
 *                                 undetermined, from DNS-scan NS results
 *   evaluate                      the per-name handover state machine,
 *                                 rules evaluated in a fixed order:
 *     J   pending journal operations are replayed by the store first
 *     R1  a validated renewed bundle B is installed; LEGACY -> WILDCARD only
 *         with at least a third of its lifetime left; FALLBACK -> WILDCARD and
 *         LEAVING -> WILDCARD for any B (fallback ends / leave cancelled)
 *     R2  an explicit not-dns01 index entry: WILDCARD|FALLBACK -> LEAVING
 *     R3  fallback enabled, WILDCARD with <= 7 days left or not servable:
 *         -> FALLBACK (needs no index, so it also fires during an outage)
 *     R4  fallback disabled while FALLBACK: -> WILDCARD
 *     R5  actions and alerts for the resulting state
 *   certbot*Args                  exact certbot argument vectors
 *   wildcardCoveringMany /        the one wildcard rule, from
 *   servableManaged               modules/certificates/libs/wildcardgatelib.sh,
 *                                 run in a bare `bash --noprofile --norc`
 */

const childProcess = require("child_process");
const crypto = require("crypto");
const path = require("path");

const DAY = 86400000;
const STATES = ["LEGACY", "WILDCARD", "FALLBACK", "LEAVING"];
const FALLBACK_DAYS = 7;
const ERROR_DAYS = 14;
const GATE_LIB = path.join(__dirname, "../certificates/libs/wildcardgatelib.sh");

function normalizeName(name) {
    return String(name || "").trim().toLowerCase().replace(/\.$/, "");
}

function ourNameServers(cdn) {
    const c = normalizeName(cdn);
    return ["ns1." + c, "ns2." + c];
}

// ours: every scanned NS is one of ours; external: at least one is not;
// undetermined: no scan or an empty NS list (the scan only resolves NS after
// the A lookup succeeded, and empties records before each lookup).
function classifyNS(ns, cdn) {
    if (!Array.isArray(ns)) return "undetermined";
    const names = ns.map(normalizeName).filter(Boolean);
    if (names.length === 0) return "undetermined";
    const ours = new Set(ourNameServers(cdn));
    return names.every(function(n) { return ours.has(n); }) ? "ours" : "external";
}

// The index names a served domain maps to: the name itself or one label
// below it (a *.name wildcard matches one level). Mapping only — whether a
// wildcard actually covers the domain is decided by wildcardgatelib.sh.
function indexNamesFor(domain, names) {
    const d = normalizeName(domain);
    return names.filter(function(n) {
        if (d === n) return true;
        if (!d.endsWith("." + n)) return false;
        return d.slice(0, -(n.length + 1)).indexOf(".") < 0;
    });
}

// Classification of one certificate domain for status and outcome.
//   indexEntry: the primary's index entry of the covering name, or null
//   ns:         the local DNS-scan NS list of the domain (or its zone)
function classifyDomain(indexEntry, ns, cdn) {
    const nsClass = classifyNS(ns, cdn);
    if (indexEntry && indexEntry.state === "issued") return { class: "ours/dns01", ns: nsClass };
    if (indexEntry && indexEntry.state === "not-dns01") {
        return { class: nsClass === "ours" ? "ours/no-cname" : nsClass, ns: nsClass, reason: indexEntry.reason };
    }
    if (nsClass === "ours") return { class: indexEntry ? "ours/dns01-pending" : "ours/no-cname", ns: nsClass };
    return { class: nsClass, ns: nsClass };
}

// W or B as the state machine sees it.
function certView(meta, now) {
    if (!meta) return { servable: false, daysLeft: 0, lifetimeDays: 0 };
    return {
        servable: Boolean(meta.servable),
        daysLeft: Math.max(0, (meta.notAfter - now) / DAY),
        lifetimeDays: Math.max(0, (meta.notAfter - meta.notBefore) / DAY),
    };
}

function hasMargin(view) {
    return view.servable && view.lifetimeDays > 0 && view.daysLeft >= view.lifetimeDays / 3;
}

/*
 * evaluate({ state, index, bundle, wildcard, fallback })
 *   state    LEGACY | WILDCARD | FALLBACK | LEAVING (default LEGACY)
 *   index    issued | not-dns01 | pending | failed | unavailable
 *   bundle   null, or a validated renewed bundle view {servable, daysLeft,
 *            lifetimeDays} (already known to expire later than the wildcard)
 *   wildcard installed managed wildcard view {servable, daysLeft, lifetimeDays}
 *   fallback D-B setting (boolean)
 * returns { state, install, http01: "gated"|"bypass", retire, alerts[], events[] }
 */
function evaluate(input) {
    let state = STATES.indexOf(input.state) >= 0 ? input.state : "LEGACY";
    const index = input.index || "unavailable";
    let wildcard = input.wildcard || { servable: false, daysLeft: 0, lifetimeDays: 0 };
    const fallback = Boolean(input.fallback);
    const out = { install: false, http01: "gated", retire: false, alerts: [], events: [] };
    let fallbackEnded = false;

    // R1: a validated renewed bundle
    if (input.bundle) {
        out.install = true;
        wildcard = input.bundle;
        const good = hasMargin(input.bundle);
        if (state === "LEGACY" && good) {
            state = "WILDCARD";
            out.events.push("handover");
        } else if (state === "FALLBACK") {
            state = "WILDCARD";
            fallbackEnded = true;
            out.events.push("fallback-ended");
        } else if (state === "LEAVING") {
            state = "WILDCARD";
            out.events.push("leave-cancelled");
        }
    }

    // R2: explicit decision of the primary that the name left DNS-01
    if (index === "not-dns01" && (state === "WILDCARD" || state === "FALLBACK")) {
        state = "LEAVING";
        out.events.push("leaving");
        out.alerts.push({ level: "error", text: "left DNS-01; http-01 resumes, wildcard retired once replaced" });
    }

    // R3: fallback start (index not needed)
    if (fallback && state === "WILDCARD" && (!wildcard.servable || wildcard.daysLeft <= FALLBACK_DAYS)) {
        state = "FALLBACK";
        out.events.push(fallbackEnded ? "fallback-re-entered" : "fallback-started");
        out.alerts.push({ level: "error", text: "http-01 fallback " + (fallbackEnded ? "re-entered" : "started") +
            " (wildcard " + (wildcard.servable ? Math.floor(wildcard.daysLeft) + " days left" : "not servable") + ")" });
    }

    // R4: fallback switched off
    if (!fallback && state === "FALLBACK") {
        state = "WILDCARD";
        out.events.push("fallback-disabled");
        out.alerts.push({ level: "error", text: "http-01 fallback disabled; holding the wildcard" });
    }

    // R5: actions and alerts
    if (state === "FALLBACK") {
        out.http01 = "bypass";
        if (!out.events.includes("fallback-started") && !out.events.includes("fallback-re-entered")) {
            out.alerts.push({ level: "error", text: "http-01 fallback active" });
        }
    } else if (state === "LEAVING") {
        out.http01 = "bypass";
        out.retire = true;
    } else if (state === "WILDCARD") {
        if (!wildcard.servable) {
            out.alerts.push({ level: "error", text: "wildcard not servable; http-01 is not blocked" });
        } else if (!fallback && wildcard.daysLeft <= FALLBACK_DAYS) {
            out.alerts.push({ level: "error", text: "wildcard expiring (" + Math.floor(wildcard.daysLeft) +
                " days) and the http-01 fallback is disabled" });
        } else if (wildcard.daysLeft < ERROR_DAYS) {
            out.alerts.push({ level: "error", text: "wildcard renewal overdue (" + Math.floor(wildcard.daysLeft) + " days left)" });
        } else if (!hasMargin(wildcard)) {
            out.alerts.push({ level: "warn", text: "wildcard renewal due (" + Math.floor(wildcard.daysLeft) + " days left)" });
        }
    }
    if (index === "unavailable" && state !== "LEGACY") {
        out.alerts.push({ level: "warn", text: "index or bundle unavailable; holding " + state });
    }

    out.state = state;
    return out;
}

// Issuance due on the primary: no bundle, or less than a third of its
// lifetime left.
function renewalDue(view) {
    return !view || !hasMargin(view);
}

// Per-name failure backoff on the primary: 1 h doubling to 24 h.
function backoffUntil(failures, lastFailure) {
    if (!failures) return 0;
    const hours = Math.min(24, Math.pow(2, failures - 1));
    return lastFailure + hours * 3600000;
}

function certbotDns01Args(name, hook, staging) {
    const args = ["certonly", "--non-interactive", "--agree-tos",
        "--manual", "--preferred-challenges", "dns",
        "--manual-auth-hook", hook + " auth",
        "--manual-cleanup-hook", hook + " cleanup",
        "--cert-name", "srvctl-wildcard-" + name,
        "--keep-until-expiring",
        "-d", name, "-d", "*." + name];
    if (staging) args.push("--test-cert");
    return args;
}

function certbotHostArgs(fqdn, staging) {
    const args = ["certonly", "--non-interactive", "--agree-tos", "--keep-until-expiring",
        "--webroot", "--webroot-path", "/var/acme/", "--cert-name", fqdn, "-d", fqdn];
    if (staging) args.push("--test-cert");
    return args;
}

function gateEnv(env) {
    const out = { PATH: env.PATH || "/usr/bin:/bin" };
    if (env.SC_ADMIN_CERT_DIR) out.SC_ADMIN_CERT_DIR = env.SC_ADMIN_CERT_DIR;
    if (env.SC_DATASTORE_DIR) out.SC_DATASTORE_DIR = env.SC_DATASTORE_DIR;
    if (env.SC_WILDCARD_EXCLUDE) out.SC_WILDCARD_EXCLUDE = env.SC_WILDCARD_EXCLUDE;
    return out;
}

// { domain: coveringFile|null } for many domains in one bash call.
function wildcardCoveringMany(domains, env) {
    const result = {};
    if (domains.length === 0) return result;
    const output = childProcess.execFileSync("bash",
        ["--noprofile", "--norc", "-c", 'source "$1"; wildcard_covering_many', "_", GATE_LIB],
        { env: gateEnv(env || process.env), input: domains.join("\n") + "\n", encoding: "utf8" });
    output.split("\n").forEach(function(line) {
        if (!line) return;
        const tab = line.indexOf("\t");
        const file = line.slice(tab + 1);
        result[line.slice(0, tab)] = file === "-" ? null : file;
    });
    return result;
}

function wildcardCovering(domain, env) {
    return wildcardCoveringMany([domain], env)[domain] || null;
}

// base or false, per wildcard_servable_managed.
function servableManaged(pemPath, env) {
    const out = childProcess.execFileSync("bash",
        ["--noprofile", "--norc", "-c", 'source "$1"; wildcard_servable_managed "$2"', "_", GATE_LIB, pemPath],
        { env: gateEnv(env || process.env), encoding: "utf8" }).trim();
    return out === "false" ? false : out;
}

// Leaf certificate facts from a PEM text (first CERTIFICATE block).
function certMeta(pemText) {
    const match = /-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/.exec(String(pemText));
    if (!match) return null;
    let x509;
    try {
        x509 = new crypto.X509Certificate(match[0]);
    } catch (error) {
        return null;
    }
    const sans = String(x509.subjectAltName || "").split(",").map(function(s) {
        return s.trim().replace(/^DNS:/, "");
    }).filter(Boolean);
    return { notBefore: Date.parse(x509.validFrom), notAfter: Date.parse(x509.validTo), sans: sans };
}

function sha256(data) {
    return crypto.createHash("sha256").update(data).digest("hex");
}

// true when the PEM text holds a private key matching its leaf certificate,
// the same pairing wildcard_servable_managed requires (a file haproxy can
// serve); certMeta alone says nothing about the key.
function keyMatchesLeaf(pemText) {
    const cert = /-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/.exec(String(pemText));
    const key = /-----BEGIN ((?:RSA |EC |ENCRYPTED )?PRIVATE KEY)-----[\s\S]+?-----END \1-----/.exec(String(pemText));
    if (!cert || !key) return false;
    try {
        return new crypto.X509Certificate(cert[0]).checkPrivateKey(crypto.createPrivateKey(key[0]));
    } catch (error) {
        return false;
    }
}

module.exports = {
    DAY,
    FALLBACK_DAYS,
    GATE_LIB,
    STATES,
    backoffUntil,
    certMeta,
    certView,
    certbotDns01Args,
    certbotHostArgs,
    classifyDomain,
    classifyNS,
    evaluate,
    hasMargin,
    indexNamesFor,
    keyMatchesLeaf,
    normalizeName,
    ourNameServers,
    renewalDue,
    servableManaged,
    sha256,
    wildcardCovering,
    wildcardCoveringMany,
};
