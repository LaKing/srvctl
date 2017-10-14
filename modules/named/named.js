#!/bin/node

/*jshint esnext: true */

function out(msg) {
    console.log(msg);
}

// includes
const fs = require('fs');
const os = require('os');
const http = require('http');

const CMD = process.argv[2];
// constatnts

const CDN = process.env.SC_COMPANY_DOMAIN;

var datastore = require('../datastore/lib.js');


// constants
const HOSTNAME = os.hostname();
const br = '\n';
const SC_CLUSTERNAME = process.env.SC_CLUSTERNAME;
const SC_CLUSTERS_DATA_FILE = "/etc/srvctl/data/clusters.json";
const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const localhost = 'localhost';

process.exitCode = 99;

function exit() {
    process.exitCode = 0;
}

function return_value(msg) {
    if (msg === undefined || msg === '') process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
    process.exitCode = 111;
    process.exit(111);
}

function output(variable, value) {
    console.log(variable + '="' + value + '"');
    process.exitCode = 0;
}



// variables
var hosts = datastore.hosts;
var users = datastore.users;
var resellers = datastore.resellers;
var containers = datastore.containers;
var clusters;
try {
    clusters = JSON.parse(fs.readFileSync(SC_CLUSTERS_DATA_FILE));
} catch (err) {
    return_error('READFILE ' + SC_CLUSTERS_DATA_FILE + ' ' + err);
}

function get_container_zone(i) {
    var container = containers[i];
    var zone = '';
    var ip = datastore.container_host_ip(container);
    var spf_string = "v=spf1";

    var serial = Math.floor(new Date().getTime() / 1000);

    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].host_ip !== undefined) spf_string += " ip4:" + hosts[i].host_ip;
        if (hosts[i].host_ipv6 !== undefined) spf_string += " ip6:" + hosts[i].host_ipv6;
    });

    spf_string += " a mx";

    if (container.use_gsuite) spf_string += " include:_spf.google.com ~all";
    else spf_string += " -all";

    zone += "$TTL 1D" + br;
    zone += "@        IN SOA        @ hostmaster." + CDN + ". (" + br;
    zone += "                                        " + serial + "        ; serial" + br;
    zone += "                                        1D        ; refresh" + br;
    zone += "                                        1H        ; retry" + br;
    zone += "                                        1W        ; expire" + br;
    zone += "                                        3H )        ; minimum" + br;
    zone += "        IN         NS        ns1." + CDN + "." + br;
    zone += "        IN         NS        ns2." + CDN + "." + br;
    zone += "        IN         NS        ns3." + CDN + "." + br;
    zone += "        IN         NS        ns4." + CDN + "." + br;
    zone += "*        IN         A        " + ip + br;
    zone += "@        IN         A        " + ip + br;

    if (container.use_gsuite) {
        zone += "; nameservers for google apps" + br;
        zone += "@    IN    MX    1    ASPMX.L.GOOGLE.COM" + br;
        zone += "@    IN    MX    5    ALT1.ASPMX.L.GOOGLE.COM" + br;
        zone += "@    IN    MX    5    ALT2.ASPMX.L.GOOGLE.COM" + br;
        zone += "@    IN    MX    10    ALT3.ASPMX.L.GOOGLE.COM" + br;
        zone += "@    IN    MX    10    ALT4.ASPMX.L.GOOGLE.COM" + br;
    } else zone += "@        IN        MX        10        mail" + br;

    zone += '@        IN        TXT        "' + spf_string + '"' + br;

    if (container["dkim-default-domainkey"] !== undefined) zone += 'default._domainkey       IN        TXT       ( "v=DKIM1; k=rsa; " "' + container["dkim-default-domainkey"] + '" )' + br;
    if (container["dkim-mail-domainkey"] !== undefined) zone += 'mail._domainkey       IN        TXT       ( "v=DKIM1; k=rsa; " "' + container["dkim-mail-domainkey"] + '" )' + br;

    if (containers["mail." + i] !== undefined) {
        if (containers["mail." + i]["dkim-mail-domainkey"] !== undefined) zone += 'mail._domainkey       IN        TXT       ( "v=DKIM1; k=rsa; " "' + containers["mail." + i]["dkim-mail-domainkey"] + '" )' + br;
    }
    return zone;
}

// each cluster may have one master server, but can can have any number of slaves.

