#!/bin/node

/*srvctl */

function out(msg) {
    console.log(msg);
}

// includes
const fs = require("fs");
const datastore = require("../datastore/lib.js");
const password_lib = require("../password/lib.js");

const lablib = "../../lablib.js";
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;

const execSync = require("child_process").execSync;
const CMD = process.argv[2];
// constatnts

const SRVCTL = process.env.SRVCTL;
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;
const os = require("os");
const HOSTNAME = os.hostname();
const localhost = "localhost";
const br = "\n";
const root = "root";
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
    console.error("main.js ERR:", msg);
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
var user = "";
var container = "";

const $RED = "\x1b[31m";
const $GREEN = "\x1b[32m";
const $YELLOW = "\x1b[33m";
const $BLUE = "\x1b[34m";
const $GRAY = "\x1b[97m";
const $CLEAR = "\x1b[37m";

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;
String.prototype.tab = function(n, c) {
    var val = this.valueOf();
    if (Math.abs(n) <= val.length) {
        return val;
    }
    var m = Math.max(Math.abs(n) - this.length || 0, 0);
    var pad = Array(m + 1).join(String(c || " ").charAt(0));
    //      var pad = String(c || ' ').charAt(0).repeat(Math.abs(n) - this.length);
    return n < 0 ? pad + val : val + pad;
    //      return (n < 0) ? val + pad : pad + val;
};

Object.prototype.length = function() {
    return Object.keys(this).length;
};

console.log("REACTION " + "VE".tab(36) + " " + "IP".tab(16) + " " + "TYPE".tab(12) + " " + "USER".tab(16) + " " + "RESELLER".tab(16) + "INFO".tab(32) + " ");

Object.keys(containers).forEach(function(c) {
    if (SC_USER !== root && containers[c].user !== SC_USER && datastore.container_reseller(c) !== SC_USER) return;

    var ping_cmd = "timeout 0.2 ping -c 1 " + containers[c].ip + " | grep rtt";
    var ping = $RED + "failure ";
    var infos = "";
    var extras = "";
    var is_active = false;
	var color0 = $RED; 
    
    try {
        execSync("timeout 0.2 systemctl is-enabled srvctl-nspawn@" + c + ".service");
    } catch (e) {
    	color0 = $BLUE; 
        infos += " DISABLED";
    }
  
    try {
        execSync("timeout 0.2 systemctl is-active srvctl-nspawn@" + c + ".service");
        ping = color0  + "active  ";
      is_active = true;
    } catch (e) {
    	ping = color0  + "inactive";
    }
  
    try {
      var release = fs.readFileSync("/srv/"+c+"/rootfs/etc/os-release", 'utf8').split('\n');
      infos += ' ' + release[2].split('=')[1] + ' ' + release[3].split('=')[1];      
	} catch (e) {
    	extras += 'OS?';
    }
  
  	if (is_active)
    try {
        ping =
            $GREEN +
            execSync(ping_cmd)
                .toString()
                .split("/")[5] +
            "ms " + $CLEAR;
    } catch (e) {
    	extras += " PING?";
    }

	if (containers[c].bridge) infos += " BRIDGE:"+containers[c].bridge;
  
    if (containers[c].dns_scan) {
        if (containers[c].dns_scan.NS.length === 0) extras += " NS?";
        if (containers[c].dns_scan.MX.length === 0) extras += " MX?";
        if (Object.keys(containers[c].dns_scan.A).length === 0) extras += " A?";
        if (Object.keys(containers[c].dns_scan.AAAA).length === 0) extras += " AAAA?";
    }
    var reseller = containers[c].user;
    if (users[containers[c].user].reseller !== undefined) reseller = users[containers[c].user].reseller;

  	var ip = '';
  	if (containers[c].ip) ip = containers[c].ip;
  
    console.log(
        ping + " " + c.tab(36) + " " + ip.tab(16) + " " + containers[c].type.tab(12) + " " + containers[c].user.tab(16) + " " + reseller.tab(16) + " " + $CLEAR + infos.tab(32) + " " + $RED + extras
    );
});

exit();
