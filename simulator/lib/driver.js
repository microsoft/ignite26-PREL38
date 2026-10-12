"use strict";

const { spawn } = require("node:child_process");
const { buildScenarioCommand } = require("./commands");

const phasePattern = /^::phase::([^:]+)::(\d+)::(.+)$/;

function delay(ms, signal) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => {
      clearTimeout(timer);
      reject(new Error("Operation cancelled. Run Reset before starting another scenario."));
    }, { once: true });
  });
}

class MockDriver {
  async run({ action, targetAgent, scenario, onPhase, signal }) {
    const isLatency = scenario.id === "api-quiz-latency" || scenario.kind === "latency";
    const isReporting = scenario.kind === "reporting";
    const isIntermittent = scenario.id === "quiz-intermittent-failures";
    const isGuidedManual = scenario.kind === "guided-manual";
    const phases = {
      check: isGuidedManual
        ? [["Checking core health and the isolated guided feature", 35], ["Confirming no automated incident is configured", 80]]
        : [["Checking learner deployment and selected response plan", 35], ["Confirming alert ownership requirements", 80]],
      start: isGuidedManual
        ? [["Recording the guided-feature state", 25], ["Activating the isolated symptom", 55], ["Generating App Insights evidence", 82]]
        : [["Assigning the live alert to the selected agent", 18], ["Activating the selected exercise", 40], ["Verifying learner-visible impact", 58], ["Generating controlled learner traffic", 72], ["Waiting for the one-minute monitor", 88]],
      verify: [["Checking learner-visible recovery", 65], ["Confirming service health", 85]],
      fix: [["Restoring the saved baseline", 55], ["Verifying recovery", 85]],
      reset: [["Restoring the saved baseline", 45], ["Restoring response-plan ownership", 78], ["Clearing scenario state", 92]]
    };
    for (const [message, progress] of phases[action] || []) {
      onPhase({ message, progress });
      await delay(20, signal);
    }
    if (action === "check") {
      return {
        ready: true,
        agentName: `sre-caldova-${targetAgent}`,
        investigationUrl: `https://sre.azure.com/agents/${targetAgent}`,
        alertConfigured: !isGuidedManual,
        alertExpected: !isGuidedManual
      };
    }
    if (action === "start") {
      if (isGuidedManual) {
        return {
          changed: true,
          phase: "investigate",
          scenarioId: scenario.id,
          impact: { publicStatus: 503, featureStatus: "degraded" },
          traffic: { requests: 12, marker: "mock-course-recommendations" },
          alertExpected: false,
          alertId: null,
          investigationUrl: `https://sre.azure.com/agents/${targetAgent}`
        };
      }
      return {
        changed: true,
        phase: "investigate",
        scenarioId: scenario.id,
        impact: isLatency
          ? { medianMs: 1262 }
          : isReporting
            ? { recentExport: false, heartbeat: false }
            : { publicStatus: isIntermittent ? 503 : 502, successes: isIntermittent ? 6 : 0, failures: isIntermittent ? 6 : 12 },
        latency: isLatency ? { medianMs: 1262 } : undefined,
        trafficRequests: isLatency ? 58 : 12,
        alertId: `mock-alert-${scenario.id}`,
        investigationUrl: `https://sre.azure.com/agents/${targetAgent}`
      };
    }
    if (action === "verify") {
      if (isGuidedManual) return { recovered: false, feature: { status: 503, featureStatus: "degraded" } };
      return isLatency
        ? { recovered: false, latency: { medianMs: 1258 } }
        : isReporting
          ? { recovered: false, recentExport: false, heartbeat: false }
          : { recovered: false, publicStatus: 503 };
    }
    if (action === "fix") {
      if (isGuidedManual) return { recovered: true, feature: { status: 200, featureStatus: "available" } };
      if (isLatency) return { recovered: true, latency: { medianMs: 24 } };
      if (isReporting) return { recovered: true, recentExport: true, heartbeat: true };
      return { recovered: true, publicStatus: 200 };
    }
    if (isGuidedManual) return { reset: true, recovered: true, feature: { status: 200, featureStatus: "available" } };
    if (isLatency) return { reset: true, latency: { medianMs: 21 } };
    if (isReporting) return { reset: true, recentExport: true, heartbeat: true };
    return { reset: true, publicStatus: 200 };
  }
}

class PowerShellDriver {
  constructor(repoRoot) {
    this.repoRoot = repoRoot;
  }

  async run({ scenario, action, learnerNumber, targetAgent, onPhase, signal }) {
    if (action !== "check" &&
        (process.env.CALDOVA_AZURE_MUTATION_ENABLED !== "YES" || process.env.CALDOVA_AZURE_TARGET !== "skillable")) {
      throw new Error("Azure scenario changes are disabled. On the Skillable workstation set CALDOVA_AZURE_MUTATION_ENABLED=YES and CALDOVA_AZURE_TARGET=skillable, then retry. No Azure change was attempted.");
    }
    const command = buildScenarioCommand({
      repoRoot: this.repoRoot,
      scenario,
      action,
      learnerNumber,
      targetAgent
    });
    return new Promise((resolve, reject) => {
      const child = spawn(command.executable, command.args, {
        cwd: this.repoRoot,
        windowsHide: true,
        env: process.env
      });
      let stdout = "";
      let stderr = "";
      const consume = (chunk, isError) => {
        const text = chunk.toString();
        if (isError) stderr += text;
        else stdout += text;
        for (const line of text.split(/\r?\n/)) {
          const match = line.match(phasePattern);
          if (match) onPhase({ key: match[1], progress: Number(match[2]), message: match[3] });
        }
      };
      child.stdout.on("data", (chunk) => consume(chunk, false));
      child.stderr.on("data", (chunk) => consume(chunk, true));
      signal?.addEventListener("abort", () => child.kill(), { once: true });
      child.on("error", (error) => reject(new Error(`Could not start PowerShell: ${error.message}. Install PowerShell 7 and retry.`)));
      child.on("exit", (code) => {
        if (code !== 0) {
          const detail = `${stderr}\n${stdout}`.replace(/^::phase::.*$/gm, "").trim();
          reject(new Error(detail || `${command.display} failed with exit code ${code}. Run Reset before retrying.`));
          return;
        }
        const jsonLine = stdout.split(/\r?\n/).reverse().find((line) => line.trim().startsWith("{"));
        if (!jsonLine) {
          reject(new Error(`Scenario command completed without a result. Command: ${command.display}`));
          return;
        }
        try {
          resolve(JSON.parse(jsonLine));
        } catch (error) {
          reject(new Error(`Scenario returned invalid JSON: ${error.message}`));
        }
      });
    });
  }
}

function createDriver(repoRoot, mode = process.env.SIMULATOR_DRIVER || "azure") {
  return mode === "mock" ? new MockDriver() : new PowerShellDriver(repoRoot);
}

module.exports = { MockDriver, PowerShellDriver, createDriver, phasePattern };
