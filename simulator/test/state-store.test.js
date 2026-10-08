"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { fork } = require("node:child_process");
const { once } = require("node:events");
const { StateStore } = require("../lib/state-store");

test("state transitions preserve readiness and reject invalid jumps", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-state-"));
  const store = new StateStore(directory);
  store.transition(7, "checking", { phase: "Checking" });
  const ready = store.transition(7, "ready", { ready: true, targetAgent: "preconfigured", scenarioId: "api-quiz-latency" });
  assert.equal(ready.ready, true);
  assert.throws(() => store.transition(7, "recovered"), /Invalid simulator transition/);
  fs.rmSync(directory, { recursive: true, force: true });
});

test("per-learner lock prevents concurrent scenario actions", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-lock-"));
  const store = new StateStore(directory);
  const release = store.acquire(8, "start");
  assert.throws(() => store.acquire(8, "reset"), /already owns learner 8/);
  release();
  const releaseAgain = store.acquire(8, "reset");
  releaseAgain();
  fs.rmSync(directory, { recursive: true, force: true });
});

test("expired malformed lock is recovered but a fresh malformed lock is actionable", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-lock-malformed-"));
  const store = new StateStore(directory, { staleLockMs: 1000 });
  const file = store.lockPath(9);
  fs.writeFileSync(file, "{not-json");
  assert.throws(() => store.acquire(9, "reset"), /malformed but only/);
  const expired = new Date(Date.now() - 5000);
  fs.utimesSync(file, expired, expired);
  const release = store.acquire(9, "reset");
  release();
  fs.rmSync(directory, { recursive: true, force: true });
});

test("dead owner lock is recovered after a simulator restart", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-lock-dead-"));
  const file = path.join(directory, "simulator-lock-user10.json");
  fs.writeFileSync(file, JSON.stringify({
    schemaVersion: 1,
    learnerNumber: 10,
    action: "start",
    pid: 2147483647,
    token: "dead-owner",
    acquiredAt: new Date().toISOString()
  }));
  const store = new StateStore(directory, { isProcessAlive: () => false });
  const release = store.acquire(10, "reset");
  assert.equal(JSON.parse(fs.readFileSync(file, "utf8")).pid, process.pid);
  release();
  fs.rmSync(directory, { recursive: true, force: true });
});

test("live process lock survives competing acquire and owner restart boundary", async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-lock-live-"));
  const helper = path.join(directory, "lock-owner.cjs");
  fs.writeFileSync(helper, `
    const { StateStore } = require(${JSON.stringify(path.resolve(__dirname, "../lib/state-store.js"))});
    const store = new StateStore(process.argv[2]);
    store.acquire(11, "start");
    if (process.send) process.send("ready");
    setInterval(() => {}, 1000);
  `);
  const child = fork(helper, [directory], { stdio: ["ignore", "ignore", "ignore", "ipc"] });
  await once(child, "message");
  const store = new StateStore(directory, { staleLockMs: 1 });
  const file = store.lockPath(11);
  const before = fs.readFileSync(file, "utf8");
  assert.throws(() => store.acquire(11, "reset"), new RegExp(`live process ${child.pid}`));
  assert.equal(fs.readFileSync(file, "utf8"), before);
  child.kill();
  await once(child, "exit");
  const restarted = new StateStore(directory);
  const release = restarted.acquire(11, "reset");
  release();
  fs.rmSync(directory, { recursive: true, force: true });
});
