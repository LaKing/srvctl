// Regression coverage for the public containers snapshot served to peer
// hosts. Run with: node modules/datastore/selftest/datastore-server.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const {
  DATASTORE_PATH,
  createHttpServer,
  readContainersSnapshot,
} = require(path.join(HERE, "../apps/datastore-server.js"));

let passed = 0;
const failures = [];

async function test(name, fn) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sc-datastore-server-"));
  try {
    await fn(tmp);
    passed++;
    console.log(`  ok  ${name}`);
  } catch (err) {
    failures.push({ name, err });
    console.log(`FAIL  ${name}\n      ${err.stack || err}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
}

function request(server, requestPath) {
  return new Promise((resolve, reject) => {
    const req = http.get({
      host: "127.0.0.1",
      port: server.address().port,
      path: requestPath,
    }, (res) => {
      let body = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => { body += chunk; });
      res.on("end", () => resolve({
        statusCode: res.statusCode,
        contentType: res.headers["content-type"],
        body,
      }));
    });
    req.on("error", reject);
  });
}

await test("pre-migration snapshot merges monolithic and per-entity records", async (dir) => {
  writeJson(path.join(dir, "containers.json"), {
    "legacy.example": { ip: "192.0.2.1" },
    "mindtalk.hu": { override_in_a_ip: "195.228.45.188" },
  });
  writeJson(path.join(dir, "containers/mindtalk.hu.json"), {
    override_in_a_ip: "38.242.131.65",
  });

  assert.deepEqual(JSON.parse(await readContainersSnapshot(dir)), {
    "legacy.example": { ip: "192.0.2.1" },
    "mindtalk.hu": { override_in_a_ip: "38.242.131.65" },
  });
});

await test("HTTP snapshot honors .per-entity and ignores a stale monolith", async (dir) => {
  writeJson(path.join(dir, "containers.json"), {
    "deleted.example": { ip: "192.0.2.2" },
    "mindtalk.hu": { override_in_a_ip: "195.228.45.188" },
  });
  writeJson(path.join(dir, "containers/mindtalk.hu.json"), {
    override_in_a_ip: "38.242.131.65",
  });
  fs.writeFileSync(path.join(dir, ".per-entity"), "");

  const server = createHttpServer({ datastoreDir: dir });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  try {
    const response = await request(server, DATASTORE_PATH);
    assert.equal(response.statusCode, 200);
    assert.equal(response.contentType, "application/json");
    assert.equal(response.body.endsWith("\n"), true);
    assert.deepEqual(JSON.parse(response.body), {
      "mindtalk.hu": { override_in_a_ip: "38.242.131.65" },
    });

    // The daemon is long-running: every request must observe fresh entity
    // files rather than a containers map cached when the module was loaded.
    writeJson(path.join(dir, "containers/mindtalk.hu.json"), {
      override_in_a_ip: "203.0.113.65",
    });
    const refreshed = await request(server, DATASTORE_PATH);
    assert.deepEqual(JSON.parse(refreshed.body), {
      "mindtalk.hu": { override_in_a_ip: "203.0.113.65" },
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

await test("HTTP snapshot fails visibly instead of returning invalid JSON as 200", async (dir) => {
  fs.mkdirSync(path.join(dir, "containers"), { recursive: true });
  fs.writeFileSync(path.join(dir, "containers/broken.example.json"), "{not-json\n");
  fs.writeFileSync(path.join(dir, ".per-entity"), "");

  const server = createHttpServer({ datastoreDir: dir });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  try {
    const response = await request(server, DATASTORE_PATH);
    assert.equal(response.statusCode, 500);
    assert.equal(response.contentType, "application/json");
    assert.deepEqual(JSON.parse(response.body), { error: "INVALID DATA" });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
