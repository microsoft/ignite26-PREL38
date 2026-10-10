import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { configureAzureMcp } from "./configure-azure-mcp.mjs";
import { configurePreconfiguredGitHub } from "./configure-github.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(__dirname, "..");
const apiVersion = "2025-05-01-preview";
const requiredAzmcpVersion = "3.0.0-beta.43";

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const result = { mode: "apply" };
  const args = [...argv];
  if (args[0] === "check" || args[0] === "apply") result.mode = args.shift();
  while (args.length > 0) {
    const key = args.shift();
    if (!key.startsWith("--") || args.length === 0) fail(`Invalid argument '${key}'.`);
    result[key.slice(2)] = args.shift();
  }
  for (const key of ["subscription", "resource-group", "preconfigured-agent", "configure-agent", "bundle", "repository"]) {
    if (!result[key]) fail(`Missing --${key}.`);
  }
  return result;
}

function findExecutable(name, remediation, envName) {
  const override = envName ? process.env[envName] : "";
  if (override) {
    if (!fs.existsSync(override)) fail(`${envName} points to missing file '${override}'. ${remediation}`);
    return override;
  }

  const command = os.platform() === "win32" ? "where.exe" : "which";
  try {
    const found = execFileSync(command, [name], { encoding: "utf8" })
      .split(/\r?\n/)
      .find((entry) => entry && !entry.endsWith(".ps1"));
    if (found) {
      return os.platform() === "win32" && found.toLowerCase().endsWith(".cmd") ? name : found;
    }
  } catch {}
  fail(`Required command '${name}' was not found. ${remediation}`);
}

function findAzmcp() {
  if (process.env.AZMCP_EXE) {
    return findExecutable("azmcp", "Install with: npm install -g @azure/mcp@3.0.0-beta.43", "AZMCP_EXE");
  }
  try {
    const npm = os.platform() === "win32" ? "npm.cmd" : "npm";
    const root = execFileSync(npm, ["root", "-g"], {
      encoding: "utf8",
      shell: os.platform() === "win32",
    }).trim();
    const base = path.join(root, "@azure", "mcp", "node_modules", "@azure");
    const exe = os.platform() === "win32" ? "azmcp.exe" : "azmcp";
    if (fs.existsSync(base)) {
      for (const entry of fs.readdirSync(base, { withFileTypes: true })) {
        const candidate = path.join(base, entry.name, "dist", exe);
        if (entry.isDirectory() && fs.existsSync(candidate)) return candidate;
      }
    }
  } catch {}
  return findExecutable("azmcp", "Install with: npm install -g @azure/mcp@3.0.0-beta.43", "AZMCP_EXE");
}

function findSrectl() {
  if (process.env.SRECTL_EXE) {
    return findExecutable("srectl", "Install the approved SRE Agent CLI as a .NET global tool.", "SRECTL_EXE");
  }
  const exe = os.platform() === "win32" ? "srectl.exe" : "srectl";
  const dotnetTool = path.join(os.homedir(), ".dotnet", "tools", exe);
  if (fs.existsSync(dotnetTool)) return dotnetTool;
  return findExecutable("srectl", "Install the approved SRE Agent CLI as a .NET global tool.", "SRECTL_EXE");
}

function run(executable, args, options = {}) {
  try {
    return execFileSync(executable, args, {
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
      shell: os.platform() === "win32" && executable.toLowerCase().endsWith(".cmd"),
      ...options,
    }).trim();
  } catch (error) {
    const detail = `${error.stdout || ""}${error.stderr || ""}${error.message || ""}`.trim();
    fail(`Command failed: ${path.basename(executable)} ${args.join(" ")}\n${detail.slice(0, 2400)}`);
  }
}

function readJson(filePath, purpose) {
  if (!fs.existsSync(filePath)) fail(`${purpose} is missing at '${filePath}'.`);
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(`${purpose} is invalid JSON: ${error.message}`);
  }
}

function resolveBundle(bundlePath) {
  const bundle = readJson(bundlePath, "Caldova agent bundle");
  if (bundle.schemaVersion !== 2 || bundle.incidentPlatform !== "AzMonitor") {
    fail("The Caldova agent bundle must use schemaVersion 2 and incidentPlatform 'AzMonitor'.");
  }
  const root = path.dirname(bundlePath);
  const references = [
    bundle.connectors,
    ...bundle.sourceDocuments.map((document) => document.path),
    bundle.skill?.path,
    bundle.customAgent?.path,
    bundle.responsePlan?.path,
  ];
  for (const reference of references) {
    if (!reference || !fs.existsSync(path.join(root, reference))) {
      fail(`The Caldova agent bundle references missing artifact '${reference || "<empty>"}'.`);
    }
  }
  if (!Array.isArray(bundle.scheduledTasks) || bundle.scheduledTasks.length !== 5) {
    fail("The preconfigured Caldova bundle must define exactly five scheduled tasks.");
  }
  const taskNames = new Set();
  for (const task of bundle.scheduledTasks) {
    if (!task?.name || !task?.description || !task?.cronExpression || !task?.message) {
      fail("Every scheduled task requires name, description, cronExpression, and message.");
    }
    if (taskNames.has(task.name)) fail(`Duplicate scheduled task '${task.name}'.`);
    taskNames.add(task.name);
  }
  return { bundle, root };
}

