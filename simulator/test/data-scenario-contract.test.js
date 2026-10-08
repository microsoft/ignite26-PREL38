"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const modulePath = path.resolve(__dirname, "..", "..", "scripts", "scenarios", "Caldova.DataScenarios.psm1");
const source = fs.readFileSync(modulePath, "utf8");

test("Azure commands are bounded and use private execution paths", () => {
  assert.match(source, /containerapp', 'exec'/);
  assert.match(source, /Requests = 12/);
  assert.match(source, /POSTGRES_POOL_MAX=1/);
  assert.match(source, /POSTGRES_CONNECT_TIMEOUT_MS=250/);
  assert.match(source, /CALDOVA_DB_HOLD_MS=1500/);
  assert.doesNotMatch(source, /network.*postgres.*public/i);
});

test("credential scenario stores references but never retrieves or prints values", () => {
  assert.match(source, /keyVaultUrl/);
  assert.match(source, /identityref:/);
  assert.doesNotMatch(source, /secret\s+show/);
  assert.doesNotMatch(source, /postgresPassword\s*=/);
});

test("reporting scenario owns one named filler on the dedicated mount", () => {
  assert.match(source, /\/var\/lib\/caldova\/\.caldova-reporting-output-missing\.filler/);
  assert.match(source, /mountpoint -q \/var\/lib\/caldova/);
  assert.match(source, /rm -f --/);
  assert.doesNotMatch(source, /\/var\/lib\/caldova\/\*/);
});
