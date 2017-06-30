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
const $CLEAR='\x1b[37m';
const $TAG = $BLUE + '[ ' + HOSTNAME.split('.')[0] + ' ]';

String.prototype.padding = function(n, c){
        var val = this.valueOf();
        if ( Math.abs(n) <= val.length ) {
                return val;
        }
        var m = Math.max((Math.abs(n) - this.length) || 0, 0);
        var pad = Array(m + 1).join(String(c || ' ').charAt(0));
//      var pad = String(c || ' ').charAt(0).repeat(Math.abs(n) - this.length);
        return (n < 0) ? pad + val : val + pad;
//      return (n < 0) ? val + pad : pad + val;

};
        

exports.msg = function msg(str) {
     console.log($TAG + $GREEN, str, $CLEAR);   
};

exports.ntc = function ntc(str) {
     console.log($YELLOW, str, $CLEAR);   
};
exports.err = function err(str) {
     console.log($RED +'ERROR', str, $CLEAR);   
};

exports.get = function get(cmd) {
    try {
        var result = execSync(cmd).toString();
        if (result.length > 0) return result;
    } catch (e) {
        console.log($RED +'ERROR', e.stderr.toString(), $CLEAR);
    }
};


exports.run = function run(cmd) {
    try {
        console.log($BLUE + '[' + process.env.USER + '@' + HOSTNAME + ' ' + process.env.PWD.split('/')[process.env.PWD.split('/').length -1] +']#' + $YELLOW , cmd, $CLEAR);
        var result = execSync(cmd).toString();
        if (result.length > 0) console.log(result);
    } catch (e) {
        console.log($RED +'ERROR', e.stderr.toString(), $CLEAR);
    }
};


exports.rok = function check(cmd) {
    try {
        var result = execSync(cmd + ' 2> /dev/null');
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