function substitute(content, values) {
  let result = content;
  for (const [key, value] of Object.entries(values)) {
    result = result.split(`@@${key}@@`).join(value);
  }
  return result;
}

function getAgentResource(az, subscription, resourceGroup, agent) {
  const output = run(az, [
    "rest",
    "--method", "get",
    "--url", `https://management.azure.com/subscriptions/${subscription}/resourceGroups/${resourceGroup}/providers/Microsoft.App/agents/${agent}?api-version=${apiVersion}`,
    "--output", "json",
  ]);
  const resource = JSON.parse(output);
  if (resource?.properties?.provisioningState !== "Succeeded") {
    fail(`SRE Agent '${agent}' is not ready (provisioning: ${resource?.properties?.provisioningState ?? "unknown"}).`);
  }
  if (resource?.properties?.incidentManagementConfiguration?.type !== "AzMonitor") {
    fail(`SRE Agent '${agent}' is not configured for Azure Monitor.`);
  }
  if (Object.keys(resource?.identity?.userAssignedIdentities ?? {}).length !== 1) {
    fail(`SRE Agent '${agent}' must have exactly one user-assigned identity before configuration.`);
  }
  if (!resource?.properties?.agentEndpoint) {
    fail(`SRE Agent '${agent}' has no data-plane endpoint. Wait for provisioning and retry.`);
  }
  return resource;
}

function checkProvider(az, subscription) {
  const account = JSON.parse(run(az, ["account", "show", "--subscription", subscription, "--output", "json"]));
  if (!account?.id) fail(`Azure CLI has no active identity for subscription '${subscription}'. Run 'az login' with the Skillable identity.`);
  const provider = JSON.parse(run(az, [
    "provider", "show",
    "--namespace", "Microsoft.App",
    "--subscription", subscription,
    "--output", "json",
  ]));
  if (provider.registrationState !== "Registered") {
    fail(`Microsoft.App is '${provider.registrationState}', not Registered. Register it with 'az provider register --namespace Microsoft.App' using an authorized identity.`);
  }
  const agents = provider.resourceTypes?.find((resourceType) => resourceType.resourceType === "agents");
  if (!agents?.apiVersions?.includes(apiVersion)) {
    fail(`Microsoft.App/agents API ${apiVersion} is unavailable in subscription '${subscription}'. Confirm preview access/provider rollout.`);
  }
}

function writeWorkspace(bundleInfo, resourceGroup) {
  const { bundle, root } = bundleInfo;
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-srectl-"));
  const values = { RG: resourceGroup };
  const skillDir = path.join(temp, "skills", bundle.skill.name);
  const agentDir = path.join(temp, "agents", bundle.customAgent.name);
  const filterDir = path.join(temp, "IncidentFilters");
  fs.mkdirSync(skillDir, { recursive: true });
  fs.mkdirSync(agentDir, { recursive: true });
  fs.mkdirSync(filterDir, { recursive: true });
  fs.writeFileSync(
    path.join(skillDir, "SKILL.md"),
    substitute(fs.readFileSync(path.join(root, bundle.skill.path), "utf8"), values),
  );
  fs.writeFileSync(
    path.join(agentDir, `${bundle.customAgent.name}.yaml`),
    substitute(fs.readFileSync(path.join(root, bundle.customAgent.path), "utf8"), values),
  );
  fs.writeFileSync(
    path.join(filterDir, `${bundle.responsePlan.name}.yaml`),
    substitute(fs.readFileSync(path.join(root, bundle.responsePlan.path), "utf8"), values),
  );
  return temp;
}

function withSrectlEndpoint(srectl, endpoint, workspace, callback) {
  const configPath = path.join(os.homedir(), ".sreagent", "config.json");
  const backup = fs.existsSync(configPath) ? fs.readFileSync(configPath) : null;
  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  const now = new Date().toISOString();
  fs.writeFileSync(configPath, JSON.stringify({
    resource_url: endpoint,
    auth_required: true,
    last_updated: now,
    created_at: now,
  }, null, 2));
  try {
    callback();
  } finally {
    if (backup) fs.writeFileSync(configPath, backup);
    else fs.rmSync(configPath, { force: true });
    fs.rmSync(workspace, { recursive: true, force: true });
  }
}

