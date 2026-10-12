"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const modulePath = path.resolve(__dirname, "..", "..", "scripts", "scenarios", "Caldova.DataScenarios.psm1");
const source = fs.readFileSync(modulePath, "utf8");
const workerSource = fs.readFileSync(
  path.resolve(__dirname, "..", "..", "src", "reporting-worker", "cloud-init.yaml"),
  "utf8",
);
const reportingAlertSource = fs.readFileSync(
  path.resolve(__dirname, "..", "..", "infra", "modules", "reporting-alert.bicep"),
  "utf8",
);

test("Azure commands are bounded and use private execution paths", () => {
  assert.match(source, /containerapp', 'exec'/);
  assert.match(source, /Requests = 12/);
  assert.match(source, /POSTGRES_POOL_MAX=1/);
  assert.match(source, /POSTGRES_CONNECT_TIMEOUT_MS=250/);
  assert.match(source, /CALDOVA_DB_HOLD_MS=1500/);
  assert.match(source, /pressurePrewarm=/);
  assert.match(source, /"\$\{Uri\}\?pressure=\$Attempt"/);
  assert.doesNotMatch(source, /network.*postgres.*public/i);
});

test("consistent-failure scenario changes only the non-secret quiz availability setting", () => {
  assert.match(source, /CALDOVA_QUIZ_MODE=unavailable/);
  assert.match(source, /quiz-availability-setting/);
  assert.doesNotMatch(source, /containerapp', 'secret', 'set'/);
  assert.doesNotMatch(source, /secret\s+show/);
  assert.doesNotMatch(source, /postgresPassword\s*=/);
});

test("reporting scenario owns one named filler on the dedicated mount", () => {
  assert.match(source, /\/var\/lib\/caldova\/\.caldova-reporting-output-missing\.filler/);
  assert.match(source, /mountpoint -q \/var\/lib\/caldova/);
  assert.match(source, /journalctl -t caldova-reporting.*status=FAILED/);
  assert.match(source, /rm -f --/);
  assert.match(source, /tune2fs -m 0/);
  assert.match(source, /tune2fs -m 5/);
  assert.doesNotMatch(source, /\/var\/lib\/caldova\/\*/);
  assert.match(workerSource, /row_count.*-lt 0/);
  assert.match(workerSource, /reason=empty_export_output/);
  assert.match(reportingAlertSource, /LastFailure > LastSuccess/);
  assert.doesNotMatch(reportingAlertSource, /FailureCount > 0 or isnull\(LastSuccess\)/);
  assert.match(source, /reporting worker is not verified recovered; refusing to recycle/i);
  assert.match(source, /A reporting alert is open; refusing to recycle/i);
  assert.match(source, /scheduled-query', 'delete'/);
  assert.match(source, /reporting-alert\.bicep/);
});
