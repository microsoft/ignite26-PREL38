import { execFileSync } from "node:child_process";
import os from "node:os";

const tokenAudience = "https://azuresre.dev";
const pollIntervalMs = 10_000;
const creationTimeoutMs = 20 * 60_000;

function fail(message) {
  throw new Error(message);
}

function run(executable, args) {
  try {
    return execFileSync(executable, args, {
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
      shell: os.platform() === "win32" && executable.toLowerCase().endsWith(".cmd"),
    }).trim();
  } catch (error) {
    const detail = `${error.stdout || ""}${error.stderr || ""}${error.message || ""}`.trim();
    fail(`Command failed while configuring Live Reports: ${detail.slice(0, 2400)}`);
  }
}

async function runWhenAgentAvailable(executable, args) {
  const deadline = Date.now() + creationTimeoutMs;
  while (Date.now() < deadline) {
    try {
      return run(executable, args);
    } catch (error) {
      if (!error.message.includes("currently busy processing your request")) throw error;
      await wait(pollIntervalMs);
    }
  }
  fail("The SRE Agent remained busy for 20 minutes while starting Live Report authoring.");
}

async function fetchWithRetry(url, options) {
  let response;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      response = await fetch(url, {
        ...options,
        signal: AbortSignal.timeout(60_000),
      });
      if (response.status !== 429 && response.status < 500) return response;
    } catch (error) {
      if (attempt === 3) throw error;
    }
    if (attempt < 3) await wait(attempt * 2_000);
  }
  return response;
}

