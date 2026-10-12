"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const { once } = require("node:events");
const { spawn } = require("node:child_process");
const path = require("node:path");

const portalRoot = path.resolve(__dirname, "..");

async function withPortal(action) {
  const upstream = http.createServer((request, response) => {
    if (request.url.startsWith("/recommendations/health")) {
      response.writeHead(503, { "content-type": "application/json" });
      response.end(JSON.stringify({
        status: "degraded",
        feature: "course_recommendations",
        message: "Course recommendations are temporarily unavailable. Courses and assessments remain available."
      }));
      return;
    }
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({ status: "ready" }));
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");

  const port = 21000 + Math.floor(Math.random() * 1000);
  const child = spawn(process.execPath, ["server.js"], {
    cwd: portalRoot,
    env: {
      ...process.env,
      NODE_ENV: "test",
      APPLICATIONINSIGHTS_CONNECTION_STRING: "",
      CALDOVA_API_BASE_URL: `http://127.0.0.1:${upstream.address().port}`,
      PORT: String(port)
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", (chunk) => { output += chunk.toString(); });
  child.stderr.on("data", (chunk) => { output += chunk.toString(); });
  const deadline = Date.now() + 15000;
  while (!output.includes("caldova_service_started")) {
    if (child.exitCode !== null) throw new Error(`Portal exited before startup:\n${output}`);
    if (Date.now() > deadline) throw new Error(`Portal startup timed out:\n${output}`);
    await new Promise((resolve) => setTimeout(resolve, 25));
  }

  try {
    await action(`http://127.0.0.1:${port}`);
  } finally {
    if (child.exitCode === null) {
      child.kill("SIGKILL");
      await once(child, "exit");
    }
    upstream.close();
    await once(upstream, "close");
  }
}

test("portal keeps the recommendations symptom isolated from core health", async () => {
  await withPortal(async (baseUrl) => {
    const [health, ready, feature, page] = await Promise.all([
      fetch(`${baseUrl}/health`),
      fetch(`${baseUrl}/ready`),
      fetch(`${baseUrl}/api/recommendations/health`),
      fetch(baseUrl)
    ]);
    assert.equal(health.status, 200);
    assert.equal(ready.status, 200);
    assert.equal(feature.status, 503);
    assert.equal((await feature.json()).feature, "course_recommendations");
    const html = await page.text();
    assert.match(html, /Course recommendations/);
    assert.match(html, /recommendations-retry/);
    assert.match(html, /loadRecommendations/);
  });
});
