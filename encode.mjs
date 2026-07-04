// run in the project root

import { readFileSync } from "fs";
import { readdir, readFile, writeFile, realpath, lstat } from "fs/promises";
import { join, extname, basename } from "path";
const allowedExtensions = [".mjs", ".sh", ".js"];

const CWD = process.cwd();
const PROJECT = basename(CWD);

// Set the output file path
let version;
try {
    version = readFileSync(CWD + "/version", "utf8");
} catch (err) {
    console.error("Error reading version file:", err);
    process.exit();
}

const outputFilePath = CWD + "/var/tools/" + PROJECT + "." + version.trim() + ".txt";

// Helper function to resolve real paths while handling broken symlinks
async function getRealPath(path) {
    try {
        const realPath = await realpath(path);
        return realPath;
    } catch {
        // Return original path if realpath fails (e.g., broken symlink)
        return path;
    }
}

async function getFiles(dir, visitedPaths = new Set()) {
    let files = [];

    // Prevent infinite loops from circular symlinks by tracking visited paths
    const realDir = await getRealPath(dir);
    if (visitedPaths.has(realDir)) {
        return files;
    }
    visitedPaths.add(realDir);

    // Read the directory content
    const entries = await readdir(dir, { withFileTypes: true });

    // Iterate over each entry
    for (const entry of entries) {
        const fullPath = join(dir, entry.name);

        // Skip excluded directories
        if (entry.name === "node_modules" || entry.name === ".git" || entry.name === "var" || entry.name === "cert") {
            continue;
        }

        try {
            // Get the stats with symlink resolution
            const stats = await lstat(fullPath);

            if (stats.isSymbolicLink()) {
                // Handle symlink
                const realPath = await getRealPath(fullPath);
                const linkStats = await lstat(realPath);

                if (linkStats.isDirectory()) {
                    // Recurse into symlinked directory
                    files = files.concat(await getFiles(realPath, visitedPaths));
                } else if (linkStats.isFile()) {
                    // Add symlinked file
                    files.push(fullPath);
                }
            } else if (stats.isDirectory()) {
                // Regular directory handling
                files = files.concat(await getFiles(fullPath, visitedPaths));
            } else if (stats.isFile()) {
                // Regular file handling
                files.push(fullPath);
            }
        } catch (error) {
            console.warn(`Warning: Could not process ${fullPath}:`, error.message);
            continue;
        }
    }

    return files;
}

async function main() {
    const args = process.argv.slice(2) || [];
    let output = "";
    // Read each file's content and append to the output file with the filename as a comment
    async function mergeFiles(dir) {
        const files = await getFiles(dir);

        // Process each file
        for (const file of files)
            if (allowedExtensions.includes(extname(file))) {
                let content = "";
                try {
                    content = await readFile(file, "utf-8");
                } catch (err) {
                    console.error(`Error reading file ${file}:`, err);
                }
                const firstline = content.split("\n")[0];
                if (firstline.startsWith("// @encode skip")) content = firstline;
                if (firstline.startsWith("<!-- @encode skip")) content = firstline;
                output += `\n// FILE: ${file}\n`;
                output += `\n${content}\n`;
            }
    }

    // Start the process from the current directory
    if (args.length > 0) for (const dir of args) await mergeFiles(dir);
    else await mergeFiles(CWD);

    // Write the output to the output file
    try {
        await writeFile(outputFilePath, output, "utf-8");
        console.log(`All ${allowedExtensions.join(" ")} files merged into ${outputFilePath} ${args.join(' ')}` );
    } catch (err) {
        console.error(`Error writing to ${outputFilePath}:`, err);
    }
}
main();