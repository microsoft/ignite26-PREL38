"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..");
const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), "utf8");

const requiredInstructionFiles = [
  "instructions/README.md",
  "instructions/preconfigured-path.md",
  "instructions/configure-path.md",
  "instructions/simulator-and-reset.md",
  "instructions/screenshot-inventory.md"
];

test("attendee entry point requires exactly one path and links every path", () => {
  for (const file of requiredInstructionFiles) {
    assert.ok(fs.existsSync(path.join(repoRoot, file)), `${file} must exist`);
  }
  const entry = read("instructions/README.md");
  assert.match(entry, /Choose \*\*exactly one\*\* path/i);
  assert.match(entry, /\[Preconfigured Agent\]\(preconfigured-path\.md\)/);
  assert.match(entry, /\[Configure Agent\]\(configure-path\.md\)/);
  assert.match(entry, /\[Simulator and reset\]\(simulator-and-reset\.md\)/);
  assert.match(entry, /\[Screenshot inventory\]\(screenshot-inventory\.md\)/);
  assert.doesNotMatch(entry, /complete both|required.*both/i);
});

test("path timing, selection, one-scenario, recovery, and reset contracts are explicit", () => {
  const preconfigured = read("instructions/preconfigured-path.md");
  const configure = read("instructions/configure-path.md");
  const simulator = read("instructions/simulator-and-reset.md");

  assert.match(preconfigured, /25–30 minutes/);
  assert.match(configure, /50 minutes/);
  assert.match(preconfigured, /select \*\*Preconfigured\*\*/i);
  assert.match(configure, /select \*\*Configure\*\*/i);
  assert.match(preconfigured, /exactly one scenario/i);
  assert.match(configure, /Choose \*\*exactly one scenario\*\*/i);
  assert.match(preconfigured, /guided alert and response plan remain disabled/i);
  assert.match(configure, /alert → skill → custom agent → incident response plan/i);
  assert.match(simulator, /exactly one scenario/i);
  assert.match(simulator, /default.*Course recommendations are unavailable/is);
  assert.match(simulator, /No alert or automatic incident is expected/i);
  assert.match(simulator, /Azure Monitor evaluation interval \| 5 minutes/);
  assert.match(simulator, /5–10 minutes/);
  assert.match(simulator, /Cancel stops the running operation/);
  assert.match(simulator, /Open investigation in Azure SRE Agent/);
  assert.match(simulator, /Recovery verified/);
  assert.match(simulator, /Baseline restored/);
});

test("guided AFTER-state remains outside the initial bundle and disabled by default", () => {
  const configuration = read("data/agent/configuration.json");
  const catalog = JSON.parse(read("simulator/scenarios.json"));
  const guided = read("data/agent/guided-course-recommendations/README.md");
  const alert = read("data/agent/guided-course-recommendations/alert.bicep");
  const responsePlan = read("data/agent/guided-course-recommendations/incident-filter/course-recommendations-learning-response.yaml");
  const lifecycle = read("scripts/configure-guided-recommendations.mjs");
  assert.equal(catalog.defaultScenarioId, "course-recommendations-unavailable");
  assert.doesNotMatch(configuration, /course-recommendations-recovery|caldova-guided-feature-responder|course-recommendations-learning-response/);
  assert.match(guided, /does \*\*not\*\* apply them during initial lab preparation/i);
  assert.match(alert, /param enabled bool = false/);
  assert.match(responsePlan, /isEnabled: false/);
  assert.match(lifecycle, /\["apply", "enable", "disable", "verify"\]/);
  assert.match(lifecycle, /deleteConfigureArtifacts/);
  assert.match(lifecycle, /deleteConfigureResponsePlan/);
});

