import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(__dirname, "..");
const agentApiVersion = "2025-05-01-preview";
const alertsApiVersion = "2019-03-01";
const sreTokenAudience = "https://azuresre.dev";
const alertName = "Course-recommendations-unavailable";
const skillName = "course-recommendations-recovery";
const customAgentName = "caldova-guided-feature-responder";
const responsePlanName = "course-recommendations-learning-response";

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const args = [...argv];
  const operation = args.shift();
  if (!["apply", "enable", "disable", "verify"].includes(operation)) {
    fail("Operation must be apply, enable, disable, or verify.");
  }
  const result = { operation, expected: operation === "enable" ? "enabled" : "disabled" };
  while (args.length > 0) {
    const key = args.shift();
    if (!key?.startsWith("--") || args.length === 0) fail(`Invalid argument '${key ?? "<empty>"}'.`);
    result[key.slice(2)] = args.shift();
  }
  for (const key of ["subscription", "resource-group", "preconfigured-agent", "configure-agent"]) {
    if (!result[key]) fail(`Missing --${key}.`);
  }
  if (!["enabled", "disabled"].includes(result.expected)) {
    fail("--expected must be enabled or disabled.");
  }
  return result;
}

function findExecutable(name, fallback) {
  const command = os.platform() === "win32" ? "where.exe" : "which";
  try {
    const found = execFileSync(command, [name], { encoding: "utf8" })
      .split(/\r?\n/)
      .find((entry) => entry && !entry.endsWith(".ps1"));
    if (found) {
      return os.platform() === "win32" && found.toLowerCase().endsWith(".cmd") ? name : found;
    }
  } catch {}
  if (fallback && fs.existsSync(fallback)) return fallback;
  fail(`Required command '${name}' was not found.`);
}

function run(executable, args, options = {}) {
  const useShell = os.platform() === "win32" && executable.toLowerCase().endsWith(".cmd");
  try {
    return execFileSync(executable, args, {
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
      shell: useShell,
      ...options,
    }).trim();
  } catch (error) {
    const detail = `${error.stdout || ""}${error.stderr || ""}${error.message || ""}`.trim();
    fail(`Command failed: ${path.basename(executable)} ${args.join(" ")}\n${detail.slice(0, 3000)}`);
  }
}

function runJson(executable, args, options) {
  const output = run(executable, args, options);
  try {
    return JSON.parse(output);
  } catch (error) {
    fail(`Command returned invalid JSON: ${error.message}\n${output.slice(0, 1000)}`);
  }
}

function getAgentResource(az, args, agentName) {
  const url = `https://management.azure.com/subscriptions/${args.subscription}/resourceGroups/${args["resource-group"]}/providers/Microsoft.App/agents/${agentName}?api-version=${agentApiVersion}`;
  const resource = runJson(az, ["rest", "--method", "get", "--url", url, "--output", "json"]);
  if (resource?.properties?.provisioningState !== "Succeeded" || !resource?.properties?.agentEndpoint) {
    fail(`SRE Agent '${agentName}' is not ready or has no data-plane endpoint.`);
  }
  return resource;
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
    return callback();
  } finally {
    if (backup) fs.writeFileSync(configPath, backup);
    else fs.rmSync(configPath, { force: true });
    fs.rmSync(workspace, { recursive: true, force: true });
  }
}

function substitute(content, values) {
  let result = content;
  for (const [key, value] of Object.entries(values)) {
    result = result.replaceAll(`@@${key}@@`, value);
  }
  return result;
}

function createWorkspace(resourceGroup) {
  const source = path.join(repoRoot, "data", "agent", "guided-course-recommendations");
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-guided-"));
  const skillDir = path.join(workspace, "skills", skillName);
  const agentDir = path.join(workspace, "agents", customAgentName);
  fs.mkdirSync(skillDir, { recursive: true });
  fs.mkdirSync(agentDir, { recursive: true });
  fs.writeFileSync(
    path.join(skillDir, "SKILL.md"),
    substitute(fs.readFileSync(path.join(source, "skill", "SKILL.md"), "utf8"), { RG: resourceGroup }),
  );
  fs.writeFileSync(
    path.join(agentDir, `${customAgentName}.yaml`),
    substitute(
      fs.readFileSync(path.join(source, "agent", `${customAgentName}.yaml`), "utf8"),
      { RG: resourceGroup },
    ),
  );
  return workspace;
}

