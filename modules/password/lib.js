#!/bin/node

/*srvctl */

// password/lib.js - Node password generator: get_password() returns one
// pronounceable Word-Word password (same alphabets/pattern as the bash
// libs/get-password.sh). Consumed via require() by get-password.js and
// modules/usersonhost/main.js.
// FIXME(v4): Math.random() is not cryptographically secure and pattern
// entropy is ~39 bits, yet outputs become user/SSL credentials; use
// crypto.randomInt() in v4.

function random(items) {
    return items[Math.floor(Math.random() * items.length)];
}

function get_password() {
    var ad = ["ld", "ng", "nt", "lf", "br", "kr", "pr", "fr", "gr", "tr", "rt", "st", "x", "q", "w"];
    var aa = ["B", "C", "D", "F", "G", "H", "J", "K", "L", "M", "N", "P", "R", "S", "T", "V", "Z"];
    var ar = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"];
    var bb = ["a", "e", "i", "o", "u"];
    var bc = ["A", "E", "I", "O", "U"];
    var w1 = random([random(bc) + random(ad.concat(ar)), random(aa) + random(bb) + random(ar)]) + random(bb) + random(ad.concat(ar)) + random(bb);
    var w2 = random([random(bc) + random(ad.concat(ar)), random(aa) + random(bb) + random(ar)]) + random(bb) + random(ad.concat(ar)) + random(bb);
    return w1 + '-' + w2;
}

exports.get_password = function() {
    return get_password();  
};