async function request(endpoint, token, method, relativePath, body) {
  const response = await fetchWithRetry(`${endpoint.replace(/\/$/, "")}${relativePath}`, {
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
    fail(`SRE Agent Live Report API ${method} ${relativePath} failed with HTTP ${response.status}: ${text.slice(0, 1200)}`);
  }
  if (!text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch {
    fail(`SRE Agent Live Report API ${method} ${relativePath} returned invalid JSON.`);
  }
}

function asArray(value) {
  if (Array.isArray(value)) return value;
  if (Array.isArray(value?.value)) return value.value;
  return [];
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function getReports(endpoint, token, agent) {
  return asArray(await request(
    endpoint,
    token,
    "GET",
    `/api/v1/agents/${encodeURIComponent(agent)}/reports`,
  ));
}

async function getReportState(endpoint, token, agent, expected) {
  const reports = await getReports(endpoint, token, agent);
  const matches = reports.filter((report) => report?.name === expected.name);
  if (matches.length > 1) fail(`Live Report '${expected.name}' exists more than once.`);
  if (matches.length === 0) return null;

  const report = matches[0];
  if (!report.id || !report.authoringThreadId || !Number.isInteger(report.currentVersionNumber) || report.currentVersionNumber < 1) {
    fail(`Live Report '${expected.name}' is missing its ID, authoring thread, or current version.`);
  }
  const encodedReportId = encodeURIComponent(report.id);
  const detail = await request(
    endpoint,
    token,
    "GET",
    `/api/v1/agents/${encodeURIComponent(agent)}/reports/${encodedReportId}`,
  );
  const versions = asArray(await request(
    endpoint,
    token,
    "GET",
    `/api/v1/agents/${encodeURIComponent(agent)}/reports/${encodedReportId}/versions`,
  ));
  if (detail?.report?.name !== expected.name || !detail?.currentHtml) {
    fail(`Live Report '${expected.name}' detail verification failed.`);
  }
  if (!versions.some((version) => version?.versionNumber === report.currentVersionNumber)) {
    fail(`Live Report '${expected.name}' current version was not returned by the versions API.`);
  }
  return {
    report,
    detail,
    versions,
    isCurrent: !expected.revisionMarker || detail.currentHtml.includes(expected.revisionMarker),
  };
}

async function getThreadUserId(endpoint, token, threadId) {
  const messages = asArray(await request(
    endpoint,
    token,
    "GET",
    `/api/v1/threads/${encodeURIComponent(threadId)}/messages`,
  ));
  const user = messages.find((message) => message?.author?.role === "User" && message?.author?.userId);
  if (!user) fail(`Live Report authoring thread '${threadId}' did not expose its user identity.`);
  return user.author.userId;
}

async function getPendingAuthoringQuestion(endpoint, token, threadId) {
  const messages = asArray(await request(
    endpoint,
    token,
    "GET",
    `/api/v1/threads/${encodeURIComponent(threadId)}/messages`,
  ));
  return [...messages].reverse().find((message) =>
    message?.userQuestion?.status === "Pending" &&
    message.userQuestion.question,
  )?.userQuestion ?? null;
}

async function approvePendingSaves(endpoint, token, threadId, reportName, userId, reportId = null) {
  const approvals = asArray(await request(
    endpoint,
    token,
    "GET",
    `/api/v1/approvals/${encodeURIComponent(threadId)}`,
  ));
  let approved = 0;
  for (const approval of approvals.filter((item) => item?.status === "Pending")) {
    if (approval?.display?.toolName !== "SaveReport") {
      fail(`Live Report authoring requested unexpected approval '${approval?.display?.toolName || approval?.title || approval?.id}'.`);
    }
    const argsParameter = approval.display.parameters?.find((parameter) => parameter?.name === "args");
    let saveArgs;
    try {
      saveArgs = JSON.parse(argsParameter?.value ?? "{}");
    } catch {
      fail(`Live Report SaveReport approval '${approval.id}' contains invalid arguments.`);
    }
    const exactName = saveArgs.name === reportName;
    const exactId = reportId !== null && saveArgs.reportId === reportId;
    const expectedTarget = reportId === null ? exactName : exactName && exactId;
    if (!expectedTarget) {
      fail(`Live Report approval targeted name '${saveArgs.name || "<missing>"}' and ID '${saveArgs.reportId || "<missing>"}', not '${reportName}' (${reportId || "new report"}).`);
    }
    await request(
      endpoint,
      token,
      "POST",
      `/api/v1/approvals/${encodeURIComponent(threadId)}/${encodeURIComponent(approval.id)}/decision`,
      {
        Status: "Approved",
        User: userId,
        Scope: approval.oboTokenScope,
        ApproveScope: "none",
      },
    );
    approved += 1;
  }
  return approved;
}

async function createReport({ azmcpPath, endpoint, token, target, report }) {
  const authoring = await request(
    endpoint,
    token,
    "POST",
    `/api/v1/agents/${encodeURIComponent(target.agent)}/reports/authoring-thread`,
  );
  const threadId = authoring?.authoringThreadId;
  if (!threadId) fail(`Live Report '${report.name}' authoring-thread creation returned no thread ID.`);

  await runWhenAgentAvailable(azmcpPath, [
    "sreagent", "threads", "send_message",
    "--thread-id", threadId,
    "--message", report.createPrompt
      .replaceAll("@@SUBSCRIPTION@@", target.subscription)
      .replaceAll("@@RG@@", target.resourceGroup),
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]);

  const userId = await getThreadUserId(endpoint, token, threadId);
  const deadline = Date.now() + creationTimeoutMs;
  let approved = 0;
  while (Date.now() < deadline) {
    approved += await approvePendingSaves(endpoint, token, threadId, report.name, userId);
    const existing = await getReportState(endpoint, token, target.agent, report);
    if (existing?.isCurrent) {
      return {
        ...existing.report,
        configurationAction: "created",
        configurationThreadId: threadId,
        approvalsGranted: approved,
      };
    }
    const question = await getPendingAuthoringQuestion(endpoint, token, threadId);
    if (question) {
      fail(`Live Report '${report.name}' authoring requires a product decision: ${question.question}`);
    }
    await wait(pollIntervalMs);
  }
  fail(`Live Report '${report.name}' was not created within ${creationTimeoutMs / 60_000} minutes. Authoring thread: ${threadId}.`);
}

async function updateReport({ azmcpPath, endpoint, token, target, report, current }) {
  const threadId = current.report.authoringThreadId;
  const originalId = current.report.id;
  const originalVersion = current.report.currentVersionNumber;
  if (!threadId) fail(`Live Report '${report.name}' has no authoring thread for an in-place update.`);

  await runWhenAgentAvailable(azmcpPath, [
    "sreagent", "threads", "send_message",
    "--thread-id", threadId,
    "--message", report.prompt
      .replaceAll("@@SUBSCRIPTION@@", target.subscription)
      .replaceAll("@@RG@@", target.resourceGroup),
    "--agent", target.agent,
    "--subscription", target.subscription,
    "--resource-group", target.resourceGroup,
  ]);

  const userId = await getThreadUserId(endpoint, token, threadId);
  const deadline = Date.now() + creationTimeoutMs;
  let approved = 0;
  while (Date.now() < deadline) {
    approved += await approvePendingSaves(endpoint, token, threadId, report.name, userId, originalId);
    const updated = await getReportState(endpoint, token, target.agent, report);
    if (updated) {
      if (updated.report.id !== originalId) {
        fail(`Live Report '${report.name}' changed ID from '${originalId}' to '${updated.report.id}'. Refusing to accept a replacement report.`);
      }
      if (updated.isCurrent && updated.report.currentVersionNumber > originalVersion) {
        return {
          ...updated.report,
          configurationAction: "updated",
          configurationThreadId: threadId,
          approvalsGranted: approved,
          previousVersionNumber: originalVersion,
        };
      }
    }
    const question = await getPendingAuthoringQuestion(endpoint, token, threadId);
    if (question) {
      fail(`Live Report '${report.name}' update requires a product decision: ${question.question}`);
    }
    await wait(pollIntervalMs);
  }
  fail(`Live Report '${report.name}' was not updated within ${creationTimeoutMs / 60_000} minutes. Authoring thread: ${threadId}.`);
}

export async function configureLiveReports({ azPath, azmcpPath, target, reports }) {
  if (!Array.isArray(reports) || reports.length !== 2) {
    fail("The preconfigured Caldova bundle must define exactly two Live Reports.");
  }
  const names = new Set();
  for (const report of reports) {
    if (!report?.name || !report?.createPrompt || !report?.prompt || !report?.revisionMarker) {
      fail("Every Live Report requires name, createPrompt, prompt, and revisionMarker.");
    }
    if (names.has(report.name)) fail(`Duplicate Live Report '${report.name}'.`);
    names.add(report.name);
  }

  const endpoint = target.resource?.properties?.agentEndpoint;
  if (!endpoint) fail(`SRE Agent '${target.agent}' has no data-plane endpoint.`);
  const token = run(azPath, [
    "account", "get-access-token",
    "--resource", tokenAudience,
    "--query", "accessToken",
    "--output", "tsv",
  ]);

  const configured = [];
  for (const report of reports) {
    const existing = await getReportState(endpoint, token, target.agent, report);
    if (!existing) {
      configured.push(await createReport({ azmcpPath, endpoint, token, target, report }));
    } else if (existing.isCurrent) {
      configured.push({
        ...existing.report,
        configurationAction: "unchanged",
        configurationThreadId: existing.report.authoringThreadId,
        approvalsGranted: 0,
      });
    } else {
      configured.push(await updateReport({ azmcpPath, endpoint, token, target, report, current: existing }));
    }
  }
  return configured;
}
