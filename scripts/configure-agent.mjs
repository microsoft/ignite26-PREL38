import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";
import { configureAzureMcp } from "./configure-azure-mcp.mjs";
import { configurePreconfiguredGitHub } from "./configure-github.mjs";
import { configureLiveReports } from "./configure-live-reports.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(__dirname, "..");
const apiVersion = "2025-05-01-preview";
const requiredAzmcpVersion = "3.0.0-beta.43";
const sreTokenAudience = "https://azuresre.dev";

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const result = { mode: "apply" };
  const args = [...argv];
  if (["check", "apply", "finops", "tasks"].includes(args[0])) result.mode = args.shift();
  while (args.length > 0) {
    const key = args.shift();
    if (!key.startsWith("--") || args.length === 0) fail(`Invalid argument '${key}'.`);
    result[key.slice(2)] = args.shift();
  }
  const required = ["finops", "tasks"].includes(result.mode)
    ? ["subscription", "resource-group", "preconfigured-agent", "bundle"]
    : ["subscription", "resource-group", "preconfigured-agent", "configure-agent", "bundle", "repository"];
  for (const key of required) {
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
  const useShell = os.platform() === "win32" && executable.toLowerCase().endsWith(".cmd");
  const commandArgs = useShell
    ? args.map((arg) => /[\s&|<>()^"]/.test(arg) ? `"${arg.replaceAll('"', '\\"')}"` : arg)
    : args;
  try {
    return execFileSync(executable, commandArgs, {
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
      shell: useShell,
      ...options,
    }).trim();
  } catch (error) {
    const detail = `${error.stdout || ""}${error.stderr || ""}${error.message || ""}`.trim();
    fail(`Command failed: ${path.basename(executable)} ${args.join(" ")}\n${detail.slice(0, 2400)}`);
  }
}

function runListOrEmpty(executable, args, options = {}) {
  try {
    return run(executable, args, options);
  } catch (error) {
    if (error.message.includes("No extended agents found") ||
        error.message.includes("No extended skills found") ||
        error.message.includes("No skills found")) {
      return "";
    }
    throw error;
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
    ...(bundle.skills ?? []).map((skill) => skill.path),
    bundle.customAgent?.path,
    bundle.customAgent?.criticPath,
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
  if (!Array.isArray(bundle.liveReports) || bundle.liveReports.length !== 2) {
    fail("The preconfigured Caldova bundle must define exactly two Live Reports.");
  }
  if (!Array.isArray(bundle.skills) || bundle.skills.length < 2) {
    fail("The Caldova bundle must define the incident-triage and incident-summary skills.");
  }
  if (!bundle.gettingStarted?.markerMemory || !bundle.gettingStarted?.titleMatch || !bundle.gettingStarted?.message) {
    fail("The Caldova bundle must define the idempotent Getting started bootstrap.");
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

function getOperationalContext(az, target) {
  const resources = JSON.parse(run(az, [
    "resource", "list",
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
    "--output", "json",
  ]));
  const findOne = (type, purpose) => {
    const matches = resources.filter((resource) => resource.type?.toLowerCase() === type.toLowerCase());
    if (matches.length !== 1) fail(`Expected exactly one ${purpose} in '${target.resourceGroup}', found ${matches.length}.`);
    return matches[0];
  };
  const workspace = findOne("Microsoft.OperationalInsights/workspaces", "Log Analytics workspace");
  const appInsights = findOne("Microsoft.Insights/components", "Application Insights component");
  const workspaceResource = JSON.parse(run(az, [
    "monitor", "log-analytics", "workspace", "show",
    "--ids", workspace.id,
    "--output", "json",
  ]));
  const appInsightsResource = JSON.parse(run(az, [
    "resource", "show",
    "--ids", appInsights.id,
    "--api-version", "2020-02-02",
    "--output", "json",
  ]));
  const identityResourceId = Object.keys(target.resource?.identity?.userAssignedIdentities ?? {})[0];
  const identity = JSON.parse(run(az, ["identity", "show", "--ids", identityResourceId, "--output", "json"]));
  const lawGuid = workspaceResource?.customerId;
  const appId = appInsightsResource?.properties?.AppId ?? appInsightsResource?.properties?.appId;
  if (!lawGuid || !appId || !identity?.principalId || !identity?.clientId || !identity?.tenantId) {
    fail(`Could not resolve telemetry identifiers or execution identity for '${target.agent}'. Required: LAW customerId, Application Insights appId, and managed-identity IDs.`);
  }
  return {
    RG: target.resourceGroup,
    SUBSCRIPTION_ID: target.subscription,
    LAW_WORKSPACE_RESOURCE_ID: workspace.id,
    LAW_WORKSPACE_GUID: lawGuid,
    APP_INSIGHTS_RESOURCE_ID: appInsights.id,
    APP_INSIGHTS_APP_ID: appId,
    AGENT_PRINCIPAL_ID: identity.principalId,
    AGENT_IDENTITY_RESOURCE_ID: identityResourceId,
    AGENT_CLIENT_ID: identity.clientId,
    AGENT_TENANT_ID: identity.tenantId,
  };
}

function resolveRoleDefinition(az, subscription, roleName) {
  const roles = JSON.parse(run(az, [
    "role", "definition", "list",
    "--subscription", subscription,
    "--name", roleName,
    "--output", "json",
  ]));
  if (roles.length !== 1 || !roles[0]?.id) {
    fail(`Azure role '${roleName}' could not be resolved uniquely in subscription '${subscription}'. Event operations must verify the role catalog before agent configuration.`);
  }
  return roles[0];
}

function ensureRoleAssignment(az, { subscription, principalId, roleName, scope }) {
  const role = resolveRoleDefinition(az, subscription, roleName);
  const assignments = JSON.parse(run(az, [
    "role", "assignment", "list",
    "--subscription", subscription,
    "--scope", scope,
    "--include-inherited",
    "--output", "json",
  ]));
  const exists = assignments.some((assignment) =>
    assignment.principalId?.toLowerCase() === principalId.toLowerCase() &&
    assignment.roleDefinitionId?.toLowerCase() === role.id.toLowerCase());
  if (exists) return role.id;
  try {
    run(az, [
      "role", "assignment", "create",
      "--subscription", subscription,
      "--assignee-object-id", principalId,
      "--assignee-principal-type", "ServicePrincipal",
      "--role", role.id,
      "--scope", scope,
      "--output", "none",
    ]);
  } catch (error) {
    fail(`Missing '${roleName}' (${role.id}) for SRE Agent principal '${principalId}' at scope '${scope}', and the Skillable identity cannot create it. Event operations must apply this exact role assignment (requires Microsoft.Authorization/roleAssignments/write), then rerun configuration. ${error.message}`);
  }
  return role.id;
}

function ensureEvidenceAccess(az, target, context, includeCost) {
  const resourceGroupScope = `/subscriptions/${target.subscription}/resourceGroups/${target.resourceGroup}`;
  const roles = {
    logAnalyticsReader: ensureRoleAssignment(az, {
      subscription: target.subscription,
      principalId: context.AGENT_PRINCIPAL_ID,
      roleName: "Log Analytics Reader",
      scope: context.LAW_WORKSPACE_RESOURCE_ID,
    }),
    logAnalyticsDataReader: ensureRoleAssignment(az, {
      subscription: target.subscription,
      principalId: context.AGENT_PRINCIPAL_ID,
      roleName: "Log Analytics Data Reader",
      scope: context.LAW_WORKSPACE_RESOURCE_ID,
    }),
    privilegedMonitoringDataReader: ensureRoleAssignment(az, {
      subscription: target.subscription,
      principalId: context.AGENT_PRINCIPAL_ID,
      roleName: "Privileged Monitoring Data Reader",
      scope: context.LAW_WORKSPACE_RESOURCE_ID,
    }),
    monitoringReader: ensureRoleAssignment(az, {
      subscription: target.subscription,
      principalId: context.AGENT_PRINCIPAL_ID,
      roleName: "Monitoring Reader",
      scope: resourceGroupScope,
    }),
  };
  if (includeCost) {
    roles.reader = ensureRoleAssignment(az, {
      subscription: target.subscription,
      principalId: context.AGENT_PRINCIPAL_ID,
      roleName: "Reader",
      scope: resourceGroupScope,
    });
    roles.costManagementReader = ensureRoleAssignment(az, {
      subscription: target.subscription,
      principalId: context.AGENT_PRINCIPAL_ID,
      roleName: "Cost Management Reader",
      scope: resourceGroupScope,
    });
  }
  return roles;
}

function closeRecoveredAcknowledgedAlerts(az, target) {
  const listUrl = `/subscriptions/${target.subscription}/providers/Microsoft.AlertsManagement/alerts`;
  const resourceGroupSegment = `/resourceGroups/${target.resourceGroup}/`.toLowerCase();
  const result = JSON.parse(run(az, [
    "rest",
    "--method", "get",
    "--url", listUrl,
    "--url-parameters", "api-version=2019-03-01",
    "--output", "json",
  ]));
  const recovered = (result.value ?? []).filter((alert) => {
    const essentials = alert?.properties?.essentials;
    return essentials?.alertRule?.includes("Caldova") &&
      essentials.targetResource?.toLowerCase().includes(resourceGroupSegment) &&
      essentials.monitorCondition === "Resolved" &&
      essentials.alertState !== "Closed";
  });
  for (const alert of recovered) {
    run(az, [
      "rest",
      "--method", "post",
      "--url", `${alert.id}/changeState`,
      "--url-parameters", "api-version=2019-03-01", "newState=Closed",
      "--output", "none",
    ]);
    const verified = JSON.parse(run(az, [
      "rest",
      "--method", "get",
      "--url", alert.id,
      "--url-parameters", "api-version=2019-03-01",
      "--output", "json",
    ]));
    if (verified?.properties?.essentials?.alertState !== "Closed") {
      fail(`Recovered alert '${alert.id}' did not transition to Closed. Event operations must close it without deleting the retained incident evidence.`);
    }
  }
  return recovered.length;
}

function writeWorkspace(bundleInfo, values) {
  const { bundle, root } = bundleInfo;
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-srectl-"));
  const agentDir = path.join(temp, "agents", bundle.customAgent.name);
  const filterDir = path.join(temp, "IncidentFilters");
  fs.mkdirSync(agentDir, { recursive: true });
  fs.mkdirSync(filterDir, { recursive: true });
  for (const skill of bundle.skills) {
    const skillDir = path.join(temp, "skills", skill.name);
    fs.mkdirSync(skillDir, { recursive: true });
    fs.writeFileSync(
      path.join(skillDir, "SKILL.md"),
      substitute(fs.readFileSync(path.join(root, skill.path), "utf8"), values),
    );
  }
  fs.writeFileSync(
    path.join(agentDir, `${bundle.customAgent.name}.yaml`),
    substitute(fs.readFileSync(path.join(root, bundle.customAgent.path), "utf8"), values),
  );
  fs.writeFileSync(
    path.join(agentDir, "critic.md"),
    substitute(fs.readFileSync(path.join(root, bundle.customAgent.criticPath), "utf8"), values),
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

function applySourceDocuments(azmcp, target, bundleInfo, values) {
  for (const document of bundleInfo.bundle.sourceDocuments) {
    const content = substitute(
      fs.readFileSync(path.join(bundleInfo.root, document.path), "utf8"),
      values,
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

function applyDeploymentEvidence(az, azmcp, target, context, roleDefinitionIds) {
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
    `SRE Agent principal ID: ${context.AGENT_PRINCIPAL_ID}`,
    `Log Analytics workspace GUID: ${context.LAW_WORKSPACE_GUID}`,
    `Application Insights appId: ${context.APP_INSIGHTS_APP_ID}`,
    `Validated role-definition IDs: ${JSON.stringify(roleDefinitionIds)}`,
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
    const message = substitute(task.message, { RG: target.resourceGroup });
    const current = existing.find((item) => item.name === task.name);
    if (current) {
      const currentCron = current.cronExpression ?? current.schedule?.cronExpression;
      const currentMessage = current.message ?? current.prompt ?? current.agentPrompt;
      const unchanged = current.description === task.description &&
        currentCron === task.cronExpression &&
        currentMessage === message;
      if (unchanged) continue;
      const taskId = current.id ?? current.taskId;
      if (!taskId) fail(`Scheduled task '${task.name}' requires replacement but its task ID is missing.`);
      run(azmcp, [
        "sreagent", "scheduledtasks", "delete",
        "--task-id", taskId,
        "--agent", target.agent,
        "--subscription", target.subscription,
        "--resource-group", target.resourceGroup,
      ]);
      existing = existing.filter((item) => item !== current);
    }

    run(azmcp, [
      "sreagent", "scheduledtasks", "create",
      "--name", task.name,
      "--description", task.description,
      "--cron-expression", task.cronExpression,
      "--message", message,
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

function applyScheduledTaskSkills(azmcp, target, bundleInfo) {
  const skills = bundleInfo.bundle.skills.filter((skill) => skill.scheduledTaskShared);
  for (const skill of skills) {
    const content = substitute(
      fs.readFileSync(path.join(bundleInfo.root, skill.path), "utf8"),
      { RG: target.resourceGroup },
    );
    run(azmcp, [
      "sreagent", "skills", "create",
      "--name", skill.name,
      "--content", content,
      "--description", skill.description,
      "--agent", target.agent,
      "--subscription", target.subscription,
      "--resource-group", target.resourceGroup,
    ]);
  }
}

function parseItems(output, key) {
  const parsed = JSON.parse(output);
  const items = parsed?.results?.[key] ?? parsed?.results ?? parsed?.[key] ?? [];
  if (!Array.isArray(items)) fail(`${key} list returned an unexpected response.`);
  return items;
}

function applyGettingStartedThread(azmcp, target, bundleInfo) {
  const bootstrap = bundleInfo.bundle.gettingStarted;
  const memoryResponse = JSON.parse(run(azmcp, [
    "sreagent", "docs", "memories_list",
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]));
  const memoryCatalog = memoryResponse?.results?.message ?? "";
  const marker = memoryCatalog.includes(`**${bootstrap.markerMemory}.md**`) ||
    memoryCatalog.includes(`**${bootstrap.markerMemory}**`);
  let markerThreadId;
  if (marker) {
    const search = JSON.parse(run(azmcp, [
      "sreagent", "docs", "memories_search",
      "--query", `${bootstrap.markerMemory} Getting started thread`,
      "--agent", target.agent,
      "--subscription", target.subscription,
      "--resource-group", target.resourceGroup,
    ]));
    markerThreadId = search?.results?.message
      ?.match(/Getting started thread:\s*([0-9a-f-]{36})/i)?.[1];
  }
  const threads = parseItems(run(azmcp, [
    "sreagent", "threads", "list",
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]), "threads");
  const markedThread = markerThreadId &&
    threads.find((thread) => (thread.id ?? thread.threadId) === markerThreadId);
  if (markedThread) return markerThreadId;
  const existing = threads.find((thread) =>
    (thread.title ?? thread.name ?? "").includes(bootstrap.titleMatch));
  const recordMarker = (threadId) => {
    run(azmcp, [
      "sreagent", "docs", "memories_add",
      "--name", bootstrap.markerMemory,
      "--content", `Getting started thread: ${threadId}\nCreated: ${new Date().toISOString()}\nScope: ${target.resourceGroup}`,
      "--agent", target.agent,
      "--subscription", target.subscription,
      "--resource-group", target.resourceGroup,
    ]);
  };
  if (existing) {
    const threadId = existing.id ?? existing.threadId;
    if (!threadId) fail("Existing Getting started thread has no thread ID.");
    if (!marker) recordMarker(threadId);
    return threadId;
  }

  const created = JSON.parse(run(azmcp, [
    "sreagent", "threads", "create",
    "--message", substitute(bootstrap.message, { RG: target.resourceGroup }),
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]));
  const createdResult = Array.isArray(created?.results) ? created.results[0] : created?.results;
  const threadId = createdResult?.threadId ?? createdResult?.id ?? created?.threadId ?? created?.id;
  if (!threadId) fail("Getting started thread creation returned no thread ID.");
  recordMarker(threadId);
  return threadId;
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

async function applyFinOpsConnector(az, azmcp, target, connectorsPath) {
  const connectors = readJson(connectorsPath, "Connector manifest");
  const connector = connectors.connectors?.find((item) => item.name === "caldova-finops");
  if (!connector || connector.type !== "stdio" || !connector.command || !connector.scriptPath) {
    fail("Connector manifest does not define the Caldova FinOps stdio connector.");
  }
  const scriptPath = path.resolve(path.dirname(connectorsPath), connector.scriptPath);
  if (!fs.existsSync(scriptPath)) fail(`Caldova FinOps MCP server is missing at '${scriptPath}'.`);
  const resources = JSON.parse(run(az, [
    "resource", "list",
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
    "--output", "json",
  ]));
  const normalizedSku = (value) => String(value ?? "").toLowerCase().replace(/^standard_/, "");
  const desiredByService = new Map([
    ["Container Registry", new Set()],
    ["Azure Database for PostgreSQL", new Set()],
    ["Virtual Machines", new Set()],
    ["Application Gateway", new Set()],
  ]);
  const serviceByType = new Map([
    ["microsoft.containerregistry/registries", "Container Registry"],
    ["microsoft.dbforpostgresql/flexibleservers", "Azure Database for PostgreSQL"],
  ]);
  for (const resource of resources) {
    const service = serviceByType.get(resource.type?.toLowerCase());
    const sku = normalizedSku(resource.sku?.name);
    if (service && sku) desiredByService.get(service).add(sku);
  }
  const vmSkus = JSON.parse(run(az, [
    "vm", "list",
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
    "--query", "[].hardwareProfile.vmSize",
    "--output", "json",
  ]));
  const gatewaySkus = JSON.parse(run(az, [
    "network", "application-gateway", "list",
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
    "--query", "[].sku.name",
    "--output", "json",
  ]));
  for (const sku of vmSkus) desiredByService.get("Virtual Machines").add(normalizedSku(sku));
  for (const sku of gatewaySkus) desiredByService.get("Application Gateway").add(normalizedSku(sku));
  const retailItems = [];
  for (const service of ["Container Registry", "Azure Database for PostgreSQL", "Virtual Machines", "Application Gateway"]) {
    const filter = `serviceName eq '${service}' and armRegionName eq '${target.resource.location}' and priceType eq 'Consumption'`;
    let url = `https://prices.azure.com/api/retail/prices?$filter=${encodeURIComponent(filter)}`;
    for (let page = 0; url && page < 8; page += 1) {
      const response = await fetch(url, { signal: AbortSignal.timeout(60_000) });
      if (!response.ok) fail(`Azure Retail Prices snapshot failed for '${service}' (${response.status}).`);
      const data = await response.json();
      retailItems.push(...(data.Items ?? []).filter((item) => {
        const desiredSkus = desiredByService.get(service);
        const skuMatch = desiredSkus.has(normalizedSku(item.armSkuName)) || desiredSkus.has(normalizedSku(item.skuName));
        const gatewayMatch = service === "Application Gateway" &&
          [...desiredSkus].some((sku) => item.productName?.toLowerCase().includes(sku.replaceAll("_", " "))) &&
          item.meterName?.toLowerCase().includes("fixed cost");
        const safeMeter = service !== "Container Registry" || item.meterName?.toLowerCase().includes("registry unit");
        const safeProduct = service !== "Virtual Machines" || !item.productName?.toLowerCase().includes("windows");
        return item.isPrimaryMeterRegion !== false && Number(item.retailPrice) > 0 &&
          (skuMatch || gatewayMatch) && safeMeter && safeProduct;
      }));
      url = data.NextPageLink || "";
    }
  }
  const retailSnapshotBase64 = gzipSync(Buffer.from(JSON.stringify({
    capturedAtUtc: new Date().toISOString(),
    source: "Azure Retail Prices API",
    region: target.resource.location,
    items: retailItems,
  }))).toString("base64");
  const scriptBase64 = gzipSync(fs.readFileSync(scriptPath)).toString("base64");
  const bootstrap = [
    "import base64,gzip,os",
    `os.environ['CALDOVA_SUBSCRIPTION_ID']='${target.subscription}'`,
    `os.environ['CALDOVA_RESOURCE_GROUP']='${target.resourceGroup}'`,
    `os.environ['CALDOVA_EXPECTED_RESOURCE_GROUP']='${target.resourceGroup}'`,
    `os.environ['CALDOVA_RETAIL_PRICE_SNAPSHOT_B64']=base64.b64encode(gzip.decompress(base64.b64decode('${retailSnapshotBase64}'))).decode()`,
    `exec(gzip.decompress(base64.b64decode('${scriptBase64}')))`,
  ].join(";");
  run(azmcp, [
    "sreagent", "connectors", "create_mcp",
    "--name", connector.name,
    "--type", connector.type,
    "--command", connector.command,
    "--args", "-c",
    "--args", bootstrap,
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]);
  run(azmcp, [
    "sreagent", "connectors", "test",
    "--name", connector.name,
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]);
  const token = run(az, [
    "account", "get-access-token",
    "--resource", sreTokenAudience,
    "--query", "accessToken",
    "--output", "tsv",
  ]);
  const endpoint = target.resource.properties.agentEndpoint.replace(/\/$/, "");
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  const secretsResponse = await fetch(`${endpoint}/api/v2/extendedAgent/connectors/listSecrets`, { headers });
  if (!secretsResponse.ok) fail(`Could not read the FinOps connector secret-preserving definition (${secretsResponse.status}).`);
  const connectorResource = (await secretsResponse.json()).value?.find((item) => item.name === connector.name);
  if (!connectorResource) fail("The created Caldova FinOps connector was not returned by listSecrets.");
  connectorResource.properties.identity = target.context.AGENT_IDENTITY_RESOURCE_ID;
  connectorResource.properties.extendedProperties = {
    ...connectorResource.properties.extendedProperties,
    envs: {
      ...(connectorResource.properties.extendedProperties?.envs ?? {}),
      AZURE_CLIENT_ID: target.context.AGENT_CLIENT_ID,
      AZURE_TENANT_ID: target.context.AGENT_TENANT_ID,
      AZURE_SUBSCRIPTION_ID: target.subscription,
    },
    toolsVisibleToMetaAgent: ["caldova-finops_get_caldova_finops"],
  };
  const updateResponse = await fetch(`${endpoint}/api/v2/extendedAgent/connectors/${encodeURIComponent(connector.name)}`, {
    method: "PUT",
    headers,
    body: JSON.stringify(connectorResource),
  });
  if (!updateResponse.ok) {
    fail(`Could not bind the FinOps connector to the agent managed identity and select its tool (${updateResponse.status}).`);
  }
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

function reconcileConfigureAgentStarter(az, srectl, target, bundleInfo) {
  const filters = JSON.parse(run(az, [
    "rest",
    "--method", "get",
    "--url", `https://management.azure.com/subscriptions/${target.subscription}/resourceGroups/${target.resourceGroup}/providers/Microsoft.App/agents/${target.agent}/incidentFilters?api-version=${apiVersion}`,
    "--output", "json",
  ]));
  const existingFilter = (filters.value ?? []).find((filter) =>
    filter.name?.toLowerCase() === bundleInfo.bundle.responsePlan.name.toLowerCase());
  if (existingFilter?.id) {
    run(az, [
      "rest",
      "--method", "delete",
      "--url", `https://management.azure.com${existingFilter.id}?api-version=${apiVersion}`,
      "--output", "none",
    ]);
  }

  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-starter-"));
  withSrectlEndpoint(srectl, target.resource.properties.agentEndpoint, workspace, () => {
    const agents = runListOrEmpty(srectl, ["agent", "list", "--quiet"], { cwd: workspace });
    if (agents.includes(bundleInfo.bundle.customAgent.name)) {
      run(srectl, [
        "agent", "delete",
        "--name", bundleInfo.bundle.customAgent.name,
        "--delete-local-files", "false",
        "--quiet",
      ], { cwd: workspace });
    }
    const skills = runListOrEmpty(srectl, ["skill", "list", "--quiet"], { cwd: workspace });
    for (const skill of bundleInfo.bundle.skills) {
      if (!skills.includes(skill.name)) continue;
      run(srectl, [
        "skill", "delete",
        "--name", skill.name,
        "--delete-local-files", "false",
        "--quiet",
      ], { cwd: workspace });
    }
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const major = Number(process.versions.node.split(".")[0]);
  if (major < 22) fail(`Node.js 22 or later is required; found ${process.version}. Install Node.js 22+ in the Skillable image.`);

  const az = findExecutable(os.platform() === "win32" ? "az.cmd" : "az", "Install Azure CLI and authenticate with the Skillable identity.");
  const azmcp = findAzmcp();
  const srectl = ["finops", "tasks"].includes(args.mode) ? null : findSrectl();
  const azmcpVersion = run(azmcp, ["--version"]);
  if (!azmcpVersion.includes(requiredAzmcpVersion)) {
    fail(`Azure MCP ${requiredAzmcpVersion} is required; found '${azmcpVersion}'. Run: npm install -g @azure/mcp@${requiredAzmcpVersion}`);
  }
  if (srectl) run(srectl, ["version"]);

  const bundlePath = path.resolve(args.bundle);
  const bundleInfo = resolveBundle(bundlePath);
  run(az, ["account", "set", "--subscription", args.subscription]);
  checkProvider(az, args.subscription);
  const preconfiguredResource = getAgentResource(az, args.subscription, args["resource-group"], args["preconfigured-agent"]);

  if (args.mode === "tasks") {
    const target = {
      subscription: args.subscription,
      resourceGroup: args["resource-group"],
      agent: args["preconfigured-agent"],
      resource: preconfiguredResource,
    };
    applyScheduledTaskSkills(azmcp, target, bundleInfo);
    applyScheduledTasks(azmcp, target, bundleInfo);
    console.log(`Shared audit-report skill and five weekly tasks reapplied only to ${target.agent}.`);
    return;
  }

  if (args.mode === "finops") {
    const target = {
      subscription: args.subscription,
      resourceGroup: args["resource-group"],
      agent: args["preconfigured-agent"],
      resource: preconfiguredResource,
    };
    target.context = getOperationalContext(az, target);
    const connectorsPath = path.join(bundleInfo.root, bundleInfo.bundle.connectors);
    await applyFinOpsConnector(az, azmcp, target, connectorsPath);
    const reports = await configureLiveReports({
      azPath: az,
      azmcpPath: azmcp,
      target,
      reports: bundleInfo.bundle.liveReports,
    });
    console.log(`FinOps connector reapplied only to ${target.agent}.`);
    console.log(`Live Reports verified without replacement: ${reports.map((report) => `${report.name}=${report.id} (${report.configurationAction})`).join(", ")}.`);
    return;
  }

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
    target.context = getOperationalContext(az, target);
    target.roleDefinitionIds = ensureEvidenceAccess(
      az,
      target,
      target.context,
      target.agent === args["preconfigured-agent"],
    );
    applyMicrosoftLearn(azmcp, target, connectorsPath);
    applySourceDocuments(azmcp, target, bundleInfo, target.context);
    applyDeploymentEvidence(az, azmcp, target, target.context, target.roleDefinitionIds);
    run(azmcp, [
      "sreagent", "connectors", "list",
      "--agent", target.agent,
      "--subscription", target.subscription,
      "--resource-group", target.resourceGroup,
    ]);
    console.log(`Common context configured for ${target.agent}.`);
  }

  const preconfiguredTarget = targets[0];
  await configureAzureMcp({
    azPath: az,
    subscription: preconfiguredTarget.subscription,
    resourceGroup: preconfiguredTarget.resourceGroup,
    agent: preconfiguredTarget.agent,
    agentResource: preconfiguredTarget.resource,
    manifestPath: connectorsPath,
  });
  await applyFinOpsConnector(az, azmcp, preconfiguredTarget, connectorsPath);
  const workspace = writeWorkspace(bundleInfo, preconfiguredTarget.context);
  withSrectlEndpoint(srectl, preconfiguredTarget.resource.properties.agentEndpoint, workspace, () => {
    for (const skill of bundleInfo.bundle.skills) {
      run(srectl, ["skill", "apply", "--name", skill.name, "--quiet"], { cwd: workspace });
    }
    run(srectl, ["agent", "apply", "--name", bundleInfo.bundle.customAgent.name, "--quiet"], { cwd: workspace });
  });
  applyIncidentFilter(az, preconfiguredTarget, bundleInfo.bundle.responsePlan);
  reconcileConfigureAgentStarter(az, srectl, targets[1], bundleInfo);

  const closedAlerts = closeRecoveredAcknowledgedAlerts(az, preconfiguredTarget);
  applyScheduledTasks(azmcp, targets[0], bundleInfo);
  const gettingStartedThreads = targets.map((target) => ({
    agent: target.agent,
    threadId: applyGettingStartedThread(azmcp, target, bundleInfo),
  }));
  const reports = await configureLiveReports({
    azPath: az,
    azmcpPath: azmcp,
    target: targets[0],
    reports: bundleInfo.bundle.liveReports,
  });

  console.log(`Incident skills, custom agent, Azure Monitor response plan, and governance hook applied only to ${args["preconfigured-agent"]}.`);
  console.log(`Configure Agent retains only safe context, evidence access, Microsoft Learn, and its Getting started bootstrap.`);
  console.log(`Closed ${closedAlerts} recovered Caldova alerts that were still New or Acknowledged; completed incident evidence was retained.`);
  console.log(`Getting started threads verified: ${gettingStartedThreads.map((item) => `${item.agent}=${item.threadId}`).join(", ")}.`);
  console.log(`Five weekly read-only tasks applied only to ${args["preconfigured-agent"]}.`);
  console.log(`Two read-only Live Reports verified on ${args["preconfigured-agent"]}: ${reports.map((report) => report.name).join(", ")}.`);
  console.log(`Preconfigured GitHub source/operations access verified for ${github.repositoryUrl}; Configure Agent remains disconnected for learner OAuth.`);
}

main().catch((error) => {
  console.error(`Caldova SRE Agent configuration failed: ${error.message}`);
  process.exitCode = 1;
});