function listRemote(srectl, type, endpoint) {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-guided-list-"));
  return withSrectlEndpoint(srectl, endpoint, workspace, () => {
    try {
      return run(srectl, [type, "list", "--detail", "--quiet"], { cwd: workspace });
    } catch (error) {
      if (/No extended agents found|No extended skills found|No skills found/i.test(error.message)) return "";
      throw error;
    }
  });
}

function getRemoteDetail(srectl, type, name, endpoint) {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-guided-detail-"));
  return withSrectlEndpoint(srectl, endpoint, workspace, () =>
    run(srectl, [type, "list", "--name", name, "--quiet"], { cwd: workspace }));
}

function applyPreconfiguredArtifacts(srectl, endpoint, resourceGroup) {
  const workspace = createWorkspace(resourceGroup);
  withSrectlEndpoint(srectl, endpoint, workspace, () => {
    run(srectl, ["skill", "apply", "--name", skillName, "--quiet"], { cwd: workspace });
    run(srectl, ["agent", "validate", "--name", customAgentName, "--check-tools", "--quiet"], { cwd: workspace });
    run(srectl, ["agent", "apply", "--name", customAgentName, "--quiet"], { cwd: workspace });
  });
}

function findAzmcp() {
  const override = process.env.AZMCP_EXE;
  if (override && fs.existsSync(override)) return override;
  const npm = os.platform() === "win32" ? "npm.cmd" : "npm";
  try {
    const root = run(npm, ["root", "-g"]);
    const base = path.join(root, "@azure", "mcp", "node_modules", "@azure");
    const executable = os.platform() === "win32" ? "azmcp.exe" : "azmcp";
    for (const entry of fs.readdirSync(base, { withFileTypes: true })) {
      const candidate = path.join(base, entry.name, "dist", executable);
      if (entry.isDirectory() && fs.existsSync(candidate)) return candidate;
    }
  } catch {}
  return findExecutable(os.platform() === "win32" ? "azmcp.exe" : "azmcp");
}

async function applyGuidedConnector(az, azmcp, args, resource) {
  const connectorName = "caldova-guided-alerts";
  const scriptPath = path.join(repoRoot, "scripts", "caldova-guided-alerts-mcp.py");
  if (!fs.existsSync(scriptPath)) fail(`Guided alert MCP server is missing at '${scriptPath}'.`);
  const scriptBase64 = Buffer.from(fs.readFileSync(scriptPath)).toString("base64");
  const bootstrap = [
    "import os",
    `os.environ['CALDOVA_SUBSCRIPTION_ID']='${args.subscription}'`,
    `os.environ['CALDOVA_RESOURCE_GROUP']='${args["resource-group"]}'`,
    `os.environ['CALDOVA_GUIDED_ALERT_RULE']='${alertName}'`,
    `exec(__import__('base64').b64decode('${scriptBase64}'))`,
  ].join(";");
  run(azmcp, [
    "sreagent", "connectors", "create_mcp",
    "--name", connectorName,
    "--type", "stdio",
    "--command", "python3",
    "--args", "-c",
    "--args", bootstrap,
    "--agent", args["preconfigured-agent"],
    "--subscription", args.subscription,
    "--resource-group", args["resource-group"],
  ]);
  run(azmcp, [
    "sreagent", "connectors", "test",
    "--name", connectorName,
    "--agent", args["preconfigured-agent"],
    "--subscription", args.subscription,
    "--resource-group", args["resource-group"],
  ]);

  const identityResourceId = Object.keys(resource.identity?.userAssignedIdentities ?? {})[0];
  if (!identityResourceId) fail("Preconfigured Agent has no user-assigned identity for the guided alert connector.");
  const identity = runJson(az, ["identity", "show", "--ids", identityResourceId, "--output", "json"]);
  const token = run(az, [
    "account", "get-access-token",
    "--resource", sreTokenAudience,
    "--query", "accessToken",
    "--output", "tsv",
  ]);
  const endpoint = resource.properties.agentEndpoint.replace(/\/$/, "");
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  const secretsResponse = await fetch(`${endpoint}/api/v2/extendedAgent/connectors/listSecrets`, { headers });
  if (!secretsResponse.ok) fail(`Could not read guided connector definition (${secretsResponse.status}).`);
  const connectorResource = (await secretsResponse.json()).value?.find((item) => item.name === connectorName);
  if (!connectorResource) fail("Created guided alert connector was not returned by listSecrets.");
  connectorResource.properties.identity = identityResourceId;
  connectorResource.properties.extendedProperties = {
    ...connectorResource.properties.extendedProperties,
    envs: {
      ...(connectorResource.properties.extendedProperties?.envs ?? {}),
      AZURE_CLIENT_ID: identity.clientId,
      AZURE_TENANT_ID: identity.tenantId,
      AZURE_SUBSCRIPTION_ID: args.subscription,
    },
    toolsVisibleToMetaAgent: ["caldova-guided-alerts_close_guided_alert"],
  };
  const updateResponse = await fetch(`${endpoint}/api/v2/extendedAgent/connectors/${encodeURIComponent(connectorName)}`, {
    method: "PUT",
    headers,
    body: JSON.stringify(connectorResource),
  });
  if (!updateResponse.ok) fail(`Could not bind the guided alert connector to the agent identity (${updateResponse.status}).`);
}

