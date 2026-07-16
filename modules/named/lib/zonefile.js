"use strict";

/* Pure SOA-serial planning used by the authoritative-zone generator. */

const SERIAL_PLACEHOLDER = "__SRVCTL_SOA_SERIAL__";
const MAX_SERIAL = 0xffffffff;
const SERIAL_RE = /^([ \t]*)(\d+|__SRVCTL_SOA_SERIAL__)([ \t]+;[ \t]*serial[ \t]*)$/m;

function serialFromZone(content) {
    if (typeof content !== "string") return null;
    const match = content.match(SERIAL_RE);
    if (!match || match[2] === SERIAL_PLACEHOLDER) return null;
    const serial = Number(match[2]);
    if (!Number.isSafeInteger(serial) || serial < 0 || serial > MAX_SERIAL) return null;
    return serial;
}

function normalizedZone(content) {
    if (typeof content !== "string" || !SERIAL_RE.test(content)) {
        throw new Error("zone content has no recognizable SOA serial line");
    }
    return content.replace(SERIAL_RE, "$1" + SERIAL_PLACEHOLDER + "$3");
}

function insertSerial(template, serial) {
    if (!Number.isSafeInteger(serial) || serial < 0 || serial > MAX_SERIAL) {
        throw new Error("SOA serial is outside the unsigned 32-bit range: " + serial);
    }
    return normalizedZone(template).replace(SERIAL_PLACEHOLDER, String(serial));
}

function planZoneUpdate(template, previousContent, epochSeconds) {
    const normalizedTemplate = normalizedZone(template);
    const previousSerial = serialFromZone(previousContent);

    if (previousSerial !== null && normalizedZone(previousContent) === normalizedTemplate) {
        return {
            changed: false,
            serial: previousSerial,
            content: previousContent,
        };
    }

    let now = epochSeconds;
    if (now === undefined) now = Math.floor(Date.now() / 1000);
    now = Math.floor(Number(now));
    if (!Number.isSafeInteger(now) || now < 0 || now > MAX_SERIAL) {
        throw new Error("epoch SOA serial is outside the unsigned 32-bit range: " + now);
    }

    const serial = previousSerial === null ? now : Math.max(now, previousSerial + 1);
    if (serial > MAX_SERIAL) {
        throw new Error("SOA serial exhausted its unsigned 32-bit range after " + previousSerial);
    }

    return {
        changed: true,
        serial: serial,
        content: insertSerial(normalizedTemplate, serial),
    };
}

module.exports = {
    SERIAL_PLACEHOLDER: SERIAL_PLACEHOLDER,
    insertSerial: insertSerial,
    normalizedZone: normalizedZone,
    planZoneUpdate: planZoneUpdate,
    serialFromZone: serialFromZone,
};
