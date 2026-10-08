"use strict";

const elements = {
  learner: document.querySelector("#learner-number"),
  scenario: document.querySelector("#scenario"),
  name: document.querySelector("#scenario-name"),
  description: document.querySelector("#scenario-description"),
  injection: document.querySelector("#injection-time"),
  detection: document.querySelector("#detection-time"),
  badge: document.querySelector("#status-badge"),
  readiness: document.querySelector("#readiness-copy"),
  phase: document.querySelector("#phase"),
  progress: document.querySelector("#progress-bar"),
  progressTrack: document.querySelector(".progress-track"),
  updated: document.querySelector("#updated-at"),
  guidance: document.querySelector("#guidance-copy"),
  investigation: document.querySelector("#investigation-link"),
  errorRegion: document.querySelector("#error-region"),
  error: document.querySelector("#error-copy"),
  success: document.querySelector("#success-region"),
  check: document.querySelector("#check-button"),
  start: document.querySelector("#start-button"),
  recovery: document.querySelector("#recovery-button"),
  cancel: document.querySelector("#cancel-button"),
  reset: document.querySelector("#reset-button"),
  resetConfirmation: document.querySelector("#reset-confirmation"),
  confirmReset: document.querySelector("#confirm-reset-button"),
  keep: document.querySelector("#keep-button")
};
const agentControls = [...document.querySelectorAll('input[name="target-agent"]')];

let catalog = [];
let pollTimer = null;

function targetAgent() {
  return document.querySelector('input[name="target-agent"]:checked')?.value || "preconfigured";
}

function selection() {
  return {
    learnerNumber: Number(elements.learner.value),
    targetAgent: targetAgent(),
    scenarioId: elements.scenario.value
  };
}

