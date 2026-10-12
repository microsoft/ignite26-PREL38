"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const path = require("node:path");
const {
  AVAILABLE,
  UNAVAILABLE,
  getRecommendationsHealth,
  getRecommendationsMode
} = require("../lib/recommendations");

const apiRoot = path.resolve(__dirname, "..");

async function startApi(mode) {
  const port = 20000 + Math.floor(Math.random() * 1000);
  const child = spawn(process.execPath, ["server.js"], {
    cwd: apiRoot,
    env: {
      ...process.env,
      NODE_ENV: "test",
      CALDOVA_DATA_MODE: "memory",
      CALDOVA_RECOMMENDATIONS_MODE: mode,
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

async function stopApi(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGKILL");
  await new Promise((resolve) => child.once("exit", resolve));
}

test("recommendations mode has a safe prepared default", () => {
  assert.equal(getRecommendationsMode(undefined), UNAVAILABLE);
  assert.equal(getRecommendationsMode(" AVAILABLE "), AVAILABLE);
  assert.equal(getRecommendationsMode("unexpected"), UNAVAILABLE);
  assert.equal(getRecommendationsHealth(UNAVAILABLE).statusCode, 503);
  assert.equal(getRecommendationsHealth(AVAILABLE).statusCode, 200);
});

for (const [mode, expectedStatus, expectedFeatureStatus] of [
  [UNAVAILABLE, 503, "degraded"],
  [AVAILABLE, 200, "available"]
]) {
  test(`recommendations endpoint is ${expectedFeatureStatus} while core health remains ready`, async () => {
    const api = await startApi(mode);
    try {
      const [health, ready, courses, recommendations] = await Promise.all([
        fetch(`${api.baseUrl}/health`),
        fetch(`${api.baseUrl}/ready`),
        fetch(`${api.baseUrl}/courses`),
        fetch(`${api.baseUrl}/recommendations/health`)
      ]);
      assert.equal(health.status, 200);
      assert.equal(ready.status, 200);
      assert.equal(courses.status, 200);
      assert.equal(recommendations.status, expectedStatus);
      const body = await recommendations.json();
      assert.equal(body.feature, "course_recommendations");
      assert.equal(body.status, expectedFeatureStatus);
      assert.match(body.message, /Courses and assessments remain available|recommendations are available/);
    } finally {
      await stopApi(api.child);
    }
  });
}
