import { execFileSync } from "node:child_process";
import { URL } from "node:url";

function fail(message) {
  throw new Error(message);
}

function runAz(azPath, args) {
  try {
    return execFileSync(azPath, args, {
      encoding: "utf8",
      maxBuffer: 8 * 1024 * 1024,
      shell: process.platform === "win32" && azPath.toLowerCase().endsWith(".cmd"),
    }).trim();
  } catch (error) {
    const detail = `${error.stdout || ""}${error.stderr || ""}${error.message || ""}`.trim();
    fail(`Azure CLI command failed while configuring GitHub: ${detail.slice(0, 1600)}`);
  }
}

async function request(endpoint, token, method, relativePath, body) {
  const response = await fetch(`${endpoint.replace(/\/$/, "")}${relativePath}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(60_000),
  });
  const text = await response.text();
  if (!response.ok) {
    fail(`SRE Agent GitHub API ${method} ${relativePath} failed with HTTP ${response.status}: ${text.slice(0, 800)}`);
  }
  if (!text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch {
    fail(`SRE Agent GitHub API ${method} ${relativePath} returned invalid JSON.`);
  }
}

function authPayload() {
  const clientId = process.env.CALDOVA_GITHUB_APP_CLIENT_ID;
  const privateKeySecretUri = process.env.CALDOVA_GITHUB_APP_PRIVATE_KEY_SECRET_URI;
  const keyVaultManagedIdentityId = process.env.CALDOVA_GITHUB_APP_KEY_VAULT_IDENTITY_ID;
  if (clientId || privateKeySecretUri || keyVaultManagedIdentityId) {
    if (!clientId || !privateKeySecretUri || !keyVaultManagedIdentityId) {
      fail("GitHub App mode requires CALDOVA_GITHUB_APP_CLIENT_ID, CALDOVA_GITHUB_APP_PRIVATE_KEY_SECRET_URI, and CALDOVA_GITHUB_APP_KEY_VAULT_IDENTITY_ID.");
    }
    return {
      authType: "GitHubApp",
      clientId,
      privateKeySecretUri,
      keyVaultManagedIdentityId,
    };
  }

  const pat = process.env.CALDOVA_GITHUB_PAT;
  if (!pat) {
    fail("Preconfigured GitHub access requires platform-injected GitHub App references or CALDOVA_GITHUB_PAT. Never use attendee OAuth or store the credential in a file.");
  }
  return { AuthType: "Pat", Pat: pat };
}

function collectionContains(collection, predicate) {
  const values = Array.isArray(collection)
    ? collection
    : collection?.value ?? collection?.values ?? collection?.items ?? collection?.repos ?? collection?.domains ?? [];
  return Array.isArray(values) && values.some(predicate);
}

export async function configurePreconfiguredGitHub({
  azPath,
  preconfiguredResource,
  configureResource,
  repositoryUrl,
}) {
  const parsed = new URL(repositoryUrl);
  if (parsed.protocol !== "https:" || parsed.hostname !== "github.com") {
    fail("Learner repository URL must be an HTTPS github.com URL.");
  }
  const pathParts = parsed.pathname.replace(/^\/|\/$/g, "").split("/");
  if (pathParts.length !== 2) fail("Learner repository URL must be https://github.com/<owner>/<repo>.");
  const [owner, repository] = pathParts;
  const repoName = `caldova-${owner}-${repository}`.replace(/[^A-Za-z0-9_-]/g, "-");
  const token = runAz(azPath, [
    "account", "get-access-token",
    "--resource", "https://azuresre.dev",
    "--query", "accessToken",
    "--output", "tsv",
  ]);
  const preconfiguredEndpoint = preconfiguredResource?.properties?.agentEndpoint;
  const configureEndpoint = configureResource?.properties?.agentEndpoint;
  if (!preconfiguredEndpoint || !configureEndpoint) fail("Both agent endpoints are required for GitHub configuration.");

  await request(preconfiguredEndpoint, token, "PUT", "/api/v2/github/domains/github_com", authPayload());
  await request(preconfiguredEndpoint, token, "PUT", `/api/v2/repos/${encodeURIComponent(repoName)}`, {
    name: repoName,
    type: "CodeRepo",
    properties: {
      url: repositoryUrl,
      type: "GitHub",
      branch: "main",
      description: "Isolated writable Caldova learner repository for source, commit, PR, and workflow evidence.",
    },
  });

  const domains = await request(preconfiguredEndpoint, token, "GET", "/api/v2/github/domains");
  const repos = await request(preconfiguredEndpoint, token, "GET", "/api/v2/repos");
  const test = await request(preconfiguredEndpoint, token, "POST", `/api/v2/repos/${encodeURIComponent(repoName)}/test`);
  if (!collectionContains(domains, (item) => item?.name === "github_com" || item?.name === "github.com" || item?.domain === "github.com")) {
    fail("Preconfigured GitHub domain verification did not return github.com.");
  }
  if (!collectionContains(repos, (item) => item?.name === repoName || item?.properties?.url === repositoryUrl)) {
    fail("Preconfigured repository verification did not return the isolated learner repository.");
  }
  if (test?.success === false || test?.isSuccessful === false || test?.status === "Failed" || test?.status === "Error") {
    fail(`Preconfigured repository connection test failed: ${test?.message || test?.error || "unknown error"}`);
  }

  const configureDomains = await request(configureEndpoint, token, "GET", "/api/v2/github/domains");
  const configureRepos = await request(configureEndpoint, token, "GET", "/api/v2/repos");
  if (collectionContains(configureDomains, () => true) || collectionContains(configureRepos, () => true)) {
    fail("Configure Agent already has GitHub access. Remove it so the learner performs the documented OAuth flow.");
  }
  return { repoName, repositoryUrl };
}
