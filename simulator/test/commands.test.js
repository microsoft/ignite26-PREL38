"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { getScenario } = require("../lib/catalog");
const { buildScenarioCommand } = require("../lib/commands");

test("PowerShell command construction uses explicit validated arguments", () => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  const command = buildScenarioCommand({
    repoRoot,
    scenario: getScenario("api-quiz-latency"),
    action: "start",
    learnerNumber: 12,
    targetAgent: "configure",
    platform: "win32"
  });
  assert.equal(command.executable, "pwsh.exe");
  assert.deepEqual(command.args.slice(-8), [
    "-LearnerNumber", "12",
    "-TargetAgent", "configure",
    "-ImpactedThresholdMs", "900",
    "-RecoveredThresholdMs", "600"
  ]);
  assert.match(command.args[4], /break-api-latency\.ps1$/);
  assert.throws(() => buildScenarioCommand({
    repoRoot,
    scenario: getScenario("api-quiz-latency"),
    action: "start",
    learnerNumber: "1; Remove-Item",
    targetAgent: "configure"
  }), /Learner number/);
});

test("availability scenario commands omit latency-only arguments", () => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  for (const id of [
    "quiz-launch-scenario-1", "quiz-launch-scenario-2", "quiz-launch-scenario-3",
    "quiz-intermittent-failures", "quiz-consistent-failures", "reporting-output-missing",
    "course-recommendations-unavailable"
  ]) {
    const command = buildScenarioCommand({
      repoRoot,
      scenario: getScenario(id),
      action: "start",
      learnerNumber: 31,
      targetAgent: "preconfigured",
      platform: "linux"
    });
    assert.equal(command.executable, "pwsh");
    assert.deepEqual(command.args.slice(-4), ["-LearnerNumber", "31", "-TargetAgent", "preconfigured"]);
    assert.equal(command.args.includes("-ImpactedThresholdMs"), false);
    assert.match(command.args[4], new RegExp(`break-${id}\\.ps1$`));
  }
});

test("index-sensitive scenario reuses latency thresholds and exact scripts", () => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  const command = buildScenarioCommand({
    repoRoot,
    scenario: getScenario("quiz-search-slow"),
    action: "fix",
    learnerNumber: 32,
    targetAgent: "configure",
    platform: "win32"
  });
  assert.match(command.args[4], /fix-quiz-search-slow\.ps1$/);
  assert.deepEqual(command.args.slice(-8), [
    "-LearnerNumber", "32",
    "-TargetAgent", "configure",
    "-ImpactedThresholdMs", "900",
    "-RecoveredThresholdMs", "600"
  ]);
});

test("reset routes through aggregate reset and requires scenario readiness", () => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  for (const [id, expectedScenario] of [
    ["api-quiz-latency", "api-latency"],
    ["quiz-launch-scenario-1", "quiz-launch-scenario-1"],
    ["quiz-search-slow", "quiz-search-slow"],
    ["reporting-output-missing", "reporting-output-missing"],
    ["course-recommendations-unavailable", "course-recommendations-unavailable"]
  ]) {
    const command = buildScenarioCommand({
      repoRoot,
      scenario: getScenario(id),
      action: "reset",
      learnerNumber: 44,
      targetAgent: "configure",
      platform: "win32"
    });
    assert.match(command.args[4], /scripts[\\/]reset\.ps1$/);
    assert.deepEqual(command.args.slice(-4), ["-LearnerNumber", "44", "-Scenario", expectedScenario]);
    assert.equal(command.args.includes("-TargetAgent"), false);
    assert.match(command.display, new RegExp(`-Scenario ${expectedScenario}$`));
  }
});
