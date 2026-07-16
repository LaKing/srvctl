#!/bin/node

/* srvctl — modules/named/named.js
 *
 * Authoritative-DNS generator, run by namedcfg (libs/bashlib.sh) at every
 * 'sc regenerate'. It aggregates containers from every cluster host (the
 * layout-aware datastore view for this host, HTTPS fetch from peers cached
 * under /var/srvctl3/named/<host>.json), then writes:
 *   - /var/named/srvctl.conf                zone declarations (one elected
 *                                           primary; every other DNS host is
 *                                           a transfer replica)
 *   - /var/named/srvctl/<domain>.zone       full zone content, primary only
 *                                           (aliases share the primary's file)
 * Zone content (monotonic, content-aware SOA serial, NS
 * ns1/ns2.$SC_COMPANY_DOMAIN,
 * wildcard/apex A, SPF/DKIM/DMARC/MX assembly, custom dns_records) is
 * public production DNS — any byte change here changes the farm's DNS.
 *
 * Exit-code protocol (relied on by exif in namedcfg): starts at 99,
 * success 0, DATA-ERROR 111 with a "DATA-ERROR:" line on stderr.
 *
 * Peer snapshots are awaited with a hard timeout before rendering. A fresh
 * valid response atomically replaces its last-good cache. Operator-driven
 * runs require fresh peers; the hourly safety run may use a recent cache.
 * Missing/expired required data fails closed before production publication.
 */

// TODO: in case of duplicate containers, dns should priorize

// The DNS modules take effect on all hosts as it is based mainly on clusters!

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
const net = require("net");
const os = require("os");
const snapshotsLib = require("./lib/snapshots.js");
const topologyLib = require("./lib/topology.js");
const zonefileLib = require("./lib/zonefile.js");
const zonesLib = require("./lib/zones.js");
const clusterConfigLib = require("../containers/lib/cluster-config.js");
const atomicWriteFileSync = snapshotsLib.atomicWriteFileSync;
const loadPeerSnapshot = snapshotsLib.loadPeerSnapshot;
const dnsRoleForHost = topologyLib.dnsRoleForHost;
const electDnsTopology = topologyLib.electDnsTopology;
const SERIAL_PLACEHOLDER = zonefileLib.SERIAL_PLACEHOLDER;
const planZoneUpdate = zonefileLib.planZoneUpdate;
const canonicalZoneName = zonesLib.canonicalZoneName;
const validateZoneOwnership = zonesLib.validateZoneOwnership;

const CMD = process.argv[2];
// constatnts

const CDN = process.env.SC_COMPANY_DOMAIN;

var datastore = require("../datastore/lib.js");

// constants
const HOSTNAME = os.hostname();
const br = "\n";
const SC_CLUSTERNAME = process.env.SC_CLUSTERNAME;
const SC_CLUSTERS_FILE = "/etc/srvctl/clusters.json";
const PEER_CACHE_DIR = "/var/srvctl3/named";
const PEER_FETCH_TIMEOUT_MS = Number(process.env.SC_NAMED_FETCH_TIMEOUT_MS || 3000);
const PEER_CACHE_MAX_AGE_MS = Number(process.env.SC_NAMED_CACHE_MAX_AGE_MS || 21600000);
const REQUIRE_FRESH_PEERS = process.env.SC_NAMED_REQUIRE_FRESH === "true";
const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;
const localhost = "localhost";

process.exitCode = 99;
var fatal_error = false;

function exit() {
    if (!fatal_error) process.exitCode = 0;
}