var master_server_ip = '';

Object.keys(hosts).forEach(function(i) {
    if (hosts[i].dns_server === 'master') master_server_ip = hosts[i].host_ip;
});

var zones = '## ' + SC_CLUSTERNAME + br + br;

if (hosts[HOSTNAME].dns_server === 'master') {
    Object.keys(containers).forEach(function(i) {
        zones += 'zone "' + i + '" {type master; file "/var/named/srvctl/' + i + '.zone";};' + br;
        fs.writeFile("/var/named/srvctl/" + i + ".zone", get_container_zone(i), function(err) {
            if (err) return_error('WRITEFILE zone ' + err);
        });
    });
} else {
    Object.keys(containers).forEach(function(i) {
        zones += 'zone "' + i + '" {type slave; masters {' + master_server_ip + ';}; file "/var/named/srvctl/' + i + '.slave.zone";};' + br;
    });
}

zones += br + br + "## Other clusters" + br + br;

// xhosts are the hosts from all other clusters
var xhosts = {};

// ---------
function get_host_containers(ip) {

    http.get('http://' + ip + '/.well-known/srvctl/datastore/containers.json', function(res) {
        const {
            statusCode
        } = res;
        const contentType = res.headers['content-type'];

        let error;
        if (statusCode !== 200) {
            error = new Error('Request Failed.\n' +
                `Status Code: ${statusCode}`);
        } else if (!/^application\/json/.test(contentType)) {
            error = new Error('Invalid content-type.\n' +
                `Expected application/json but received ${contentType}`);
        }
        if (error) {
            console.error(error.message);
            // consume response data to free up memory
            res.resume();
            return;
        }

        res.setEncoding('utf8');
        let rawData = '';
        res.on('data', (chunk) => {
            rawData += chunk;
        });
        res.on('end', () => {
            try {
                const parsedData = JSON.parse(rawData);
                xhosts[ip] = parsedData;
                fs.writeFile("/var/local/srvctl/" + ip + ".json", rawData, function(err) {
                    if (err) return_error('WRITEFILE zone ' + err);
                });
            } catch (e) {
                console.error(e.message);
            }
        });
    }).on('error', (e) => {
        console.error(`Got error: ${e.message}`);
        try {
            xhosts[ip] = JSON.parse(fs.readFileSync("/var/local/srvctl/" + ip + ".json"));
        } catch (err) {
            return_error('READFILE ' + ip + '.json ' + err);
        }

    });

}

//---------
// A little trick here. As there is no real sync version of http.get, we will process the data when the event loop completes - on exit

Object.keys(clusters).forEach(function(i) {
    if (i !== SC_CLUSTERNAME)
        Object.keys(clusters[i]).forEach(function(j) {
            if (clusters[i][j].host_ip !== undefined)
                get_host_containers(clusters[i][j].host_ip);
            //console.log(clusters[i][j].host_ip);
        });
});

function make_xslaves(xhosts) {
    var xc = {};
    Object.keys(xhosts).forEach(function(i) {
        Object.keys(xhosts[i]).forEach(function(j) {
            xc[j] = i;
            if (xhosts[i][j].aliases !== undefined)
                for (k = 0; k < xhosts[i][j].aliases.length; k++) {
                    xc[xhosts[i][j].aliases[k]] = i;
                }
        });
    });

    var xslaves = "";
    Object.keys(xc).forEach(function(l) {
        xslaves += 'zone "' + l + '" {type slave; masters {' + xc[l] + ';}; file "/var/named/srvctl/' + l + '.slave.zone";};' + br;
    });
    return xslaves;
}



process.on('exit', function() {

    try {
        fs.writeFileSync("/var/named/srvctl.conf", zones + make_xslaves(xhosts));
        console.log('[ OK ] named srvctl conf');
    } catch (err) {
        return_error('WRITEFILE named srvctl conf' + err);
    }

    exit();
});

/*
try {
    fs.writeFileSync(SC_HOST_CONF, out);
} catch (err) {
    return_error('WRITEFILEFILE ' + SC_HOST_CONF + ' ' + err);
}

try {
    fs.writeFileSync(SC_HOSTS_DATA_FILE, JSON.stringify(hosts, null, 2));
} catch (err) {
    return_error('WRITEFILEFILE ' + SC_HOSTS_DATA_FILE + ' ' + err);
}

*/