async function request(path, options = {}) {
  const response = await fetch(path, {
    headers: { "content-type": "application/json" },
    ...options
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || `Request failed with HTTP ${response.status}.`);
  return body;
}

function selectedScenario() {
  return catalog.find((scenario) => scenario.id === elements.scenario.value);
}

function renderScenario() {
  const scenario = selectedScenario();
  if (!scenario) {
    elements.name.textContent = "No scenarios available";
    elements.description.textContent = "The scenario catalog is empty. Restore simulator/scenarios.json and reload.";
    return;
  }
  elements.name.textContent = scenario.learner.name;
  elements.description.textContent = scenario.learner.description;
  elements.injection.textContent = scenario.learner.estimatedInjection;
  elements.detection.textContent = scenario.learner.estimatedDetection;
  invalidateReadiness();
}

function isBusy(status) {
  return ["checking", "injecting", "waiting_alert", "checking_recovery", "resetting"].includes(status);
}

function statusLabel(status) {
  return {
    idle: "Not checked",
    checking: "Checking",
    ready: "Ready",
    injecting: "Starting",
    waiting_alert: "Waiting for alert",
    investigating: "Investigate",
    checking_recovery: "Checking recovery",
    recovered: "Recovered",
    resetting: "Resetting",
    error: "Needs attention",
    cancelled: "Cancelled"
  }[status] || status;
}

function renderState(state) {
  const busy = isBusy(state.status);
  const exerciseActive = busy || state.active;
  const matchesSelection = state.targetAgent === targetAgent() && state.scenarioId === elements.scenario.value;
  elements.badge.dataset.state = state.status;
  elements.badge.textContent = statusLabel(state.status);
  elements.phase.textContent = state.phase;
  elements.progress.style.transform = `scaleX(${Math.max(0, Math.min(100, state.progress || 0)) / 100})`;
  elements.progressTrack.setAttribute("aria-valuenow", String(state.progress || 0));
  elements.updated.textContent = state.updatedAt
    ? `Updated ${new Date(state.updatedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}`
    : "No activity yet.";

  elements.check.disabled = busy;
  elements.learner.disabled = exerciseActive;
  elements.scenario.disabled = exerciseActive;
  agentControls.forEach((input) => { input.disabled = exerciseActive; });
  elements.start.disabled = busy || !state.ready || !matchesSelection || state.status !== "ready";
  elements.recovery.disabled = busy || !["investigating", "recovered"].includes(state.status);
  elements.reset.disabled = busy || state.status === "idle";
  elements.cancel.hidden = !busy;
  elements.success.hidden = state.status !== "recovered";
  elements.errorRegion.hidden = !state.error;
  elements.error.textContent = state.error || "";

  const checkText = state.ready && matchesSelection
    ? `Ready. ${state.result?.agentName || "The selected agent"} owns the required response plan.`
    : state.status === "checking" ? "Validating the learner environment, alert, selected agent, and response plan." :
      "Check the selected learner environment before starting.";
  elements.readiness.textContent = checkText;

  if (state.investigationUrl) {
    elements.investigation.href = state.investigationUrl;
    elements.investigation.hidden = false;
  } else {
    elements.investigation.hidden = true;
  }

  const scenario = selectedScenario();
  elements.guidance.textContent =
    state.status === "ready" ? "Start is unlocked. Injection and detection can take several minutes." :
    state.status === "investigating" ? scenario?.learner.recoveryGuidance || "Investigate the active alert, then check recovery." :
    state.status === "recovered" ? "Recovery is verified. Reset to restore baseline ownership and clear the exercise." :
    state.status === "error" ? "Follow the action in the error message, then check configuration or reset." :
    state.status === "cancelled" ? "The operation stopped before completion. Reset before starting again." :
    busy ? "Keep this page open. The current phase updates as each real operation completes." :
    "Complete the configuration check to unlock Start.";

  if (busy) startPolling(); else stopPolling();
}

function invalidateReadiness() {
  elements.start.disabled = true;
  elements.readiness.textContent = "Selection changed. Check configuration again before starting.";
  elements.resetConfirmation.hidden = true;
}

async function refreshStatus() {
  try {
    const learnerNumber = Number(elements.learner.value);
    if (!Number.isInteger(learnerNumber) || learnerNumber < 1 || learnerNumber > 999) {
      throw new Error("Enter a learner number from 1 to 999.");
    }
    renderState(await request(`/api/status?learnerNumber=${learnerNumber}`));
  } catch (error) {
    elements.errorRegion.hidden = false;
    elements.error.textContent = error.message;
    stopPolling();
  }
}

function startPolling() {
  if (pollTimer) return;
  pollTimer = setInterval(refreshStatus, 750);
}

function stopPolling() {
  if (!pollTimer) return;
  clearInterval(pollTimer);
  pollTimer = null;
}

async function action(name) {
  elements.errorRegion.hidden = true;
  try {
    await request(`/api/${name}`, { method: "POST", body: JSON.stringify(selection()) });
    startPolling();
    await refreshStatus();
  } catch (error) {
    elements.errorRegion.hidden = false;
    elements.error.textContent = error.message;
  }
}

async function initialize() {
  try {
    const learnerFromUrl = Number(new URLSearchParams(window.location.search).get("learnerNumber"));
    if (Number.isInteger(learnerFromUrl) && learnerFromUrl >= 1 && learnerFromUrl <= 999) {
      elements.learner.value = String(learnerFromUrl);
    }
    const data = await request("/api/catalog");
    catalog = data.scenarios || [];
    elements.scenario.replaceChildren(...catalog.map((scenario) => {
      const option = document.createElement("option");
      option.value = scenario.id;
      option.textContent = scenario.learner.name;
      return option;
    }));
    renderScenario();
    await refreshStatus();
  } catch (error) {
    elements.name.textContent = "Simulator unavailable";
    elements.description.textContent = "The checked-in scenario catalog or local simulator service could not be loaded.";
    elements.errorRegion.hidden = false;
    elements.error.textContent = `${error.message} Restart with: npm --prefix simulator start`;
  }
}

elements.check.addEventListener("click", () => action("check"));
elements.start.addEventListener("click", () => action("start"));
elements.recovery.addEventListener("click", () => action("verify"));
elements.cancel.addEventListener("click", () => action("cancel"));
elements.reset.addEventListener("click", () => { elements.resetConfirmation.hidden = false; elements.confirmReset.focus(); });
elements.confirmReset.addEventListener("click", () => { elements.resetConfirmation.hidden = true; action("reset"); });
elements.keep.addEventListener("click", () => { elements.resetConfirmation.hidden = true; elements.reset.focus(); });
elements.scenario.addEventListener("change", renderScenario);
elements.learner.addEventListener("change", () => { invalidateReadiness(); refreshStatus(); });
agentControls.forEach((input) => input.addEventListener("change", invalidateReadiness));

initialize();
