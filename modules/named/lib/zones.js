"use strict";

/* Validate authoritative zone ownership before named.js renders any files. */

function canonicalZoneName(name) {
    if (typeof name !== "string" || name.length === 0) {
        throw new Error("zone name must be a non-empty string");
    }
    const canonical = name.endsWith(".") ? name.slice(0, -1).toLowerCase() : name.toLowerCase();
    if (name !== canonical) {
        throw new Error("zone name must be lowercase without a trailing dot: " + name);
    }
    if (canonical.length > 253 || !canonical.includes(".")) {
        throw new Error("invalid authoritative zone name: " + name);
    }
    canonical.split(".").forEach(function(label) {
        if (label.length < 1 || label.length > 63 ||
            !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label)) {
            throw new Error("invalid authoritative zone name: " + name);
        }
    });
    return canonical;
}

function validateZoneOwnership(sources, reservedName) {
    const owners = new Map();
    const reserved = canonicalZoneName(reservedName);

    function reserve(zone, owner) {
        const canonical = canonicalZoneName(zone);
        if (canonical === reserved) {
            throw new Error("alias attempts to own reserved zone " + canonical + " from " + owner);
        }
        const existing = owners.get(canonical);
        if (existing) {
            throw new Error("zone " + canonical + " is declared by both " + existing + " and " + owner);
        }
        owners.set(canonical, owner);
    }

    sources.forEach(function(source) {
        const containers = source.containers;
        if (!containers || typeof containers !== "object" || Array.isArray(containers)) {
            throw new Error("containers snapshot for " + source.host + " is not an object");
        }
        Object.keys(containers).forEach(function(name) {
            // Preserve the historical skip for service records/dotless
            // container names and for the company infrastructure zone.
            if (!name.includes(".")) return;
            const canonical = canonicalZoneName(name);
            if (canonical === reserved) return;

            const owner = source.cluster + "/" + source.host + "/" + name;
            reserve(name, owner + " (base)");

            const aliases = containers[name] && containers[name].aliases;
            if (aliases === undefined) return;
            if (!Array.isArray(aliases)) {
                throw new Error("aliases for " + name + " must be an array");
            }
            aliases.forEach(function(alias) {
                reserve(alias, owner + " (alias)");
            });
        });
    });

    return owners;
}

module.exports = {
    canonicalZoneName: canonicalZoneName,
    validateZoneOwnership: validateZoneOwnership,
};