function deleteConfigureArtifacts(srectl, endpoint) {
  const skills = listRemote(srectl, "skill", endpoint);
  const agents = listRemote(srectl, "agent", endpoint);
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "caldova-guided-clean-"));
  withSrectlEndpoint(srectl, endpoint, workspace, () => {
    if (agents.includes(customAgentName)) {
      run(srectl, ["agent", "delete", "--name", customAgentName, "--delete-local-files", "false", "--quiet"], { cwd: workspace });
    }
    if (skills.includes(skillName)) {
      run(srectl, ["skill", "delete", "--name", skillName, "--delete-local-files", "false", "--quiet"], { cwd: workspace });
    }
  });
}

function getAppInsights(az, args) {
  const resources = runJson(az, [
    "resource", "list",
    "--subscription", args.subscription,
    "--resource-group", args["resource-group"],
    "--resource-type", "Microsoft.Insights/components",
    "--output", "json",
  ]);
  if (resources.length !== 1) {
    fail(`Expected exactly one Application Insights component in '${args["resource-group"]}', found ${resources.length}.`);
  }
  return resources[0];
}

function deployAlert(az, args, appInsights, enabled) {
  const template = path.join(repoRoot, "data", "agent", "guided-course-recommendations", "alert.bicep");
  run(az, [
    "deployment", "group", "create",
    "--subscription", args.subscription,
    "--resource-group", args["resource-group"],
    "--name", "caldova-guided-recommendations-after-state",
    "--template-file", template,
    "--parameters",
    `location=${appInsights.location}`,
    `appInsightsId=${appInsights.id}`,
    `enabled=${enabled}`,
    "--output", "none",
  ]);
}

function getAlert(az, args) {
  return runJson(az, [
    "monitor", "scheduled-query", "show",
    "--subscription", args.subscription,
    "--resource-group", args["resource-group"],
    "--name", alertName,
    "--output", "json",
  ]);
}

function setAlertEnabled(az, args, enabled) {
  run(az, [
    "monitor", "scheduled-query", "update",
    "--subscription", args.subscription,
    "--resource-group", args["resource-group"],
    "--name", alertName,
    "--disabled", String(!enabled),
    "--output", "none",
  ]);
}

function responsePlanSpec(enabled) {
  return {
    incidentPlatform: "AzMonitor",
    priorities: [],
    titleContains: alertName,
    handlingAgent: customAgentName,
    maxAutomatedInvestigationAttempts: 2,
    mergeEnabled: false,
    isEnabled: enabled,
    azMonitorFilterSettings: {},
  };
}

function filterUrl(args, agentName) {
  return `https://management.azure.com/subscriptions/${args.subscription}/resourceGroups/${args["resource-group"]}/providers/Microsoft.App/agents/${agentName}/incidentFilters/${responsePlanName}?api-version=${agentApiVersion}`;
}