function return_value(msg) {
    if (msg === undefined || msg === "") process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function return_error(msg) {
    fatal_error = true;
    console.error("DATA-ERROR:", msg);
    process.exitCode = 111;
    process.exit(111);
}

function output(variable, value) {
    console.log(variable + '="' + value + '"');
    process.exitCode = 0;
}

// variables
//var hosts = datastore.hosts;
//var users = datastore.users;
//var resellers = datastore.resellers;
//var containers = datastore.containers;
var clusters;
var peer_container_snapshots = {};

var listed_domain_names = [];

// read clusters
try {
    var parsed_clusters = clusterConfigLib.readClusters(SC_CLUSTERS_FILE);
    clusters = parsed_clusters.clusters;
} catch (err) {
    return_error("READFILE " + SC_CLUSTERS_FILE + " " + err.message);
}

// init.sh pins the generation this invocation dispatched under; the cluster
// lock is long released, so refuse to render zones from a topology that a
// publication replaced meanwhile (the retried run reads coherently).
var pinned_generation = process.env.SC_CANONICAL_CLUSTERS_SHA256;
if (pinned_generation && /^[0-9a-f]{64}$/.test(pinned_generation) &&
    parsed_clusters.sha256 !== pinned_generation) {
    return_error("CLUSTER-GENERATION " + SC_CLUSTERS_FILE +
        " changed during this invocation (dispatched under " +
        pinned_generation + ", read " + parsed_clusters.sha256 + "); retry");
}

var dns_topology;
try {
    dns_topology = electDnsTopology(clusters);
} catch (error) {
    return_error("DNS topology: " + error.message);
}

var local_dns_role = dnsRoleForHost(dns_topology, HOSTNAME);
if (!local_dns_role) return_error("host " + HOSTNAME + " has no DNS role in " + SC_CLUSTERS_FILE);

// `is_master` is kept as the local branch name for the generator, but now
// means the one elected publication primary.  Additional legacy masters are
// replicas, eliminating independently generated competing serials.
var is_master = local_dns_role === "primary";
var master_servers = dns_topology.primaryIp + ";";
var replica_servers = dns_topology.replicaIps.map(function(ip) { return ip + ";"; }).join("");
var replica_transfer_clients = dns_topology.replicaAclIps.map(function(ip) { return ip + ";"; }).join("");
var local_dns_host = is_master ? dns_topology.primary :
    dns_topology.replicas.find(function(host) { return host.hostname === HOSTNAME; });
var soa_primary_name;
try {
    soa_primary_name = canonicalZoneName(
        dns_topology.primary.config.dns_authoritative_name || "ns1." + CDN);
} catch (error) {
    return_error("DNS authoritative name: " + error.message);
}

if (is_master) msg("bind DNS primary " + dns_topology.primary.hostname);
else msg("bind DNS replica of " + dns_topology.primary.hostname);
msg("DNS primary server: " + master_servers);
if (dns_topology.usedLegacyFallback) {
    ntc("dns_primary is not set; elected sole legacy DNS master " +
        dns_topology.primary.hostname + " (set dns_primary=true to make the role explicit)");
}

// split a DKIM key into 33-char quoted chunks for the zone-file TXT record
// FIXME(v4): low — 'r = br' creates an implicit global (no var); works only
// because this script runs non-strict.
function splitstring(s) {
    const re = new RegExp(".{1,33}", "g");
    r = br;
    var a = s.match(re);
    for (var i in a) {
        r += '    "' + a[i] + '"' + br;
    }
    return r;
}

const tab = "	";

function get_container_zone(cluster, host, hostdata, containers, name, alias) {
    var container = containers[name];
    var zone = ";;" + cluster + " " + host + " " + name + br + br;
    if (alias) zone = ";;" + cluster + " " + host + " " + name + " " + alias + br + br;

    var ip = hostdata.host_ip;

    // allow overriding the IP from the host
    if (container.use_host_ip) ip = container.use_host_ip;

    var spf_string = "v=spf1";

    if (container.use_host_ip !== undefined) spf_string += " ip4:" + container.use_host_ip;
    if (hostdata.host_ip !== undefined) spf_string += " ip4:" + hostdata.host_ip;
    if (hostdata.host_ipv6 !== undefined) spf_string += " ip6:" + hostdata.host_ipv6;

    if (container.override_in_a_ip) if (container.override_in_a_ip !== "none") spf_string += " ip4:" + container.override_in_a_ip;

    spf_string += " a mx";

    if (container.use_gsuite) spf_string += " include:_spf.google.com";
    if (container.use_mailchimp) spf_string += " include:servers.mcsv.net";
    if (container.use_mlsend) spf_string += " include:_spf.mlsend.com";

    spf_string += " ~all";

    zone += "$TTL 1D" + br;
    zone += "@        IN SOA        " + soa_primary_name + ". hostmaster." + CDN + ". (" + br;
    zone += "                                        " + SERIAL_PLACEHOLDER + "        ; serial" + br;
    zone += "                                        15M        ; refresh" + br;
    zone += "                                        5M        ; retry" + br;
    zone += "                                        1W        ; expire" + br;
    zone += "                                        3H )        ; minimum" + br;
    zone += "        IN         NS        ns1." + CDN + "." + br;
    zone += "        IN         NS        ns2." + CDN + "." + br;
    //zone += "        IN         NS        ns3." + CDN + "." + br;
    //zone += "        IN         NS        ns4." + CDN + "." + br;

    if (container.override_in_a_ip && container.override_in_a_ip !== "none") {
        zone += "*        IN         A        " + container.override_in_a_ip + br;
        zone += "@        IN         A        " + container.override_in_a_ip + br;
    } else {
        zone += "*        IN         A        " + ip + br;
        zone += "@        IN         A        " + ip + br;
    }

    let defaultMX = true;

    if (container.use_gsuite) {
        zone += "; nameservers for google apps" + br;
        zone += "@    IN    MX    1    ASPMX.L.GOOGLE.COM." + br;
        zone += "@    IN    MX    5    ALT1.ASPMX.L.GOOGLE.COM." + br;
        zone += "@    IN    MX    5    ALT2.ASPMX.L.GOOGLE.COM." + br;
        zone += "@    IN    MX    10    ALT3.ASPMX.L.GOOGLE.COM." + br;
        zone += "@    IN    MX    10    ALT4.ASPMX.L.GOOGLE.COM." + br;
        defaultMX = false;
    } else zone += ";; SPF" + br;

    if (container.spf_record) zone += '@        IN        TXT        "' + container.spf_record + '"' + br;
    else zone += '@        IN        TXT        "' + spf_string + '"' + br;

    // https://en.wikipedia.org/wiki/Zone_file
    if (container.dns_records !== undefined) {
        container.dns_records.forEach(function (o) {
            let record_name = o.name || "@";
            let record_ttl = o.ttl || "";
            let record_class = o.class || "IN";
            let record_type = o.type || "A";
            let record_priority = o.priority || "";
            let record_data = o.data || ip;

            zone += ";; custom DNS record for " + record_data + br;
            zone += record_name + tab + record_ttl + tab + record_class + tab + record_type + tab + record_priority + tab + record_data + br;

            if (record_type === "MX") defaultMX = false;
        });
    }

    if (defaultMX) zone += "@        IN        MX        10        mail" + br;

    if (container["google-site-verification"] !== undefined) {
        zone += ";; google-site-verification" + br;
        zone += "@       IN        TXT       google-site-verification=" + container["google-site-verification"] + br;
    }

    if (container["facebook-domain-verification"] !== undefined) {
        zone += ";; facebook-domain-verification" + br;
        zone += "@       IN        TXT       facebook-domain-verification=" + container["facebook-domain-verification"] + br;
    }

    if (container["dkim-custom-domainkey"] !== undefined) {
        zone += ";; dkim-custom" + br;
        zone += 'default._domainkey       IN        TXT       ( "v=DKIM1; k=rsa;"' + splitstring(container["dkim-custom-domainkey"]) + " )" + br;
    } else {
        if (container["dkim-default-domainkey"] !== undefined) {
            zone += ";; dkim-default" + br;
            zone += 'default._domainkey       IN        TXT       ( "v=DKIM1; k=rsa;"' + splitstring(container["dkim-default-domainkey"]) + " )" + br;
        }

        if (container["dkim-mail-domainkey"] !== undefined) {
            zone += ";; dkim-mail" + br;
            zone += 'mail._domainkey       IN        TXT       ( "v=DKIM1; k=rsa;"' + splitstring(container["dkim-mail-domainkey"]) + " )" + br;
        }

        if (container["dkim-google-domainkey"] !== undefined) {
            zone += ";; dkim-google" + br;
            zone += 'google._domainkey       IN        TXT       ( "v=DKIM1; k=rsa;"' + splitstring(container["dkim-google-domainkey"]) + " )" + br;
        }

        if (container["dkim-mlsend-domainkey"] !== undefined) {
            zone += ";; dkim-mlsend" + br;
            zone += 'ml._domainkey       IN        TXT       ( "v=DKIM1; k=rsa;"' + splitstring(container["dkim-mlsend-domainkey"]) + " )" + br;
        }

        if (containers["mail." + name] !== undefined) {
            zone += ";; dkim-mailcontainer" + br;
            if (containers["mail." + name]["dkim-mail-domainkey"] !== undefined)
                zone += 'mail._domainkey       IN        TXT       ( "v=DKIM1; k=rsa;"' + splitstring(containers["mail." + name]["dkim-mail-domainkey"]) + " )" + br;
        }

        if (container.use_mailchimp) {
            zone += ";; dkim-mailchimp" + br;
            zone += "k1._domainkey       IN        CNAME       dkim.mcsv.net." + br;
            zone += "k2._domainkey       IN        CNAME       dkim2.mcsv.net." + br;
            zone += "k3._domainkey       IN        CNAME       dkim3.mcsv.net." + br;
        }
    }

    // the use of dmarc is the default
    if (container.use_dmarc === false) return zone;
    else {
        if (container.dns_records !== undefined) if (container.dns_records.some((e) => e.name === "_dmarc")) return zone;
        zone += ";; DMARC" + br;
        // FIXME(v4): low — for a use_gsuite domain missing its google
        // domainkey the DMARC record is silently omitted (err only prints,
        // to stdout via lablib.js); mail policy weakens without failing.
        if (container.use_gsuite && container["dkim-google-domainkey"] === undefined) err("Missing DKIM google-domainkey in datastore for domain " + name);
        else zone += '_dmarc   TXT ( "v=DMARC1;p=reject;sp=reject;pct=100;adkim=r;aspf=r;fo=1;ri=86400;rua=mailto:webmaster@' + name + '")' + br;

    }

    return zone;
}

// Zone files are planned in memory first.  A read/render failure therefore
// leaves both the installed zones and srvctl.conf untouched instead of
// publishing a partial generation.
var pending_zone_updates = [];

function plan_container_zone(path, template) {
    var previous;
    try {
        previous = fs.readFileSync(path, "utf8");
    } catch (error) {
        if (error.code !== "ENOENT") throw error;
    }

    var update = planZoneUpdate(template, previous);
    if (update.changed) {
        pending_zone_updates.push({ path: path, content: update.content, serial: update.serial });
    }
    return update;
}

function replication_source_statement(kind, address) {
    if (!address) return "";
    return kind + (net.isIP(address) === 6 ? "-source-v6 " : "-source ") +
        address + "; ";
}

function primary_zone_statement(name, file) {
    var transfer = 'allow-transfer {' + (replica_transfer_clients || "none;") + '};';
    var notification = "notify no; ";
    if (replica_servers) {
        notification = 'notify explicit; also-notify {' + replica_servers + '}; ';
    }
    return 'zone "' + name + '" {' +
        'type master; file "' + file + '"; ' + notification +
        replication_source_statement("notify", dns_topology.primary.config.dns_replication_source) +
        transfer + '};' + br;
}

function replica_zone_statement(name, file) {
    return 'zone "' + name + '" {' +
        'type slave; masters {' + master_servers + '}; ' +
        'allow-notify {' + dns_topology.primaryAclIp + ';}; ' +
        replication_source_statement("transfer", local_dns_host.config.dns_replication_source) +
        'file "' + file + '";};' + br;
}

function containers_for_host(host) {
    if (host === HOSTNAME) {
        // datastore.containers merges v3 monolithic data with v4 per-entity
        // records (or treats per-entity as authoritative after migration).
        return datastore.containers;
    }
    if (!Object.prototype.hasOwnProperty.call(peer_container_snapshots, host)) {
        throw new Error("no prepared containers snapshot for " + host);
    }
    return peer_container_snapshots[host];
}

function get_conf(cluster, host) {
    var conf = "## " + host + br + br;
    var hostdata = clusters[cluster][host];
    if (!hostdata.host_ip) return "";
    var containers = containers_for_host(host);

    if (is_master)
        Object.keys(containers).forEach(function (i) {
            if (i == CDN) return;
            if (!i.includes(".")) return;
            if (listed_domain_names.indexOf(i) >= 0) return msg("DNS: ignoring dublicate listing of " + i + " on " + host);
            listed_domain_names.push(i);
            var zonefile = "/var/named/srvctl/" + i + ".zone";
            conf += primary_zone_statement(i, zonefile);
            plan_container_zone(zonefile, get_container_zone(cluster, host, hostdata, containers, i));
            if (containers[i].aliases)
                containers[i].aliases.forEach(function (j) {
                    conf += primary_zone_statement(j, zonefile);
                });
        });

    if (!is_master)
        Object.keys(containers).forEach(function (i) {
            if (i == CDN) return;
            if (!i.includes(".")) return;
            if (listed_domain_names.indexOf(i) >= 0) return msg("DNS: ignoring dublicate listing of " + i + "on" + host);
            listed_domain_names.push(i);
            conf += replica_zone_statement(i, "/var/named/srvctl/" + i + ".slave.zone");
            if (containers[i].aliases)
                containers[i].aliases.forEach(function (j) {
                    conf += replica_zone_statement(j, "/var/named/srvctl/" + j + ".slave.zone");
                });
        });

    return conf + br + br;
}

function make_conf() {
    var conf = "## BIND-CONFIG " + br + br;
    var zone_sources = [];
    pending_zone_updates = [];
    listed_domain_names = [];

    Object.keys(clusters).forEach(function(cluster) {
        Object.keys(clusters[cluster]).forEach(function(host) {
            if (!clusters[cluster][host].host_ip) return;
            zone_sources.push({
                cluster: cluster,
                host: host,
                containers: containers_for_host(host),
            });
        });
    });
    // Zone names and ownership are validated as a complete set before a
    // single zone is rendered or published. This catches alias/base and
    // cross-host collisions that BIND otherwise rejects only at activation.
    validateZoneOwnership(zone_sources, CDN);

    Object.keys(clusters).forEach(function (i) {
        Object.keys(clusters[i]).forEach(function (j) {
            conf += get_conf(i, j);
        });
    });

    return conf;
}

// Fetch every peer before rendering. A bounded fresh HTTPS snapshot wins;
// otherwise its atomically written last-good cache is used. If neither is
// available, Promise.all rejects and nothing is generated or published.
async function prepare_peer_snapshots() {
    fs.mkdirSync(PEER_CACHE_DIR, { recursive: true });
    var pending = [];

    Object.keys(clusters).forEach(function(cluster) {
        Object.keys(clusters[cluster]).forEach(function(host) {
            var hostdata = clusters[cluster][host];
            if (host === HOSTNAME || !hostdata.host_ip) return;
            pending.push(loadPeerSnapshot({
                cacheDir: PEER_CACHE_DIR,
                hostname: host,
                ip: hostdata.host_ip,
                timeoutMs: PEER_FETCH_TIMEOUT_MS,
                maxCacheAgeMs: PEER_CACHE_MAX_AGE_MS,
                requireFresh: REQUIRE_FRESH_PEERS,
            }).then(function(result) {
                return { host: host, result: result };
            }));
        });
    });

    var loaded = await Promise.all(pending);
    loaded.forEach(function(entry) {
        peer_container_snapshots[entry.host] = entry.result.snapshot;
        if (entry.result.source === "cache") {
            ntc("using last-good containers cache for " + entry.host +
                " after fresh fetch failed: " + entry.result.freshError.message);
        } else {
            msg("fetched containers snapshot for " + entry.host);
        }
    });
}

function publish_generated_config(conf) {
    // Each replacement is atomic. Zone data is committed first and the BIND
    // include last, so a new declaration never points at a partial zone file.
    pending_zone_updates.forEach(function(update) {
        atomicWriteFileSync(update.path, update.content);
        msg("wrote zone " + update.path + " serial " + update.serial);
    });
    atomicWriteFileSync("/var/named/srvctl.conf", conf);
    msg("wrote named conf");
}

async function main() {
    try {
        if (!Number.isFinite(PEER_FETCH_TIMEOUT_MS) || PEER_FETCH_TIMEOUT_MS <= 0) {
            throw new Error("invalid SC_NAMED_FETCH_TIMEOUT_MS: " + PEER_FETCH_TIMEOUT_MS);
        }
        if (!Number.isFinite(PEER_CACHE_MAX_AGE_MS) || PEER_CACHE_MAX_AGE_MS < 0) {
            throw new Error("invalid SC_NAMED_CACHE_MAX_AGE_MS: " + PEER_CACHE_MAX_AGE_MS);
        }
        await prepare_peer_snapshots();
        // make_conf performs every source/old-zone read and render before the
        // first write, so fatal input errors cannot leave a partial result.
        var conf = make_conf();
        publish_generated_config(conf);
        exit();
    } catch (error) {
        return_error("GENERATE named configuration " + error);
    }
}

main();
