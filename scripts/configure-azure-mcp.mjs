import { execFileSync } from "node:child_process";
import fs from "node:fs";

const apiVersion = "2025-05-01-preview";
const armAudience = "https://management.azure.com";
const dataAudience = "https://azuresre.ai";

function getAccessToken(azPath, audience) {
  return execFileSync(
    azPath,
    ["account", "get-access-token", "--resource", audience, "--query", "accessToken", "-o", "tsv"],
    {
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
      shell: process.platform === "win32" && azPath.toLowerCase().endsWith(".cmd"),
    },
  ).trim();
}

async function request(azPath, method, url, audience, body) {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${getAccessToken(azPath, audience)}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(240_000),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${method} ${new URL(url).pathname} failed (HTTP ${response.status}): ${text.slice(0, 1200)}`);
  }
  return text ? JSON.parse(text) : null;
}

export function buildAzureMcpConnector(agentResource, subscription, manifestPath) {
  const identities = Object.entries(agentResource?.identity?.userAssignedIdentities ?? {});
  if (identities.length !== 1) {
    throw new Error("Azure MCP requires exactly one existing user-assigned identity on the SRE Agent. No IAM changes were made.");
  }

  const [identity, details] = identities[0];
  const tenant = agentResource?.identity?.tenantId;
  if (!details?.clientId || !tenant) {
    throw new Error("The SRE Agent user-assigned identity is missing clientId or tenantId. Wait for identity provisioning and retry.");
  }

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const template = manifest.connectors?.find((connector) => connector.name === "azure-mcp");
  if (!template) {
    throw new Error(`${manifestPath} does not define the azure-mcp connector.`);
  }

  const properties = structuredClone(template);
  properties.identity = identity;
  properties.extendedProperties.envs = {
    ...properties.extendedProperties.envs,
    AZURE_SUBSCRIPTION_ID: subscription,
    AZURE_CLIENT_ID: details.clientId,
    AZURE_TENANT_ID: tenant,
  };
  return { name: properties.name, properties };
}

export async function configureAzureMcp({
  azPath,
  subscription,
  resourceGroup,
  agent,
  agentResource,
  manifestPath,
}) {
  const agentUrl = `${armAudience}/subscriptions/${encodeURIComponent(subscription)}/resourceGroups/${encodeURIComponent(resourceGroup)}/providers/Microsoft.App/agents/${encodeURIComponent(agent)}`;
  const endpoint = agentResource?.properties?.agentEndpoint;
  if (!endpoint || new URL(endpoint).protocol !== "https:") {
    throw new Error(`SRE Agent '${agent}' did not return an HTTPS data-plane endpoint. Confirm provisioning succeeded and retry.`);
  }

  const definition = buildAzureMcpConnector(agentResource, subscription, manifestPath);
  const connectorUrl = `${agentUrl}/connectors/${definition.name}?api-version=${apiVersion}`;
  const testUrl = `${endpoint.replace(/\/$/, "")}/api/v2/extendedAgent/connectors/${definition.name}/testconnection`;

  const tested = await request(azPath, "POST", testUrl, dataAudience, definition);
  if (tested?.success !== true || !Array.isArray(tested.tools) ||
      !tested.tools.some((tool) => tool.name === "azure" || tool.name === "azure-mcp_azure")) {
    throw new Error(`Azure MCP connection test failed for '${agent}': ${tested?.errorMessage || "azure dispatcher tool was not discovered"}. Confirm agent-side npm access and managed-identity RBAC.`);
  }

  await request(azPath, "PUT", connectorUrl, armAudience, { properties: definition.properties });
  const saved = await request(azPath, "GET", connectorUrl, armAudience);
  if (saved?.properties?.provisioningState !== "Succeeded" ||
      saved?.properties?.identity?.toLowerCase() !== definition.properties.identity.toLowerCase() ||
      !saved?.properties?.extendedProperties?.toolsVisibleToMetaAgent?.includes("azure-mcp_azure")) {
    throw new Error(`Azure MCP persisted verification failed for '${agent}' (provisioning: ${saved?.properties?.provisioningState ?? "unknown"}). Inspect Builder > Connectors.`);
  }

  console.log(`Read-only Azure connector configured for ${agent}: ${tested.tools.length} tool(s), managed identity retained.`);
}
