#!/bin/node

/*jshint esnext: true */

function out(msg) {
    console.log(msg);
}

// includes
var fs = require('fs');

const CMD = process.argv[2];
// constatnts

const CDN = process.env.SC_COMPANY_DOMAIN;

var datastore = require('../datastore/lib.js');

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const os =  require('os');
const HOSTNAME = os.hostname();
const localhost = 'localhost';
const br = '\n';
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

var master_server_ip = '';

Object.keys(hosts).forEach(function(i) {
    if (hosts[i].dns_server === 'master') master_server_ip = hosts[i].host_ip;
});

if (CMD === 'master') {
    var zones = '';
    Object.keys(containers).forEach(function(i) {
        zones += 'zone "' + i + '" {type master; file "/var/named/srvctl/' + i + '.zone";};' + br;
        fs.writeFile("/var/named/srvctl/" + i + ".zone", get_container_zone(i), function(err) {
            if (err) return_error('WRITEFILE zone ' + err);
        });
    });

    fs.writeFile("/var/named/srvctl.conf", zones, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] named srvctl master conf');
    });

    exit();
}

if (CMD === 'slave') {
    var slaves = '';
    Object.keys(containers).forEach(function(i) {
        slaves += 'zone "' + i + '" {type slave; masters {' + master_server_ip + ';}; file "/var/named/srvctl/' + i + '.slave.zone";};' + br;
    });
    fs.writeFile("/var/named/srvctl.conf", slaves, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] named srvctl slave conf');
    });

    exit();
}
