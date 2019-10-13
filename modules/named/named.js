#!/bin/node

/*srvctl */

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
const SC_ROOT = process.env.SC_ROOT;
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

// read clusters
try {
    clusters = JSON.parse(fs.readFileSync(SC_CLUSTERS_DATA_FILE));
} catch (err) {
    return_error("READFILE " + SC_CLUSTERS_DATA_FILE + " " + err);
}

var master_servers = "";

Object.keys(clusters).forEach(function(i) {
    Object.keys(clusters[i]).forEach(function(j) {
        if (clusters[i][j].dns_server === "master") {
            // if it has a public IP address 
            if (clusters[i][j].host_ip) master_servers += clusters[i][j].host_ip + ";";
        }
    });
});

if (master_servers === "") {
    return_error("could not locate master servers in the cluster configuration");
} else msg("master servers: " + master_servers);

function splitstring(s) {
    const re = new RegExp(".{1,33}", "g");
    r = br;
    var a = s.match(re);
    for (var i in a) {
        r += '    "' + a[i] + '"' + br;
    }
    return r;
}

function get_container_zone(cluster, host, hostdata, containers, name, alias) {
    var container = containers[name];
    var zone = ";;" + cluster + " " + host + " " + name + br + br;
    if (alias) zone = ";;" + cluster + " " + host + " " + name + " " + alias + br + br;
    var ip = hostdata.host_ip;
    var spf_string = "v=spf1";

    var serial = Math.floor(new Date().getTime() / 1000);

    //Object.keys(hosts).forEach(function(i) {
    if (hostdata.host_ip !== undefined) spf_string += " ip4:" + hostdata.host_ip;
    if (hostdata.host_ipv6 !== undefined) spf_string += " ip6:" + hostdata.host_ipv6;
    //});

    spf_string += " a mx";

    if (container.use_gsuite) spf_string += " include:_spf.google.com";
    if (container.use_mailchimp) spf_string += " include:servers.mcsv.net";

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
    zone += "*        IN         A        " + ip + br;
    zone += "@        IN         A        " + ip + br;

    if (container.use_gsuite) {
        zone += "; nameservers for google apps" + br;
        zone += "@    IN    MX    1    ASPMX.L.GOOGLE.COM." + br;
        zone += "@    IN    MX    5    ALT1.ASPMX.L.GOOGLE.COM." + br;
        zone += "@    IN    MX    5    ALT2.ASPMX.L.GOOGLE.COM." + br;
        zone += "@    IN    MX    10    ALT3.ASPMX.L.GOOGLE.COM." + br;
        zone += "@    IN    MX    10    ALT4.ASPMX.L.GOOGLE.COM." + br;
    } else zone += "@        IN        MX        10        mail" + br;

    zone += ";; SPF" + br;
    zone += '@        IN        TXT        "' + spf_string + '"' + br;

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

    if (containers["mail." + name] !== undefined) {
        zone += ";; dkim-mailcontainer" + br;
        if (containers["mail." + name]["dkim-mail-domainkey"] !== undefined)
            zone += 'mail._domainkey       IN        TXT       ( "v=DKIM1; k=rsa;"' + splitstring(containers["mail." + name]["dkim-mail-domainkey"]) + " )" + br;
    }

    if (container.use_mailchimp) {
        zone += ";; dkim-mailchimp" + br;
        zone += "k1._domainkey       IN        CNAME       dkim.mcsv.net." + br;
    }

    // temporary
    //if (container.use_gsuite) return zone;

    zone += ";; DMARC" + br;
    if (container.use_gsuite && container["dkim-google-domainkey"] === undefined) err("Missing DKIM google-domainkey in datastore for domain " + name);
    else zone += '_dmarc   TXT ( "v=DMARC1;p=reject;sp=reject;pct=100;adkim=r;aspf=r;fo=1;ri=86400;rua=mailto:webmaster@' + name + '")' + br;

    return zone;
}

function get_conf(cluster, host) {
    var conf = "## " + host + br + br;
    var containers = {};
    var file = "/var/srvctl3/named/" + host + ".json";
    if (host === HOSTNAME) file = "/var/srvctl3/datastore/containers.json";

    var hostdata = clusters[cluster][host];

    try {
        containers = JSON.parse(fs.readFileSync(file));
    } catch (error) {
        err("READFILE for " + host + " " + error);
        return conf + br + br;
    }

    if (is_master)
        Object.keys(containers).forEach(function(i) {
            if (i == CDN) return;
            conf += 'zone "' + i + '" {type master; file "/var/named/srvctl/' + i + '.zone";};' + br;
            fs.writeFileSync("/var/named/srvctl/" + i + ".zone", get_container_zone(cluster, host, hostdata, containers, i));
            if (containers[i].aliases)
                containers[i].aliases.forEach(function(j) {
                    conf += 'zone "' + j + '" {type master; file "/var/named/srvctl/' + i + '.zone";};' + br;
                });
        });

    if (!is_master)
        Object.keys(containers).forEach(function(i) {
            if (i == CDN) return;
            conf += 'zone "' + i + '" {type slave; masters {' + master_servers + '}; file "/var/named/srvctl/' + i + '.slave.zone";};' + br;
            if (containers[i].aliases)
                containers[i].aliases.forEach(function(j) {
                    conf += 'zone "' + j + '" {type slave; masters {' + master_servers + '}; file "/var/named/srvctl/' + j + '.slave.zone";};' + br;
                });
        });

    return conf + br + br;
}

function make_conf() {
    var conf = "## BIND-CONFIG " + br + br;

    Object.keys(clusters).forEach(function(i) {
        Object.keys(clusters[i]).forEach(function(j) {
            conf += get_conf(i, j);
        });
    });

    return conf;
}

// ---------
function get_host_containers(cluster, host) {
    //var ip = clusters[cluster][host].host_ip;
    var req = {
        host: host,
        port: 443,
        path: "/.well-known/srvctl/datastore/containers.json",
        method: "GET",
        rejectUnauthorized: false,
        requestCert: true,
        agent: new https.Agent({ keepAlive: false, timeout: 1000 })
    };
    https
        .get(req, function(res) {
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
            res.on("data", chunk => {
                rawData += chunk;
            });
            res.on("end", () => {
                try {
                    const parsedData = JSON.parse(rawData);
                    //xhosts[ip] = parsedData;
                    fs.writeFile("/var/srvctl3/named/" + host + ".json", rawData, function(err) {
                        if (err) return_error("WRITEFILE zone " + err);
                    });
                } catch (e) {
                    console.error(e.message, rawData);
                }
            });
        })
        .on("error", e => {
            console.error("GET https://" + host + "/.well-known/srvctl/datastore/containers.json", e);
        });
}

//---------
// A little trick here. As there is no real sync version of http.get, we will process the data when the event loop completes - on exit

Object.keys(clusters).forEach(function(i) {
    //if (i !== SC_CLUSTERNAME)
    Object.keys(clusters[i]).forEach(function(j) {
        if (clusters[i][j].host_ip !== undefined) get_host_containers(i, j);
        //console.log(clusters[i][j].host_ip);
    });
});

process.on("exit", function() {
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
