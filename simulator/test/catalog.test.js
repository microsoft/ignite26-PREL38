"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { loadCatalog } = require("../lib/catalog");

test("scenario catalog is complete and learner text remains symptom-only", () => {
  const catalog = loadCatalog();
  assert.equal(catalog.scenarios.length, 8);
  const forbidden = [
    "nsg", "network rule", "probe", "gateway setting", "revision", "replica",
    "replicas", "container", "scale", "root cause", "bad build", "rollback",
    "database", "index", "pool", "secret", "key vault", "disk", "vm", "storage", "cause"
  ];
  for (const scenario of catalog.scenarios) {
    assert.match(scenario.id, /^[a-z0-9-]+$/);
    for (const action of ["check", "start", "verify", "fix", "reset"]) {
      const script = path.resolve(__dirname, "..", "..", scenario.scripts[action]);
      assert.ok(fs.existsSync(script), `${scenario.id} ${action} script must exist`);
    }
    const learnerText = Object.values(scenario.learner).join(" ").toLowerCase();
    for (const term of forbidden) {
      assert.equal(learnerText.includes(term), false, `${scenario.id} learner text exposes '${term}'`);
    }
  }
  const quizLaunchAlerts = catalog.scenarios
    .filter((scenario) => scenario.id.startsWith("quiz-launch-scenario-") || scenario.id.includes("failures"))
    .map((scenario) => scenario.alert.name);
  assert.equal(new Set(quizLaunchAlerts).size, 1, "quiz-launch choices must share one symptom alert");
  assert.notEqual(quizLaunchAlerts[0], catalog.scenarios[0].alert.name);
  assert.equal(getAlert("quiz-search-slow"), "Caldova-quiz-response-time-elevated");
  assert.equal(getAlert("reporting-output-missing"), "Caldova-reporting-output-missing");

  function getAlert(id) {
    return catalog.scenarios.find((scenario) => scenario.id === id).alert.name;
  }
});
