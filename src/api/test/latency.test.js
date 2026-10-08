"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const path = require("node:path");

const apiRoot = path.resolve(__dirname, "..");

async function startApi(profile) {
  const port = 19000 + Math.floor(Math.random() * 1000);
  const child = spawn(process.execPath, ["server.js"], {
    cwd: apiRoot,
    env: {
      ...process.env,
      NODE_ENV: "test",
      CALDOVA_DATA_MODE: "memory",
      CALDOVA_TEST_LATENCY_PROFILE: profile,
      PORT: String(port)
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", (chunk) => { output += chunk.toString(); });
  child.stderr.on("data", (chunk) => { output += chunk.toString(); });

  const deadline = Date.now() + 15000;
  while (!output.includes("caldova_service_started")) {
    if (child.exitCode !== null) throw new Error(`API exited before startup:\n${output}`);
    if (Date.now() > deadline) {
      child.kill("SIGKILL");
      throw new Error(`API startup timed out:\n${output}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  return { child, baseUrl: `http://127.0.0.1:${port}` };
}

async function timedGet(url) {
  const started = performance.now();
  const response = await fetch(url);
  const body = await response.json();
  return { status: response.status, body, elapsedMs: performance.now() - started };
}

async function stopApi(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGKILL");
  await new Promise((resolve) => child.once("exit", resolve));
}

test("healthy and latency images preserve health while separating quiz response times", async () => {
  const healthy = await startApi("healthy");
  try {
    const health = await timedGet(`${healthy.baseUrl}/health`);
    const quiz = await timedGet(`${healthy.baseUrl}/quiz/OPS-201-M1`);
    assert.equal(health.status, 200);
    assert.equal(quiz.status, 200);
    assert.ok(quiz.elapsedMs < 400, `healthy quiz was ${quiz.elapsedMs.toFixed(1)} ms`);
  } finally {
    await stopApi(healthy.child);
  }

  const bad = await startApi("bad");
  try {
    const health = await timedGet(`${bad.baseUrl}/health`);
    const quiz = await timedGet(`${bad.baseUrl}/quiz/OPS-201-M1`);
    assert.equal(health.status, 200);
    assert.equal(quiz.status, 200);
    assert.ok(health.elapsedMs < 400, `bad-image health was ${health.elapsedMs.toFixed(1)} ms`);
    assert.ok(quiz.elapsedMs >= 1150, `bad-image quiz was ${quiz.elapsedMs.toFixed(1)} ms`);
  } finally {
    await stopApi(bad.child);
  }
});