function putResponsePlan(az, args, enabled) {
  const encoded = Buffer.from(JSON.stringify(responsePlanSpec(enabled)), "utf8").toString("base64");
  const bodyPath = path.join(os.tmpdir(), `caldova-guided-filter-${process.pid}-${Date.now()}.json`);
  fs.writeFileSync(bodyPath, JSON.stringify({ properties: { value: encoded } }));
  try {
    run(az, ["rest", "--method", "put", "--url", filterUrl(args, args["preconfigured-agent"]), "--body", `@${bodyPath}`, "--output", "none"]);
  } finally {
    fs.rmSync(bodyPath, { force: true });
  }
}

function getResponsePlan(az, args, agentName, allowMissing = false) {
  try {
    const resource = runJson(az, ["rest", "--method", "get", "--url", filterUrl(args, agentName), "--output", "json"]);
    return {
      resource,
      spec: JSON.parse(Buffer.from(resource.properties.value, "base64").toString("utf8")),
    };
  } catch (error) {
    if (allowMissing && /404|not found|could not be found/i.test(error.message)) return null;
    throw error;
  }
}

function deleteConfigureResponsePlan(az, args) {
  const existing = getResponsePlan(az, args, args["configure-agent"], true);
  if (!existing) return;
  run(az, ["rest", "--method", "delete", "--url", filterUrl(args, args["configure-agent"]), "--output", "none"]);
}

function closeRecoveredAlerts(az, args) {
  const url = `/subscriptions/${args.subscription}/providers/Microsoft.AlertsManagement/alerts`;
  const alerts = runJson(az, [
    "rest", "--method", "get", "--url", url,
    "--url-parameters", `api-version=${alertsApiVersion}`,
    "--output", "json",
  ]);
  const resourceGroupSegment = `/resourceGroups/${args["resource-group"]}/`.toLowerCase();
  const recovered = (alerts.value ?? []).filter((alert) => {
    const essentials = alert?.properties?.essentials;
    return (essentials?.alertRule?.split("/")?.at(-1) === alertName) &&
      essentials?.targetResource?.toLowerCase().includes(resourceGroupSegment) &&
      essentials?.monitorCondition === "Resolved" &&
      essentials?.alertState !== "Closed";
  });
  for (const alert of recovered) {
    run(az, [
      "rest", "--method", "post", "--url", `${alert.id}/changeState`,
      "--url-parameters", `api-version=${alertsApiVersion}`, "newState=Closed",
      "--output", "none",
    ]);
  }
  return recovered.length;
}

