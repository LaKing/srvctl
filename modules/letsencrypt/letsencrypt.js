#!/bin/node

/*jshint esnext: true */

const lablib = '../../lablib.js';
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
const fs = require('fs');
const datastore = require('../datastore/lib.js');
const execSync = require('child_process').execSync;
const https = require('https');

const CMD = process.argv[2];
// constatnts

const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';
const SC_CONTAINERS_CERT_DIR = process.env.SC_DATASTORE_DIR + '/cert';
const SC_INSTALL_DIR = process.env.SC_INSTALL_DIR;
const SC_COMPANY_DOMAIN = process.env.SC_COMPANY_DOMAIN;
const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const os = require('os');
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

// We check for validity, and assume it is a wildcard certificate.            
/*
var dont_check_company_domains = false;
var cert_file = "/etc/srvctl/cert/" + SC_COMPANY_DOMAIN + "/" + SC_COMPANY_DOMAIN + ".pem";
if (fs.existsSync(cert_file)) {
    if (execSync('openssl x509 -checkend 604800 -noout -in ' + cert_file)) {
        dont_check_company_domains = true;
        ntc("Letsencrypt: dont check *." + SC_COMPANY_DOMAIN);
    }
}
*/

function is_wildcard_certificate(domain) {
    var cert_file = "/etc/srvctl/cert/" + domain + "/" + domain + ".pem";
    if (fs.existsSync(cert_file)) {
        if (execSync('openssl x509 -noout -subject -in ' + cert_file).indexOf('*') > -1) {
            ntc("Letsencrypt: found wildcard certificate *." + domain);
            return true;
        }
    }
    return false;
}

function has_wildcard_certificate(domain) {
    if (is_wildcard_certificate(domain)) return true;
    if (is_wildcard_certificate(domain.substring(domain.indexOf('.')))) return true;
    return false;
}


// variables
var hosts = datastore.hosts;
var users = datastore.users;
var resellers = datastore.resellers;
var containers = datastore.containers;
var user = '';
var container = '';

var le_dirs = fs.readdirSync("/etc/letsencrypt/live");

function get_le_dir(domain) {
    var le_dir = process.env.SC_COMPANY_DOMAIN;
    le_dirs.forEach(dir => {
        if (dir.substring(0, domain.length + 4) === 'www.' + domain) le_dir = dir;
        if (dir.substring(0, domain.length) === domain) le_dir = dir;
    });
    return le_dir;
}

function deploy(le_dir, domain) {

    var cert_pem = "/etc/letsencrypt/live/" + le_dir + "/cert.pem";
    var fullchain_pem = "/etc/letsencrypt/live/" + le_dir + "/fullchain.pem";
    var privkey_pem = "/etc/letsencrypt/live/" + le_dir + "/privkey.pem";
    var ca_pem = "/etc/letsencrypt/ca.pem";

    if (!fs.existsSync(privkey_pem)) return err("Private key dont exists " + privkey_pem);
    if (!fs.existsSync(fullchain_pem)) return err("Certificate dont exists " + fullchain_pem);
    if (!fs.existsSync(ca_pem)) return err("CA file dont exists " + ca_pem);

    var privkey = fs.readFileSync(privkey_pem, 'UTF8');
    var fullchain = fs.readFileSync(fullchain_pem, 'UTF8');
    var ca = fs.readFileSync(ca_pem, 'UTF8');

    var pem = privkey + br + fullchain + br + ca + br;

    fs.writeFileSync(SC_CONTAINERS_CERT_DIR + '/' + domain + '.pem', pem);
    msg(domain + " letsencrypt certificate deployed");
}

function check_domain(domain) {

    if (has_wildcard_certificate(domain)) return console.log("wildcard certificate found for", domain);

    //if (dont_check_company_domains) {
    //    if (domain.substr(domain.length - SC_COMPANY_DOMAIN.length - 1) === '.' + SC_COMPANY_DOMAIN) return; // console.log(domain, "is part of", SC_COMPANY_DOMAIN, "therefore it should have a wildcard certificate");
    //}

    var cert_file = SC_CONTAINERS_CERT_DIR + "/" + domain + ".pem";
    if (fs.existsSync(cert_file)) {
        if (execSync('openssl x509 -checkend 604800 -noout -in ' + cert_file)) return; // console.log(domain, "has a valid certificate.");
    }

    var le_dir = get_le_dir(domain);
    var cert_pem = "/etc/letsencrypt/live/" + le_dir + "/cert.pem";

    if (fs.existsSync(cert_pem)) {
        msg("Certificate check for " + domain);
        try {
            execSync('openssl x509 -checkend 604800 -noout -in ' + cert_pem);
            deploy(le_dir, domain);
        } catch (err) {
            if (err) containers[domain].dns_scan.A.forEach(function(e) {
                if (e === hosts[HOSTNAME].host_ip) run_on_domain(domain);
            });
        }
    } else {
        msg("New certificate needed for " + domain);
        containers[domain].dns_scan.A.forEach(function(e) {
            if (e === hosts[HOSTNAME].host_ip) run_on_domain(domain);
        });
    }

}


function run_on_domain(domain) {

    // we can check against HOSTNAME if a reverse address is set, but since it is not mandatory ...
    //if (containers[domain].dns_scan.A[hosts[HOSTNAME].host_ip] === undefined) return; 
    var has_www = false;
    containers[domain].www_scan.A.forEach(function(e) {
        if (e === hosts[HOSTNAME].host_ip) has_www = true;
    });

    if (has_www) msg("Certificate required for " + domain + " and www." + domain);
    else msg("Certificate required for " + domain);

    var cmd = "letsencrypt certonly --non-interactive --agree-tos --keep-until-expiring --expand --webroot --webroot-path /var/acme/ -d " + domain + " >> /srv/" + domain + "/letsencrypt.log";
    if (has_www) cmd = "letsencrypt certonly --non-interactive --agree-tos --keep-until-expiring --expand --webroot --webroot-path /var/acme/ -d " + domain + " -d www." + domain + " >> /srv/" + domain + "/letsencrypt.log";
    ntc(cmd);

    try {
        execSync(cmd);
    } catch (err) {
        if (err) return console.log("Letsencypt certonly failure for ", domain, err);
        else msg("Letsencrypt certonly success for " + domain);
    } finally {
        le_dir = get_le_dir(domain);
        deploy(le_dir, domain);
    }
}

function main() {
    Object.keys(containers).forEach(function(i) {
        if ((i.substr(i.length - 6) !== '.devel') && (i.substr(i.length - 6) !== '-devel') && (i.substr(i.length - 6) !== '.local') && (i.substr(i.length - 6) !== '-local') && (i.substring(0, 5) !== 'mail.'))
            check_domain(i);
    });
}

main();

process.exitCode = 0;

//process.on('exit', function() {
//fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
//echo });

exit();