function applySourceDocuments(azmcp, target, bundleInfo) {
  for (const document of bundleInfo.bundle.sourceDocuments) {
    const content = substitute(
      fs.readFileSync(path.join(bundleInfo.root, document.path), "utf8"),
      { RG: target.resourceGroup },
    );
    run(azmcp, [
      "sreagent", "docs", "memories_add",
      "--name", document.name,
      "--content", content,
      "--agent", target.agent,
      "--subscription", target.subscription,
      "--resource-group", target.resourceGroup,
    ]);
  }
}

function sha256(filePath) {
  return createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function packageSummary(relativeDirectory) {
  const packagePath = path.join(repoRoot, relativeDirectory, "package.json");
  const lockPath = path.join(repoRoot, relativeDirectory, "package-lock.json");
  const manifest = readJson(packagePath, `${relativeDirectory} package manifest`);
  const dependencies = Object.entries(manifest.dependencies ?? {})
    .map(([name, version]) => `${name}@${version}`)
    .sort();
  return {
    manifest: `${relativeDirectory.replaceAll("\\", "/")}/package.json`,
    lockfile: `${relativeDirectory.replaceAll("\\", "/")}/package-lock.json`,
    lockfileSha256: sha256(lockPath),
    dependencies,
  };
}

function applyDeploymentEvidence(az, azmcp, target) {
  const commit = run("git", ["rev-parse", "HEAD"], { cwd: repoRoot });
  const apps = JSON.parse(run(az, [
    "containerapp", "list",
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
    "--query", "[].{name:name,image:properties.template.containers[0].image,revision:properties.latestRevisionName,fqdn:properties.configuration.ingress.fqdn}",
    "--output", "json",
  ]));
  const document = [
    "# Caldova deployment evidence",
    "",
    `Generated: ${new Date().toISOString()}`,
    `Resource group: ${target.resourceGroup}`,
    `Active source repository: ${process.env.CALDOVA_SOURCE_REPOSITORY || "not connected; use packaged fallback until the isolated learner repository is provisioned"}`,
    "Template source: https://github.com/microsoft/ignite26-PREL38",
    `Source commit: ${commit}`,
    "",
    "## Dependency evidence",
    "",
    "```json",
    JSON.stringify([
      packageSummary(path.join("src", "portal")),
      packageSummary(path.join("src", "api")),
    ], null, 2),
    "```",
    "",
    "## Deployed image evidence",
    "",
    "```json",
    JSON.stringify(apps, null, 2),
    "```",
    "",
    "An image without an `@sha256:` digest is not immutable evidence. A missing Defender finding set, SBOM, lockfile, image digest, registry manifest, or exposure result makes a CVE conclusion INCONCLUSIVE rather than clean.",
  ].join("\n");
  run(azmcp, [
    "sreagent", "docs", "memories_add",
    "--name", "caldova-deployment-evidence",
    "--content", document,
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]);
}

function parseTaskList(output) {
  const parsed = JSON.parse(output);
  const tasks = parsed?.results?.tasks ?? parsed?.results ?? parsed?.tasks ?? [];
  if (!Array.isArray(tasks)) fail("Scheduled-task list returned an unexpected response.");
  return tasks;
}

function applyScheduledTasks(azmcp, target, bundleInfo) {
  let existing = parseTaskList(run(azmcp, [
    "sreagent", "scheduledtasks", "list",
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]));
  for (const task of bundleInfo.bundle.scheduledTasks) {
    if (existing.some((item) => item.name === task.name)) continue;
    run(azmcp, [
      "sreagent", "scheduledtasks", "create",
      "--name", task.name,
      "--description", task.description,
      "--cron-expression", task.cronExpression,
      "--message", substitute(task.message, { RG: target.resourceGroup }),
      "--agent", target.agent,
      "--subscription", target.subscription,
      "--resource-group", target.resourceGroup,
    ]);
  }
  existing = parseTaskList(run(azmcp, [
    "sreagent", "scheduledtasks", "list",
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]));
  const expected = new Set(bundleInfo.bundle.scheduledTasks.map((task) => task.name));
  const configured = existing.filter((task) => expected.has(task.name));
  if (configured.length !== expected.size) {
    fail(`Expected five Caldova weekly tasks on '${target.agent}', found ${configured.length}.`);
  }
}

function applyMicrosoftLearn(azmcp, target, connectorsPath) {
  const connectors = readJson(connectorsPath, "Connector manifest");
  const connector = connectors.connectors?.find((item) => item.name === "microsoft-learn");
  if (!connector) fail("Connector manifest does not define microsoft-learn.");
  run(azmcp, [
    "sreagent", "connectors", "create_mcp",
    "--name", connector.name,
    "--type", connector.type,
    "--endpoint", connector.endpoint,
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]);
}

function applyIncidentFilter(az, target, responsePlan) {
  const encoded = Buffer.from(JSON.stringify(responsePlan.spec), "utf8").toString("base64");
  const bodyPath = path.join(os.tmpdir(), `caldova-filter-${process.pid}-${Date.now()}.json`);
  fs.writeFileSync(bodyPath, JSON.stringify({ properties: { value: encoded } }));
  try {
    run(az, [
      "rest",
      "--method", "put",
      "--url", `https://management.azure.com/subscriptions/${target.subscription}/resourceGroups/${target.resourceGroup}/providers/Microsoft.App/agents/${target.agent}/incidentFilters/${responsePlan.name}?api-version=${apiVersion}`,
      "--body", `@${bodyPath}`,
      "--output", "none",
    ]);
  } finally {
    fs.rmSync(bodyPath, { force: true });
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const major = Number(process.versions.node.split(".")[0]);
  if (major < 22) fail(`Node.js 22 or later is required; found ${process.version}. Install Node.js 22+ in the Skillable image.`);

  const az = findExecutable(os.platform() === "win32" ? "az.cmd" : "az", "Install Azure CLI and authenticate with the Skillable identity.");
  const azmcp = findAzmcp();
  const srectl = findSrectl();
  const azmcpVersion = run(azmcp, ["--version"]);
  if (!azmcpVersion.includes(requiredAzmcpVersion)) {
    fail(`Azure MCP ${requiredAzmcpVersion} is required; found '${azmcpVersion}'. Run: npm install -g @azure/mcp@${requiredAzmcpVersion}`);
  }
  run(srectl, ["version"]);

  const bundlePath = path.resolve(args.bundle);
  const bundleInfo = resolveBundle(bundlePath);
  run(az, ["account", "set", "--subscription", args.subscription]);
  checkProvider(az, args.subscription);
  const preconfiguredResource = getAgentResource(az, args.subscription, args["resource-group"], args["preconfigured-agent"]);
  const configureResource = getAgentResource(az, args.subscription, args["resource-group"], args["configure-agent"]);

  console.log(`Prerequisites passed: node ${process.version}, Azure CLI, azmcp ${requiredAzmcpVersion}, srectl, Microsoft.App/agents ${apiVersion}, active Azure identity, bundle, and both agent endpoints.`);
  if (args.mode === "check") return;

  const github = await configurePreconfiguredGitHub({
    azPath: az,
    preconfiguredResource,
    configureResource,
    repositoryUrl: args.repository,
  });
  process.env.CALDOVA_SOURCE_REPOSITORY = github.repositoryUrl;

  const connectorsPath = path.join(bundleInfo.root, bundleInfo.bundle.connectors);
  const targets = [
    { subscription: args.subscription, resourceGroup: args["resource-group"], agent: args["preconfigured-agent"], resource: preconfiguredResource },
    { subscription: args.subscription, resourceGroup: args["resource-group"], agent: args["configure-agent"], resource: configureResource },
  ];

  for (const target of targets) {
    await configureAzureMcp({
      azPath: az,
      subscription: target.subscription,
      resourceGroup: target.resourceGroup,
      agent: target.agent,
      agentResource: target.resource,
      manifestPath: connectorsPath,
    });
    applyMicrosoftLearn(azmcp, target, connectorsPath);
    applySourceDocuments(azmcp, target, bundleInfo);
    applyDeploymentEvidence(az, azmcp, target);
    run(azmcp, [
      "sreagent", "connectors", "list",
      "--agent", target.agent,
      "--subscription", target.subscription,
      "--resource-group", target.resourceGroup,
    ]);
    console.log(`Common context configured for ${target.agent}.`);
  }

  for (const target of targets) {
    const workspace = writeWorkspace(bundleInfo, target.resourceGroup);
    withSrectlEndpoint(srectl, target.resource.properties.agentEndpoint, workspace, () => {
      run(srectl, ["skill", "apply", "--name", bundleInfo.bundle.skill.name, "--quiet"], { cwd: workspace });
      run(srectl, ["agent", "apply", "--name", bundleInfo.bundle.customAgent.name, "--quiet"], { cwd: workspace });
    });
    applyIncidentFilter(az, target, bundleInfo.bundle.responsePlan);
  }
  applyScheduledTasks(azmcp, targets[0], bundleInfo);

  console.log(`Incident skill, custom agent, Azure Monitor response plan, and governance hook applied to both agents.`);
  console.log(`Five weekly read-only tasks applied only to ${args["preconfigured-agent"]}.`);
  console.log(`Preconfigured GitHub source/operations access verified for ${github.repositoryUrl}; Configure Agent remains disconnected for learner OAuth.`);
  console.log(`${args["configure-agent"]} retains connectors and source context only for the learner configuration path.`);
}

main().catch((error) => {
  console.error(`Caldova SRE Agent configuration failed: ${error.message}`);
  process.exitCode = 1;
});
