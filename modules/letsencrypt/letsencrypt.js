#!/bin/node

/*
 * srvctl letsencrypt module — letsencrypt.js
 *
 * Certificate request/deploy engine. Invoked (with no arguments) by
 * letsencrypt_main (libs/bashlib.sh) from regenerate_letsencrypt, i.e. on
 * every regenerate_certificates hook run (haproxy regenerate,
 * http-redirect/https-redirect, named override-in-address).
 *
 * For every container in the datastore it decides per domain whether a
 * Let's Encrypt certificate is needed (skips mail./devel/local/dotless
 * names, www. duplicates, wildcard-covered domains, still-valid certs and
 * domains whose scanned A record does not point at this host), then runs
 * 'letsencrypt certonly' via the /var/acme webroot (http-01, answered by
 * apps/acme-server.js behind haproxy) and deploys the result.
 *
 * Reads:  datastore containers/hosts JSON (datastore/lib.js),
 *         /etc/letsencrypt/live/<lineage>/{cert,fullchain,privkey}.pem,
 *         /etc/letsencrypt/ca.pem, /etc/srvctl/cert/<domain>/<domain>.pem
 *         (wildcard detection, owned by the certificates module).
 * Writes: $SC_DATASTORE_DIR/cert/<domain>.pem (privkey+fullchain+ca) and,
 *         when /srv/<domain>/rootfs/etc/pki/tls/{private,certs} exist, the
 *         container's localhost.key / localhost.crt / <domain>.pem /
 *         localhost.pem; appends certbot output to /srv/<name>/
 *         letsencrypt<name>.log or letsencrypt-www.<name>.log.
 *
 * Exit codes: 99 preset at load, 0 on completion (per-domain failures are
 * logged but do not change the exit code); the return_value/return_error
 * helpers (100/111) are currently unused here.
 *
 * Scheduled for the v4 DNS-01 wildcard redesign (G7): document, don't
 * rework.
 */

const lablib = "../../lablib.js";
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;

function out(msg) {
    console.log(msg);
}

// includes
const fs = require("fs");
const datastore = require("../datastore/lib.js");
const execSync = require("child_process").execSync;
const https = require("https");

const CMD = process.argv[2];
// constants

// FIXME(v4): SC_CONTAINERS_DATA_FILE, SC_UID0 and localhost below are
// declared but never used (dead symbols) — drop them in the redesign.
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/containers.json";
const SC_CONTAINERS_CERT_DIR = process.env.SC_DATASTORE_DIR + "/cert";
const SC_INSTALL_DIR = process.env.SC_INSTALL_DIR;
const SC_COMPANY_DOMAIN = process.env.SC_COMPANY_DOMAIN;
const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;
const os = require("os");
const HOSTNAME = os.hostname();
const localhost = "localhost";
const br = "\n";
process.exitCode = 99;

function exit() {
    process.exitCode = 0;
}

