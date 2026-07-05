#!/bin/node

/* srvctl — modules/named/named.js
 *
 * Authoritative-DNS generator, run by namedcfg (libs/bashlib.sh) at every
 * 'sc regenerate'. It aggregates containers.json from every cluster host
 * (local datastore file for this host, HTTPS fetch from peers, cached under
 * /var/srvctl3/named/<host>.json), then writes:
 *   - /var/named/srvctl.conf                zone declarations (master or
 *                                           slave, per this host's role)
 *   - /var/named/srvctl/<domain>.zone       full zone content, masters only
 *                                           (aliases share the primary's file)
 * Zone content (SOA serial = epoch seconds, NS ns1/ns2.$SC_COMPANY_DOMAIN,
 * wildcard/apex A, SPF/DKIM/DMARC/MX assembly, custom dns_records) is
 * public production DNS — any byte change here changes the farm's DNS.
 *
 * Exit-code protocol (relied on by exif in namedcfg): starts at 99,
 * success 0, DATA-ERROR 111 with a "DATA-ERROR:" line on stderr.
 *
 * Flow trick: the peer fetches are async and there is no await here, so
 * the config is assembled in a process.on("exit") handler after the event
 * loop drains — meaning each run uses the peer caches written by the
 * PREVIOUS run. See the FIXME notes at the exit handler.
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
const os = require("os");
const http = require("http");
const https = require("https");

const CMD = process.argv[2];
// constatnts

const CDN = process.env.SC_COMPANY_DOMAIN;

var datastore = require("../datastore/lib.js");

// constants
const HOSTNAME = os.hostname();
const br = "\n";
const SC_CLUSTERNAME = process.env.SC_CLUSTERNAME;
const SC_CLUSTERS_DATA_FILE = "/etc/srvctl/clusters.json";
const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;
const localhost = "localhost";

process.exitCode = 99;

function exit() {
    process.exitCode = 0;
}

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

// if the default
var is_master = false;
if (datastore.hosts[HOSTNAME]) if (datastore.hosts[HOSTNAME].dns_server === "master") is_master = true;
if (is_master) msg("bind DNS master");
else msg("bind DNS slave");

// variables
//var hosts = datastore.hosts;
//var users = datastore.users;
//var resellers = datastore.resellers;
//var containers = datastore.containers;
var clusters;

var listed_domain_names = [];

// read clusters
try {
    clusters = JSON.parse(fs.readFileSync(SC_CLUSTERS_DATA_FILE));
} catch (err) {
    return_error("READFILE " + SC_CLUSTERS_DATA_FILE + " " + err);
}

var master_servers = "";

Object.keys(clusters).forEach(function (i) {
    Object.keys(clusters[i]).forEach(function (j) {
        if (clusters[i][j].dns_server === "master") {
            // if it has a public IP address
            if (clusters[i][j].host_ip) master_servers += clusters[i][j].host_ip + ";";
        }
    });
});

if (master_servers === "") {
    return_error("could not locate master servers in the cluster configuration");
} else msg("master servers: " + master_servers);

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

    var serial = Math.floor(new Date().getTime() / 1000);

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
    zone += "@        IN SOA        @ hostmaster." + CDN + ". (" + br;
    zone += "                                        " + serial + "        ; serial" + br;
    zone += "                                        1D        ; refresh" + br;
    zone += "                                        1H        ; retry" + br;
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

function get_conf(cluster, host) {
    var conf = "## " + host + br + br;
    var containers = {};
    var file = "/var/srvctl3/named/" + host + ".json";
    if (host === HOSTNAME) file = "/var/srvctl3/datastore/containers.json";

    var hostdata = clusters[cluster][host];
    if (!hostdata.host_ip) return "";

    try {
        containers = JSON.parse(fs.readFileSync(file));
    } catch (error) {
        err("READFILE for " + host + " " + error);
        return conf + br + br;
    }

    if (is_master)
        Object.keys(containers).forEach(function (i) {
            if (i == CDN) return;
            if (!i.includes(".")) return;
            if (listed_domain_names.indexOf(i) >= 0) return msg("DNS: ignoring dublicate listing of " + i + " on " + host);
            listed_domain_names.push(i);
            conf += 'zone "' + i + '" {type master; file "/var/named/srvctl/' + i + '.zone";};' + br;
            fs.writeFileSync("/var/named/srvctl/" + i + ".zone", get_container_zone(cluster, host, hostdata, containers, i));
            if (containers[i].aliases)
                containers[i].aliases.forEach(function (j) {
                    conf += 'zone "' + j + '" {type master; file "/var/named/srvctl/' + i + '.zone";};' + br;
                });
        });

    if (!is_master)
        Object.keys(containers).forEach(function (i) {
            if (i == CDN) return;
            if (!i.includes(".")) return;
            if (listed_domain_names.indexOf(i) >= 0) return msg("DNS: ignoring dublicate listing of " + i + "on" + host);
            listed_domain_names.push(i);
            conf += 'zone "' + i + '" {type slave; masters {' + master_servers + '}; file "/var/named/srvctl/' + i + '.slave.zone";};' + br;
            if (containers[i].aliases)
                containers[i].aliases.forEach(function (j) {
                    conf += 'zone "' + j + '" {type slave; masters {' + master_servers + '}; file "/var/named/srvctl/' + j + '.slave.zone";};' + br;
                });
        });

    return conf + br + br;
}

function make_conf() {
    var conf = "## BIND-CONFIG " + br + br;

    Object.keys(clusters).forEach(function (i) {
        Object.keys(clusters[i]).forEach(function (j) {
            conf += get_conf(i, j);
        });
    });

    return conf;
}

// ---------
// fetch a peer's containers.json over HTTPS (self-signed certs accepted;
// endpoint served by modules/datastore/apps/datastore-server.js behind the
// haproxy ACL) and cache it under /var/srvctl3/named/<host>.json for the
// NEXT run's make_conf.
// FIXME(v4): medium — no effective timeout: the https.Agent timeout only
// arms a socket timeout with no 'timeout' listener and the request is never
// destroyed, so one unresponsive peer can stall this script (and thus
// 'sc regenerate') indefinitely.
function get_host_containers(cluster, host) {
    var ip = clusters[cluster][host].host_ip;
    console.log("get_host_containers", host, ip);
    var req = {
        host: ip, // host
        port: 443,
        path: "/.well-known/srvctl/datastore/containers.json",
        method: "GET",
        rejectUnauthorized: false,
        requestCert: true,
        agent: new https.Agent({ keepAlive: false, timeout: 1000 }),
    };
    https
        .get(req, function (res) {
            const { statusCode } = res;
            const contentType = res.headers["content-type"];

            let error;
            if (statusCode !== 200) {
                error = new Error("Request Failed.\n" + `Status Code: ${statusCode}`);
            } else if (!/^application\/json/.test(contentType)) {
                error = new Error("Invalid content-type.\n" + `Expected application/json but received ${contentType}`);
            }
            if (error) {
                console.error(error.message);
                // consume response data to free up memory
                res.resume();
                return;
            }

            res.setEncoding("utf8");
            let rawData = "";
            res.on("data", (chunk) => {
                rawData += chunk;
            });
            res.on("end", () => {
                try {
                    const parsedData = JSON.parse(rawData);
                    //xhosts[ip] = parsedData;
                    fs.writeFile("/var/srvctl3/named/" + host + ".json", rawData, function (err) {
                        if (err) return_error("WRITEFILE zone " + err);
                    });
                } catch (e) {
                    console.error(e.message, rawData);
                }
            });
        })
        .on("error", (e) => {
            console.error("GET https://" + host + "/.well-known/srvctl/datastore/containers.json", e);
        });
}

//---------
// A little trick here. As there is no real sync version of http.get, we will process the data when the event loop completes - on exit
// FIXME(v4): the local host is fetched over HTTPS too, although get_conf
// reads the local datastore file directly — one request per run is wasted.

Object.keys(clusters).forEach(function (i) {
    //if (i !== SC_CLUSTERNAME)
    Object.keys(clusters[i]).forEach(function (j) {
        if (clusters[i][j].host_ip !== undefined) get_host_containers(i, j);
        //console.log(clusters[i][j].host_ip);
    });
});

// FIXME(v4): medium — this exit handler also runs after return_error's
// process.exit(111): 'exit' listeners still fire and exit() resets
// process.exitCode to 0, which Node re-reads. Concrete case: no master
// with a host_ip triggers return_error above, yet a broken srvctl.conf
// (slave zones with empty 'masters {};') is still written and exif in
// namedcfg sees success, so restart_named reloads BIND on a config that
// fails to load. Related: if clusters.json was unreadable, make_conf
// throws a TypeError on the undefined 'clusters' during exit instead of
// the clean DATA-ERROR path. v4: rewrite with async/await and explicit
// exit paths.

process.on("exit", function () {
    var conf = make_conf();
    //console.log(conf);

    try {
        fs.writeFileSync("/var/named/srvctl.conf", conf);
        msg("wrote named conf");
    } catch (err) {
        return_error("ERROR WRITEFILE named srvctl conf" + err);
    }

    exit();
});
