"use strict";

const path = require("node:path");

const allowedAgents = new Set(["preconfigured", "configure"]);
const allowedActions = new Set(["check", "start", "verify", "fix", "reset"]);

function assertLearnerNumber(value) {
  const learnerNumber = Number(value);
  if (!Number.isInteger(learnerNumber) || learnerNumber < 1 || learnerNumber > 999) {
    throw new Error("Learner number must be a whole number from 1 to 999.");
  }
  return learnerNumber;
}

function buildScenarioCommand({ repoRoot, scenario, action, learnerNumber, targetAgent, platform = process.platform }) {
  if (!allowedActions.has(action)) throw new Error(`Unsupported simulator action '${action}'.`);
  if (!allowedAgents.has(targetAgent)) throw new Error("Target agent must be Preconfigured or Configure.");
  const normalizedLearner = assertLearnerNumber(learnerNumber);
  const scenarioReset = scenario.scripts?.reset?.match(/reset-(.+)\.ps1$/)?.[1];
  const relativeScript = action === "reset" ? "scripts/reset.ps1" : scenario.scripts?.[action];
  if (!relativeScript) throw new Error(`Scenario '${scenario.id}' does not define action '${action}'.`);
  if (action === "reset" && !scenarioReset) throw new Error(`Scenario '${scenario.id}' does not define a valid reset script.`);
  const scriptPath = path.resolve(repoRoot, relativeScript);
  const expectedRoot = `${path.resolve(repoRoot)}${path.sep}`;
  if (!scriptPath.startsWith(expectedRoot)) throw new Error("Scenario command resolved outside the repository.");

  const args = [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-File",
    scriptPath,
    "-LearnerNumber",
    String(normalizedLearner)
  ];
  if (action === "reset") {
    args.push("-Scenario", scenarioReset);
  } else {
    args.push("-TargetAgent", targetAgent);
  }
  if (action !== "reset" && Number.isFinite(scenario.probe?.impactedMedianMs)) {
    args.push("-ImpactedThresholdMs", String(scenario.probe.impactedMedianMs));
  }
  if (action !== "reset" && Number.isFinite(scenario.probe?.recoveredMedianMs)) {
    args.push("-RecoveredThresholdMs", String(scenario.probe.recoveredMedianMs));
  }

  return {
    executable: platform === "win32" ? "pwsh.exe" : "pwsh",
    args,
    display: action === "reset"
      ? `pwsh -NoProfile -File ${relativeScript} -LearnerNumber ${normalizedLearner} -Scenario ${scenarioReset}`
      : `pwsh -NoProfile -File ${relativeScript} -LearnerNumber ${normalizedLearner} -TargetAgent ${targetAgent}`
  };
}

module.exports = { buildScenarioCommand, assertLearnerNumber, allowedAgents, allowedActions };