// FIXME(v4): return_value, return_error and output are copy-pasted helper
// boilerplate shared with other JS modules and unused here — consolidate on
// a single lablib import surface in the mjs port.
function return_value(msg) {
    if (msg === undefined || msg === "") process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function return_error(msg) {
    console.error("DATA-ERROR:", msg);
    process.exitCode = 111;
    process.exit(111);
}

function output(variable, value) {
    console.log(variable + '="' + value + '"');
    process.exitCode = 0;
}

// A wildcard cert installed by the certificates module lives at
// /etc/srvctl/cert/<domain>/<domain>.pem with a "*" in its subject; this
// path/layout must stay in sync with wildcardcertlib.sh.
function is_wildcard_certificate(domain) {
    var cert_file = "/etc/srvctl/cert/" + domain + "/" + domain + ".pem";
    if (fs.existsSync(cert_file)) {
        if (execSync("openssl x509 -noout -subject -in " + cert_file).indexOf("*") > -1) {
            return true;
        }
    }
    return false;
}

// True when the domain itself or its parent domain (first label stripped,
// after any leading "www.") is covered by an installed wildcard cert.
function has_wildcard_certificate(domain) {
    if (domain.substring(0, 4) === "www.") domain = domain.substring(4);
    if (is_wildcard_certificate(domain)) return true;
    if (is_wildcard_certificate(domain.substring(1 + domain.indexOf(".")))) return true;
    return false;
}

// variables
var hosts = datastore.hosts;
// FIXME(v4): users, resellers, user and container below are never used
// (copy-pasted module boilerplate) — drop them in the redesign.
var users = datastore.users;
var resellers = datastore.resellers;
var containers = datastore.containers;
var user = "";
var container = "";

function get_le_dir(domain) {
    // certbot creates suffixed lineages like "mobilflower.hu-0001" when a stale
    // base lineage already exists. Match the base name and any "-NNNN" suffixed
    // variants, then pick the one whose cert.pem expires latest.
    // Read the live dir fresh on every call: certonly may have just created a brand-new
    // lineage during this same run (e.g. a first-time subdomain cert), which a snapshot
    // taken at startup would miss.
    var le_dirs;
    try {
        le_dirs = fs.readdirSync("/etc/letsencrypt/live");
    } catch (e) {
        return undefined;
    }
    var candidates = [];
    var re = new RegExp("^(www\\.)?" + domain.replace(/\./g, "\\.") + "(-\\d+)?$");
    le_dirs.forEach((dir) => {
        if (re.test(dir)) candidates.push(dir);
    });
    if (candidates.length === 0) return undefined;
    if (candidates.length === 1) return candidates[0];

    var best;
    var best_epoch = -1;
    candidates.forEach((dir) => {
        var cert_file = "/etc/letsencrypt/live/" + dir + "/cert.pem";
        if (!fs.existsSync(cert_file)) return;
        try {
            var out = execSync("openssl x509 -enddate -noout -in " + cert_file).toString();
            var m = out.match(/notAfter=(.+)/);
            if (!m) return;
            var epoch = Date.parse(m[1]);
            if (isNaN(epoch)) return;
            if (epoch > best_epoch) {
                best_epoch = epoch;
                best = dir;
            }
        } catch (e) {}
    });
    return best || candidates[0];
}

// True when the cert exists and remains valid for at least 7 more days
// (openssl -checkend 604800 exits non-zero otherwise).
// FIXME(v4): prints the raw openssl command via ntc on every call (constant
// yellow noise) and uses 'return' inside a finally block, which overrides
// any control flow from the try/catch — lint-flagged; works, but clean up
// in the redesign.
function check_checkend(cert_file) {
    if (!fs.existsSync(cert_file)) return false;
    var returnState = false;
    try {
        ntc("openssl x509 -checkend 604800 -noout -in " + cert_file);
        execSync("openssl x509 -checkend 604800 -noout -in " + cert_file);
        returnState = true;
    } catch (error) {
        ntc("Certificate will expire! " + cert_file);
    } finally {
        return returnState;
    }
}

// True when the already-deployed $SC_DATASTORE_DIR/cert/<domain>.pem is a
// real (not self-signed) cert still valid for 7+ days — i.e. nothing to do.
function check_datastore_cert(domain) {
    // TODO no need to check this certificate in the LE module.
    var cert_file = SC_CONTAINERS_CERT_DIR + "/" + domain + ".pem";
    var cmd = "openssl x509 -noout -subject -in " + cert_file;

    if (fs.existsSync(cert_file)) {
        var cn = "";
        try {
            cn = execSync(cmd).toString();
        } catch (err) {
            console.log("Letsencypt check_domain failure for ", domain, err);
            return false;
        }

        if (cn.indexOf("emailAddress = webmaster@") > 0) {
            console.log("Selfsigned certiciate in the datastore for ", domain);
            return false;
        }

        return check_checkend(cert_file);
    } else {
        ntc("No datastore cert file for", domain, cert_file);
        return false;
    }
}

// Bundle privkey + fullchain + ca into $SC_DATASTORE_DIR/cert/<domain>.pem
// and, when a container rootfs matches the domain, into its
// /etc/pki/tls/{private,certs} files. Best-effort: any missing input just
// logs an err and returns; the caller's exit code stays 0.
// FIXME(v4): per-domain deploy failures are invisible to the caller
// (process still exits 0) — surface an aggregate non-zero exit code so
// haproxy regenerate / cron can detect issuance failures.
function letsencrypt_deploy(domain) {
    var le_dir = get_le_dir(domain);
    if (!le_dir) return;
    // FIXME(v4): cert_pem below is declared but never used (dead symbol).
    var cert_pem = "/etc/letsencrypt/live/" + le_dir + "/cert.pem";
    var fullchain_pem = "/etc/letsencrypt/live/" + le_dir + "/fullchain.pem";
    var privkey_pem = "/etc/letsencrypt/live/" + le_dir + "/privkey.pem";
    // FIXME(v4): /etc/letsencrypt/ca.pem is the vendored letsencrypt-ca.pem
    // (DST Root CA X3, expired 2021-09-30) installed by install_acme; it is
    // appended to every bundle below, shipping an expired root in the
    // presented chain. certbot's fullchain.pem already carries the correct
    // ISRG chain — drop the append (or vendor the current ISRG root) in the
    // DNS-01 redesign.
    var ca_pem = "/etc/letsencrypt/ca.pem";

    if (!fs.existsSync(privkey_pem)) return err("Private key dont exists " + privkey_pem);
    if (!fs.existsSync(fullchain_pem)) return err("Certificate dont exists " + fullchain_pem);
    if (!fs.existsSync(ca_pem)) return err("CA file dont exists " + ca_pem);

    var privkey = fs.readFileSync(privkey_pem, "UTF8");
    var fullchain = fs.readFileSync(fullchain_pem, "UTF8");
    var ca = fs.readFileSync(ca_pem, "UTF8");

    var pem = privkey + br + fullchain + br + ca + br;

    fs.writeFileSync(SC_CONTAINERS_CERT_DIR + "/" + domain + ".pem", pem);

    msg(SC_CONTAINERS_CERT_DIR + "/" + domain + " letsencrypt certificate deployed. " + SC_CONTAINERS_CERT_DIR + "/" + domain + ".pem");

    // deploy certificate to container, if the domain name matches the container
    if (fs.existsSync("/srv/" + domain + "/rootfs/etc/pki/tls/private") && fs.existsSync("/srv/" + domain + "/rootfs/etc/pki/tls/certs")) {
        // /etc/pki/tls/private/localhost.key
        fs.writeFileSync("/srv/" + domain + "/rootfs/etc/pki/tls/private/localhost.key", privkey);

        // /etc/pki/tls/certs/localhost.crt
        fs.writeFileSync("/srv/" + domain + "/rootfs/etc/pki/tls/certs/localhost.crt", fullchain + br + ca + br);

        fs.writeFileSync("/srv/" + domain + "/rootfs/etc/pki/tls/certs/" + domain + ".pem", pem);
        fs.writeFileSync("/srv/" + domain + "/rootfs/etc/pki/tls/certs/localhost.pem", pem);

        msg(domain + " container letsencrypt certificate deployed");
    }
}

// Run 'letsencrypt certonly' (webroot http-01) for one domain, adding
// www.<domain> as a second -d when the scanned www A record points at this
// host, then verify the live cert and deploy it.
function run_on_container_domain(name, domain) {
    // we can check against HOSTNAME if a reverse address is set, but since it is not mandatory ...
    ntc(name, domain);

    var has_www = false;
    if (hosts[HOSTNAME])
        if (containers[name].dns["www." + domain])
            containers[name].dns["www." + domain].A.forEach(function (e) {
                if (e === hosts[HOSTNAME].host_ip) has_www = true;
            });

    if (has_www) msg("Certificate required for " + domain + " and www." + domain);
    else msg("Certificate required for " + domain);

    // FIXME(v4): asymmetric log filenames — the non-www run appends to
    // /srv/<name>/letsencrypt<name>.log (no separator) while the www run
    // uses /srv/<name>/letsencrypt-www.<name>.log; one container's runs
    // scatter across differently-named files. Normalize while porting.
    var cmd =
        "letsencrypt certonly --non-interactive --agree-tos --keep-until-expiring --expand --webroot --webroot-path /var/acme/ -d " +
        domain +
        " >> /srv/" +
        name +
        "/letsencrypt" +
        name +
        ".log";
    if (has_www)
        cmd =
            "letsencrypt certonly --non-interactive --agree-tos --keep-until-expiring --expand --webroot --webroot-path /var/acme/ -d " +
            domain +
            " -d www." +
            domain +
            " >> /srv/" +
            name +
            "/letsencrypt-www." +
            name +
            ".log";
    ntc(cmd);

    try {
        execSync(cmd);
        msg("Letsencrypt certonly success for " + domain);
    } catch (err) {
        return console.log("Letsencypt certonly failure for ", domain, err);
    }

    // verify the live cert is actually valid before deploying — certbot can
    // exit 0 (e.g. silent ACME validation failure with --keep-until-expiring)
    // while leaving an expired cert in /etc/letsencrypt/live/
    var le_dir = get_le_dir(domain);
    if (!le_dir) return err("No letsencrypt live dir for " + domain + " after certonly");
    var live_cert = "/etc/letsencrypt/live/" + le_dir + "/cert.pem";
    if (!check_checkend(live_cert)) {
        return err("Letsencrypt cert for " + domain + " is still expired/expiring after certonly — not deploying. Check /srv/" + name + "/letsencrypt*.log");
    }

    letsencrypt_deploy(domain);
}

// Decide whether run_on_container_domain should request a cert for this
// domain. Returns false (with a ntc'd reason) for www. names, wildcard-
// covered domains, still-valid datastore certs, unscanned DNS and A records
// pointing elsewhere; deploys an already-valid live cert as a side effect.
function check_container_domain(name, domain) {
    function skip(msg) {
        ntc(name, domain, msg);
        return false;
    }

    // www domains can be considered as subset of domains, its OK if the www points to the same IP.
    if (domain.substring(0, 4) === "www.") return skip("domain.substring(0, 4) === www.");

    if (has_wildcard_certificate(domain)) return skip("Using wildcard certificate");

    if (check_datastore_cert(domain)) return skip("check_datastore_cert");

    // le_dir may be undefined (no lineage yet); the resulting
    // ".../undefined/cert.pem" path simply fails check_checkend's existsSync.
    var le_dir = get_le_dir(domain);
    var cert_pem = "/etc/letsencrypt/live/" + le_dir + "/cert.pem";

    if (check_checkend(cert_pem)) {
        letsencrypt_deploy(domain);
        return skip("check_checkend & letsencrypt_deploy");
    }

    var hasA = false;
    var points_to = "";
    // dns[domain] is populated by dns-scan; a just-added subdomain may not be scanned yet.
    if (!containers[name].dns || !containers[name].dns[domain]) return skip("no DNS scan yet for " + domain);
    if (hosts[HOSTNAME])
        containers[name].dns[domain].A.forEach(function (e) {
            ntc(e, hosts[HOSTNAME].host_ip);

            if (e === hosts[HOSTNAME].host_ip) hasA = true;
            else points_to += e + " ";
        });

    if (!hasA)
        // FIXME(v4): operator precedence bug in the nameserver hint — '+'
        // binds tighter than '||', so a truthy NS[0] short-circuits the whole
        // expression and NS[1] is never shown; intended
        // (NS[0]||"?") + " " + (NS[1]||"?"). Diagnostic text only.
        return skip(
            name +
                " Letsencrypt: no A record for " +
                domain +
                " Note: Namesevers are " +
                (containers[name].dns[domain].NS[0] || "?" + " " + containers[name].dns[domain].NS[1] || "?") +
                " " +
                points_to
        );

    return true;
}

// Check every domain of one container (name + aliases + altnames +
// subdomains, per datastore.container_domains) and request/deploy where due.
function check_container(name) {
    let domains = datastore.container_domains(name);
    for (let n in domains) {
        if (check_container_domain(name, domains[n])) {
            msg("-->", name, domains[n]);
            run_on_container_domain(name, domains[n]);
        }
    }
}

function main() {
    Object.keys(containers).forEach(function (i) {
        // mail containers get their certificates elsewhere, never here
        if (i.substring(0, 5) === "mail.") return;

        var has_subdomains = Array.isArray(containers[i].subdomains) && containers[i].subdomains.length > 0;

        // Explicit subdomains (e.g. fox.v4-devel.d250.hu) sit two labels under the company
        // domain, so the *.d250.hu wildcard does not cover them and they need their own
        // certificate. Process such containers even when they are devel/local/dotless names
        // that otherwise ride the wildcard for their own base name — container_domains() only
        // returns the subdomain fqdns for those, so no base cert is requested.
        if (has_subdomains) return check_container(i);

        // devel/local and dotless container names are covered by the company
        // wildcard (or are not public at all) — no per-name certificate.
        if (
            i.substr(i.length - 6) === ".devel" ||
            i.substr(i.length - 6) === "-devel" ||
            i.substr(i.length - 6) === ".local" ||
            i.substr(i.length - 6) === "-local"
        )
            return;

        if (i.indexOf(".") <= 0) return;

        check_container(i);
    });
}

main();

// Per-domain failures above only log; the run itself always reports success
// (exit() sets exitCode 0 again — see the deploy FIXME about surfacing an
// aggregate error code).
process.exitCode = 0;

exit();