test("preconfigured path covers the completed operational reference", () => {
  const content = read("instructions/preconfigured-path.md");
  for (const phrase of [
    "exactly five weekly read-only tasks",
    "NSG, RBAC, cost, capacity, and CVE",
    "Caldova FinOps",
    "ActualCost → consumption → inventory/Retail Prices fallback",
    "Operations Overview",
    "Dependency Mapping",
    "Resource Explorer",
    "Log Analytics queries from the runtime can return 403",
    "Application Insights",
    "VM journal evidence"
  ]) {
    assert.match(content, new RegExp(phrase.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i"));
  }
});

test("cost and CVE tasks require validated downloadable audit decks", () => {
  const configuration = JSON.parse(read("data/agent/configuration.json"));
  const taskByName = new Map(configuration.scheduledTasks.map((task) => [task.name, task]));
  const sharedSkill = configuration.skills.find((skill) => skill.name === "caldova-audit-report");
  assert.ok(sharedSkill, "shared Caldova audit-report skill must be packaged");
  assert.equal(sharedSkill.scheduledTaskShared, true);
  assert.ok(fs.existsSync(path.join(repoRoot, "data/agent", sharedSkill.path)));

  for (const name of ["Caldova weekly cost review", "Caldova weekly CVE review"]) {
    const task = taskByName.get(name);
    assert.ok(task, `${name} must exist`);
    assert.match(task.message, /load .*caldova-audit-report/i);
    assert.match(task.message, /SaveFileToBlob/);
    assert.match(task.message, /\.pptx/);
    assert.match(task.message, /do not finish successfully unless/i);
    assert.match(task.message, /no Azure changes|Do not patch, rebuild, or redeploy/i);
  }

  const skill = read("data/agent/skills/caldova-audit-report/SKILL.md");
  assert.match(skill, /python-pptx/);
  assert.match(skill, /Office Open XML ZIP package/);
  assert.match(skill, /at least six slides/);
  assert.match(skill, /Unknown is never reported as zero, healthy, compliant, or clean/);
});

test("learner instructions do not reveal planted causes or require hosted source control", () => {
  const content = requiredInstructionFiles.map(read).join("\n").toLowerCase();
  const forbiddenCausePhrases = [
    "nsg rule priority",
    "broken probe path",
    "min replicas",
    "missing index",
    "nonexistent version",
    "fill the disk",
    "connection pool exhaustion"
  ];
  for (const phrase of forbiddenCausePhrases) {
    assert.equal(content.includes(phrase), false, `learner instructions expose planted cause '${phrase}'`);
  }
  for (const brand of ["pagerduty", "servicenow", "zava-learning"]) {
    assert.equal(content.includes(brand), false, `learner instructions include unsupported platform/brand '${brand}'`);
  }
  assert.doesNotMatch(content, /github\.com|git clone|git pull|pull request/);
});

test("Markdown relative links resolve", () => {
  const markdownFiles = [
    ...requiredInstructionFiles,
    "docs/README.md",
    "docs/architecture.md",
    "docs/facilitator-scenarios.md",
    "docs/lifecycle.md",
    "docs/skillable-hosting.md",
    "docs/troubleshooting.md",
    "data/agent/README.md"
  ];
  const linkPattern = /\[[^\]]+\]\((?!https?:|#|mailto:)([^)]+)\)/g;
  for (const relativePath of markdownFiles) {
    const content = read(relativePath);
    for (const match of content.matchAll(linkPattern)) {
      const target = match[1].split("#")[0].replace(/\\/g, "/");
      if (!target) continue;
      const resolved = path.resolve(path.dirname(path.join(repoRoot, relativePath)), decodeURIComponent(target));
      assert.ok(fs.existsSync(resolved), `${relativePath} has broken relative link '${match[1]}'`);
    }
  }
});

test("workstation scripts are offline, pinned, and separate attendee runtime from pre-run", () => {
  const check = read("scripts/check-workstation.ps1");
  const setup = read("scripts/setup-workstation.ps1");
  assert.match(check, /3\.0\.0-beta\.43/);
  assert.match(check, /1\.0\.43/);
  assert.match(check, /Node\.js 22/);
  assert.match(check, /PowerShell 7/);
  assert.match(check, /bicep/i);
  assert.match(setup, /ci --offline/);
  assert.match(setup, /ImageAuthoring/);
  assert.match(setup, /PreRun/);
  assert.match(setup, /CALDOVA_ATTENDEE_RUNTIME/);
  assert.doesNotMatch(setup, /npm\s+install|Invoke-WebRequest|curl|wget/i);
});

test("Skillable wrapper preserves lifecycle order and excludes reset and teardown", () => {
  const script = read("scripts/skillable-orchestrate.ps1");
  const stages = ["provision.ps1", "configure.ps1", "prepare.ps1", "readiness.ps1"];
  let previous = -1;
  for (const stage of stages) {
    const current = script.indexOf(stage);
    assert.ok(current > previous, `${stage} must appear in lifecycle order`);
    previous = current;
  }
  assert.doesNotMatch(script, /reset\.ps1|teardown\.ps1/);
  assert.match(script, /preconfiguredAgentPortalUrl/);
  assert.match(script, /configuredAgentPortalUrl/);
  assert.match(script, /127\.0\.0\.1:7070\/\?learnerNumber=/);
  assert.doesNotMatch(script, /CALDOVA_POSTGRES_ADMIN_PASSWORD|postgresPassword|ConvertTo-Json/);
});

test("simulator wrapper is attached, readiness checked, and learner-linked", () => {
  const script = read("scripts/start-simulator.ps1");
  const app = read("simulator/public/app.js");
  assert.match(script, /System\.Diagnostics\.Process/);
  assert.match(script, /WaitForExit/);
  assert.match(script, /api\/status\?learnerNumber=/);
  assert.match(script, /Kill\(\$true\)/);
  assert.doesNotMatch(script, /--no-window|nohup|Start-Job|detach/i);
  assert.match(app, /URLSearchParams\(window\.location\.search\)/);
  assert.match(app, /learnerNumber/);
});

test("new lab content has no unsupported placeholders or likely secrets", () => {
  const files = [
    ...requiredInstructionFiles,
    "docs/skillable-hosting.md",
    "docs/troubleshooting.md",
    "scripts/check-workstation.ps1",
    "scripts/setup-workstation.ps1",
    "scripts/skillable-orchestrate.ps1",
    "scripts/start-simulator.ps1"
  ];
  const content = files.map(read).join("\n");
  assert.doesNotMatch(content, /<subscription|<password|<token|YOUR_[A-Z_]+|REPLACE_ME|TBD/i);
  assert.doesNotMatch(content, /(?:password|token|secret)\s*[:=]\s*["'][^"'$]{8,}["']/i);
});
