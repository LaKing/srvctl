#!/bin/node

/*jshint esnext: true */

/*
Usage:
Import the function definitions
const lablib = '../../lablib.js';
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;
...
Use them
msg("hello world");
*/


const os = require('os');
const HOSTNAME = os.hostname();
const execSync = require('child_process').execSync;

// javascript lablib
const $RED='\x1b[31m';
const $GREEN='\x1b[32m';
const $YELLOW='\x1b[33m';
const $BLUE='\x1b[34m';
const $GRAY='\x1b[37m';
const $CLEAR='\x1b[0m';
const $TAG = $BLUE + '[ ' + HOSTNAME.split('.')[0] + ' ]';
const SC_INSTALL_DIR = process.env.SC_INSTALL_DIR;

exports.msg = function msg() {
     console.log($TAG + $GREEN, ...arguments, $CLEAR);   
};

exports.ntc = function ntc() {
     console.log($YELLOW, ...arguments, $CLEAR);   
};
exports.err = function err() {
     console.log($RED +'JS-ERROR',...arguments, $CLEAR);   
};

exports.get = function get(cmd) {
    try {
        var result = execSync(cmd,{shell: "/bin/bash"}).toString();
        if (result.length > 0) return result;
    } catch (e) {
        console.log($RED +'JS-ERROR in get: ', e.stderr.toString(), $CLEAR);
    }
};


exports.run = function run(cmd) {
    try {
        console.log($BLUE + '[' + process.env.USER + '@' + HOSTNAME + ' ' + process.env.PWD.split('/')[process.env.PWD.split('/').length -1] +']#' + $YELLOW , cmd, $CLEAR);
        var result = execSync(cmd,{shell: "/bin/bash"}).toString();
        if (result.length > 0) console.log(result);
    } catch (e) {
        var stderr = '';
        if (e.stderr !== undefined ) stderr =  e.stderr.toString();
        console.log($RED +'JS-ERROR in run: ' + cmd, stderr, $CLEAR);
    }
};


exports.rok = function check(cmd) {
    try {
        var result = execSync(cmd + ' 2> /dev/null',{shell: "/bin/bash"});
        return true;
    } catch (e) {
        /// exit code
        //e.status; 
        /// stdout
        //e.message; 
        //e.stderr;
        return false;
    }
};

exports.exec_function = function run(cmd) {
    try {
        console.log($GREEN , cmd, $CLEAR);
        var prefix = SC_INSTALL_DIR + "/srvctl.sh exec-function ";
        var result = execSync(prefix + cmd,{shell: "/bin/bash"}).toString();
        if (result.length > 0) console.log(result);
    } catch (e) {
        var stderr = '';
        if (e.stderr !== undefined ) stderr =  e.stderr.toString();
        console.log($RED +'ERROR lablib.js exec_function ' + cmd, e, $CLEAR);
    }
};
