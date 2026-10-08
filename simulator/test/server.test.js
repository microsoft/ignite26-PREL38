"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { once } = require("node:events");
const { createSimulatorServer } = require("../server");
const { loadCatalog } = require("../lib/catalog");

async function waitForStatus(baseUrl, learnerNumber, expected) {
  const deadline = Date.now() + 4000;
  while (Date.now() < deadline) {
    const response = await fetch(`${baseUrl}/api/status?learnerNumber=${learnerNumber}`);
    const state = await response.json();
    if (state.status === expected) return state;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(`Timed out waiting for ${expected}`);
}

async function post(baseUrl, action, payload) {
  return fetch(`${baseUrl}/api/${action}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
}

async function withServer(options, action) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-server-"));
  const { server } = createSimulatorServer({ dataDirectory: directory, ...options });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  try {
    await action(baseUrl);
  } finally {
    server.close();
    await once(server, "close");
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

test("simulator serves UI and catalog through real HTTP", async () => {
  await withServer({ driverMode: "mock" }, async (baseUrl) => {
    const page = await fetch(`${baseUrl}/?learnerNumber=17`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /Caldova incident simulator/);
    const status = await fetch(`${baseUrl}/api/status?learnerNumber=17`);
    assert.equal(status.status, 200);
    assert.equal((await status.json()).learnerNumber, 17);
    const catalog = await fetch(`${baseUrl}/api/catalog`);
    assert.equal(catalog.status, 200);
    assert.equal((await catalog.json()).scenarios.length, 8);
  });
});

for (const [index, scenario] of loadCatalog().scenarios.entries()) {
  test(`${scenario.id} enforces check, lock, start, and reset through real HTTP`, async () => {
    await withServer({ driverMode: "mock" }, async (baseUrl) => {
      const learnerNumber = 40 + index;
      const payload = { learnerNumber, targetAgent: "preconfigured", scenarioId: scenario.id };

      const blocked = await post(baseUrl, "start", payload);
      assert.equal(blocked.status, 409);
      assert.match((await blocked.json()).error, /Check configuration/);

      assert.equal((await post(baseUrl, "check", payload)).status, 202);
      const ready = await waitForStatus(baseUrl, learnerNumber, "ready");
      assert.equal(ready.ready, true);
      assert.match(ready.investigationUrl, /^https:/);

      const start = await post(baseUrl, "start", payload);
      assert.equal(start.status, 202);
      const duplicate = await post(baseUrl, "start", payload);
      assert.equal(duplicate.status, 409);
      assert.match((await duplicate.json()).error, /already running/);

      const investigating = await waitForStatus(baseUrl, learnerNumber, "investigating");
      assert.equal(investigating.active, true);
      assert.equal(investigating.result.scenarioId, scenario.id);
      assert.match(investigating.result.alertId, new RegExp(scenario.id));

      const verify = await post(baseUrl, "verify", payload);
      assert.equal(verify.status, 202);
      const stillImpacted = await waitForStatus(baseUrl, learnerNumber, "investigating");
      assert.equal(stillImpacted.result.recovered, false);

      const fix = await post(baseUrl, "fix", payload);
      assert.equal(fix.status, 202);
      const recovered = await waitForStatus(baseUrl, learnerNumber, "recovered");
      assert.equal(recovered.result.recovered, true);

      const reset = await post(baseUrl, "reset", payload);
      assert.equal(reset.status, 202);
      const idle = await waitForStatus(baseUrl, learnerNumber, "idle");
      assert.equal(idle.ready, false);
      assert.equal(idle.active, false);
      assert.equal(idle.scenarioId, null);
      assert.equal(idle.targetAgent, null);
    });
  });
}

test("failed precondition is returned as actionable state through real HTTP", async () => {
  const driver = {
    async run({ action }) {
      if (action === "check") {
        throw new Error("The learner-visible quiz path is not healthy before the exercise (HTTP 503). Run Reset or restore the baseline before starting; no scenario change was made.");
      }
      return {};
    }
  };
  await withServer({ driver }, async (baseUrl) => {
    const payload = { learnerNumber: 66, targetAgent: "configure", scenarioId: "quiz-launch-scenario-2" };
    assert.equal((await post(baseUrl, "check", payload)).status, 202);
    const state = await waitForStatus(baseUrl, 66, "error");
    assert.match(state.error, /HTTP 503/);
    assert.match(state.error, /Run Reset/);
    const blocked = await post(baseUrl, "start", payload);
    assert.equal(blocked.status, 409);
  });
});

test("mismatched verify, fix, and reset return 409 without altering active state", async () => {
  await withServer({ driverMode: "mock" }, async (baseUrl) => {
    const learnerNumber = 88;
    const active = { learnerNumber, targetAgent: "preconfigured", scenarioId: "quiz-launch-scenario-1" };
    assert.equal((await post(baseUrl, "check", active)).status, 202);
    await waitForStatus(baseUrl, learnerNumber, "ready");
    assert.equal((await post(baseUrl, "start", active)).status, 202);
    const investigating = await waitForStatus(baseUrl, learnerNumber, "investigating");

    const mismatches = [
      ["verify", { ...active, scenarioId: "quiz-launch-scenario-2" }],
      ["fix", { ...active, targetAgent: "configure" }],
      ["reset", { ...active, scenarioId: "quiz-launch-scenario-3", targetAgent: "configure" }]
    ];
    for (const [action, payload] of mismatches) {
      const response = await post(baseUrl, action, payload);
      assert.equal(response.status, 409, `${action} must reject a mismatched active selection`);
      assert.match((await response.json()).error, /does not match the active learner exercise/);
      const current = await (await fetch(`${baseUrl}/api/status?learnerNumber=${learnerNumber}`)).json();
      assert.equal(current.status, "investigating");
      assert.equal(current.scenarioId, investigating.scenarioId);
      assert.equal(current.targetAgent, investigating.targetAgent);
      assert.deepEqual(current.result, investigating.result);
    }
  });
});
