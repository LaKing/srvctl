// Public inventory is read directly by unprivileged srvctl commands. Keep
// this policy limited to entity records; keys, certificates and other types
// must not inherit it. Explicit chmod makes the contract independent of umask.
const fs = require("node:fs");
const path = require("node:path");
const PUBLIC_TYPES = new Set(["hosts", "users", "containers"]);

function recordMode(type) {
    return PUBLIC_TYPES.has(type) ? 0o644 : 0o600;
}

function prepareTypeDirectory(root, type) {
    const dir = path.join(root, type);
    fs.mkdirSync(dir, { recursive: true });
    if (PUBLIC_TYPES.has(type)) {
        fs.chmodSync(root, 0o755);
        fs.chmodSync(dir, 0o755);
    }
    return dir;
}

// Repair existing inventory without descending into private material or
// following symlinks. Reads never invoke this; regenerate is the repair path.
function repairInventoryPermissions(root) {
    if (!fs.lstatSync(root).isDirectory()) throw new Error("Datastore root must be a directory");
    fs.chmodSync(root, 0o755);
    for (const type of PUBLIC_TYPES) {
        const dir = path.join(root, type);
        // Retain compatibility with stores that still have monolithic files.
        const legacy = path.join(root, type + ".json");
        try {
            if (fs.lstatSync(legacy).isFile()) fs.chmodSync(legacy, recordMode(type));
        } catch (err) { if (err.code !== "ENOENT") throw err; }
        try {
            if (!fs.lstatSync(dir).isDirectory()) continue;
        } catch (err) {
            if (err.code === "ENOENT") continue;
            throw err;
        }
        fs.chmodSync(dir, 0o755);
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            if (entry.isFile() && !entry.name.startsWith(".") && entry.name.endsWith(".json")) {
                fs.chmodSync(path.join(dir, entry.name), recordMode(type));
            }
        }
    }
}

module.exports = { recordMode, prepareTypeDirectory, repairInventoryPermissions };

if (require.main === module) {
    try {
        if (process.argv.length !== 3) throw new Error("usage: permissions.js <datastore-root>");
        repairInventoryPermissions(process.argv[2]);
    } catch (err) {
        console.error("Datastore permission repair failed:", err.message);
        process.exitCode = 113;
    }
}
