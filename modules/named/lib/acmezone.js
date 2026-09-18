"use strict";

/*
 * Pure helpers for the DNS-01 challenge delegation rendered by named.js.
 *
 * Every generated zone gets
 *     _acme-challenge  IN  CNAME  <base-container>._acme.<company-domain>.
 * so certbot on the DNS primary only ever updates the one dynamic zone
 * _acme.<company-domain> (TSIG-restricted); the generated zones stay static.
 * Aliases share the base container's zone file, so the target is always
 * built from the base container name.
 *
 * A zone that cannot carry the CNAME keeps http-01 and is reported with a
 * reason; a customer's own _acme-challenge record is never overwritten.
 */

const crypto = require("crypto");

const MAX_NAME = 253;
const MAX_LABEL = 63;
const ACME_KEY_NAME = "srvctl-acme";

function acmeZoneName(cdn) {
    return "_acme." + cdn;
}

// The CNAME target, or null when it would not be a valid DNS name.
function challengeTarget(base, cdn) {
    const target = base + "." + acmeZoneName(cdn);
    if (target.length > MAX_NAME) return null;
    if (target.split(".").some(function(label) { return label.length < 1 || label.length > MAX_LABEL; })) {
        return null;
    }
    return target;
}

// True when the container's own dns_records already define the
// _acme-challenge name of any zone rendered from its file (relative
// "_acme-challenge" or the absolute "_acme-challenge.<zone>." spelling).
function hasCustomerChallengeRecord(container, zoneNames) {
    const records = container && container.dns_records;
    if (!Array.isArray(records)) return false;
    return records.some(function(record) {
        const name = String((record && record.name) || "").toLowerCase();
        if (name === "_acme-challenge") return true;
        return zoneNames.some(function(zone) {
            return name === "_acme-challenge." + zone + ".";
        });
    });
}

// Decide the challenge delegation for one zone file (base + aliases).
// Returns { cname: bool, target: string|null, reason: string|null }.
function challengePlan(container, base, aliases, cdn) {
    const zones = [base].concat(Array.isArray(aliases) ? aliases : []);
    if (hasCustomerChallengeRecord(container, zones)) {
        return { cname: false, target: null, reason: "customer _acme-challenge record" };
    }
    const target = challengeTarget(base, cdn);
    if (!target) return { cname: false, target: null, reason: "challenge target too long" };
    return { cname: true, target: target, reason: null };
}

function challengeLine(target) {
    return "_acme-challenge        IN        CNAME        " + target + ".\n";
}

// Turn a regular primary zone statement (same notify/transfer ACLs as every
// generated zone) into the dynamic _acme zone statement: only TXT records
// below the zone, and only with the srvctl-acme TSIG key.
function primaryAcmeStatement(regularStatement, zone, keyFile) {
    const policy = "update-policy { grant " + ACME_KEY_NAME + " subdomain " + zone + ". TXT; }; ";
    const marker = /(file "[^"]*"; )/;
    if (!marker.test(regularStatement)) throw new Error("unexpected zone statement: " + regularStatement);
    return 'include "' + keyFile + '";\n' + regularStatement.replace(marker, "$1" + policy);
}

function sha256(text) {
    return crypto.createHash("sha256").update(text).digest("hex");
}

// Manifest of the DNS-01 zone list, bound to the exact srvctl.conf it was
// rendered with. named/libs/acmelib.sh commits it only after that
// configuration has been activated (restart_named succeeded and the live
// file still has this hash).
function buildManifest(options) {
    return {
        version: 1,
        generatedAt: options.generatedAt,
        cdn: options.cdn,
        acmeZone: acmeZoneName(options.cdn),
        active: Boolean(options.active),
        confSha256: sha256(options.conf),
        zones: options.zones,
    };
}

module.exports = {
    ACME_KEY_NAME: ACME_KEY_NAME,
    acmeZoneName: acmeZoneName,
    buildManifest: buildManifest,
    challengeLine: challengeLine,
    challengePlan: challengePlan,
    challengeTarget: challengeTarget,
    hasCustomerChallengeRecord: hasCustomerChallengeRecord,
    primaryAcmeStatement: primaryAcmeStatement,
    sha256: sha256,
};