function verify(az, azmcp, srectl, args, resources) {
  const expectedEnabled = args.expected === "enabled";
  const alert = getAlert(az, args);
  const preconfiguredPlan = getResponsePlan(az, args, args["preconfigured-agent"]);
  const configurePlan = getResponsePlan(az, args, args["configure-agent"], true);
  const preconfiguredSkills = listRemote(srectl, "skill", resources.preconfigured.properties.agentEndpoint);
  const preconfiguredAgents = listRemote(srectl, "agent", resources.preconfigured.properties.agentEndpoint);
  const guidedAgent = getRemoteDetail(srectl, "agent", customAgentName, resources.preconfigured.properties.agentEndpoint);
  const guidedSkill = getRemoteDetail(srectl, "skill", skillName, resources.preconfigured.properties.agentEndpoint);
  const configureSkills = listRemote(srectl, "skill", resources.configure.properties.agentEndpoint);
  const configureAgents = listRemote(srectl, "agent", resources.configure.properties.agentEndpoint);
  const preconfiguredConnectors = run(azmcp, [
    "sreagent", "connectors", "list",
    "--agent", args["preconfigured-agent"],
    "--subscription", args.subscription,
    "--resource-group", args["resource-group"],
  ]);
  const configureConnectors = run(azmcp, [
    "sreagent", "connectors", "list",
    "--agent", args["configure-agent"],
    "--subscription", args.subscription,
    "--resource-group", args["resource-group"],
  ]);
  const alertEnabled = Boolean(alert.enabled ?? alert.properties?.enabled);
  const query = alert.criteria?.allOf?.[0]?.query ?? alert.properties?.criteria?.allOf?.[0]?.query ?? "";
  const checks = {
    alertExists: alert.name === alertName,
    alertEnabled: alertEnabled === expectedEnabled,
    alertUsesProvenEvent: query.includes("CaldovaRecommendationsHealth") && query.includes("featureStatus"),
    alertAutoMitigates: Boolean(alert.autoMitigate ?? alert.properties?.autoMitigate),
    planExists: preconfiguredPlan.resource.name === responsePlanName,
    planEnabled: Boolean(preconfiguredPlan.spec.isEnabled) === expectedEnabled,
    planExactTitle: preconfiguredPlan.spec.titleContains === alertName,
    planExactAgent: preconfiguredPlan.spec.handlingAgent === customAgentName,
    planMergeDisabled: preconfiguredPlan.spec.mergeEnabled === false,
    preconfiguredSkillVisible: preconfiguredSkills.includes(skillName) && guidedSkill.includes(skillName),
    preconfiguredAgentVisible: preconfiguredAgents.includes(customAgentName) && guidedAgent.includes(customAgentName),
    agentAllowsOnlyGuidedSkill: guidedAgent.includes(skillName) &&
      !guidedAgent.includes("caldova-incident-triage") &&
      !guidedAgent.includes("incident-summary"),
    agentHasAzureCliTools: ["RunAzCliReadCommands", "RunAzCliWriteCommands", "GetAzCliHelp"]
      .every((tool) => guidedAgent.includes(tool)),
    guidedCloseConnectorVisible: preconfiguredConnectors.includes("caldova-guided-alerts"),
    configureCloseConnectorAbsent: !configureConnectors.includes("caldova-guided-alerts"),
    configurePlanAbsent: configurePlan === null,
    configureSkillAbsent: !configureSkills.includes(skillName),
    configureAgentAbsent: !configureAgents.includes(customAgentName),
  };
  const failures = Object.entries(checks).filter(([, passed]) => !passed).map(([name]) => name);
  if (failures.length > 0) {
    fail(`Guided AFTER-state verification failed: ${failures.join(", ")}.`);
  }
  return {
    checkedAtUtc: new Date().toISOString(),
    expectedState: args.expected,
    alert: { id: alert.id, name: alert.name, enabled: alertEnabled, autoMitigate: true },
    skill: { name: skillName, preconfiguredOnly: true, ownsTools: false },
    customAgent: { name: customAgentName, preconfiguredOnly: true, allowedSkill: skillName },
    responsePlan: { id: preconfiguredPlan.resource.id, name: responsePlanName, enabled: expectedEnabled, titleContains: alertName, handlingAgent: customAgentName },
    checks,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const az = findExecutable(os.platform() === "win32" ? "az.cmd" : "az");
  const azmcp = findAzmcp();
  const srectl = findExecutable(
    os.platform() === "win32" ? "srectl.exe" : "srectl",
    path.join(os.homedir(), ".dotnet", "tools", os.platform() === "win32" ? "srectl.exe" : "srectl"),
  );
  run(az, ["account", "set", "--subscription", args.subscription]);
  const resources = {
    preconfigured: getAgentResource(az, args, args["preconfigured-agent"]),
    configure: getAgentResource(az, args, args["configure-agent"]),
  };

  if (args.operation === "apply") {
    const appInsights = getAppInsights(az, args);
    deployAlert(az, args, appInsights, false);
    await applyGuidedConnector(az, azmcp, args, resources.preconfigured);
    applyPreconfiguredArtifacts(srectl, resources.preconfigured.properties.agentEndpoint, args["resource-group"]);
    putResponsePlan(az, args, false);
    deleteConfigureArtifacts(srectl, resources.configure.properties.agentEndpoint);
    deleteConfigureResponsePlan(az, args);
  } else if (args.operation === "enable") {
    setAlertEnabled(az, args, true);
    putResponsePlan(az, args, true);
  } else if (args.operation === "disable") {
    putResponsePlan(az, args, false);
    setAlertEnabled(az, args, false);
    closeRecoveredAlerts(az, args);
  }

  const result = verify(az, azmcp, srectl, args, resources);
  console.log(JSON.stringify(result, null, 2));
}

try {
  await main();
} catch (error) {
  console.error(`Guided recommendations configuration failed: ${error.message}`);
  process.exitCode = 1;
}
