/*
 * srvctl letsencrypt module — bundlelib.js
 *
 * Lives in the module root, not libs/: commonlib.sh sources every file under
 * every module's libs directory as a bash library, and this file is Node.
 *
 * Pure helpers for the deployed certificate bundle. Kept free of datastore
 * and environment access so modules/letsencrypt/selftest/bundle.test.sh can
 * exercise them with certificates generated on the spot.
 *
 * A served bundle is the private key followed by certbot's fullchain.pem
 * (leaf, then intermediates). Nothing is appended: a trust anchor does not
 * belong in the presented chain, and the vendored DST Root CA X3 that earlier
 * versions appended expired on 2021-09-30.
 */

const execSync = require("child_process").execSync;

const br = "\n";
const BEGIN = "-----BEGIN CERTIFICATE-----";
const END = "-----END CERTIFICATE-----";

// Trailing-newline-normalised copy of a PEM chunk.
function chunk(text) {
    return String(text).replace(/\s+$/, "") + br;
}

// privkey + fullchain, each terminated by exactly one newline.
function composeBundle(privkey, fullchain) {
    return chunk(privkey) + chunk(fullchain);
}

// Every CERTIFICATE block in a PEM text, in order, as complete PEM strings.
function certificateBlocks(pem) {
    var blocks = [];
    var text = String(pem);
    var from = 0;
    for (;;) {
        var start = text.indexOf(BEGIN, from);
        if (start < 0) break;
        var stop = text.indexOf(END, start);
        if (stop < 0) break;
        stop += END.length;
        blocks.push(text.substring(start, stop) + br);
        from = stop;
    }
    return blocks;
}

// True when openssl accepts the block as a certificate still valid now.
function blockValid(block) {
    try {
        execSync("openssl x509 -checkend 0 -noout", { input: block, stdio: ["pipe", "ignore", "ignore"] });
        return true;
    } catch (error) {
        return false;
    }
}

// Indexes (0-based, in bundle order) of certificate blocks that are expired
// or unreadable. A non-empty result means the bundle must be rebuilt from
// the certbot lineage even if its leaf is still fine.
function expiredBlocks(pem) {
    var expired = [];
    certificateBlocks(pem).forEach(function (block, index) {
        if (!blockValid(block)) expired.push(index);
    });
    return expired;
}

module.exports = { composeBundle, certificateBlocks, expiredBlocks };
