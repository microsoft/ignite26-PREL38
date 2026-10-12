"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { URL } = require("node:url");
const { loadCatalog, getScenario } = require("./lib/catalog");
const { assertLearnerNumber, allowedAgents } = require("./lib/commands");
const { StateStore } = require("./lib/state-store");
const { createDriver } = require("./lib/driver");

const simulatorRoot = __dirname;
const repoRoot = path.resolve(simulatorRoot, "..");
const publicRoot = path.join(simulatorRoot, "public");
const activeOperations = new Map();

function json(response, status, body) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  response.end(JSON.stringify(body));
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 64 * 1024) reject(new Error("Request body exceeds 64 KB."));
    });
    request.on("end", () => {
      try { resolve(body ? JSON.parse(body) : {}); } catch { reject(new Error("Request body must be valid JSON.")); }
    });
    request.on("error", reject);
  });
}

function publicState(state) {
  return {
    learnerNumber: state.learnerNumber,
    status: state.status,
    phase: state.phase,
    progress: state.progress,
    ready: state.ready,
    active: Boolean(state.active),
    targetAgent: state.targetAgent,
    scenarioId: state.scenarioId,
    investigationUrl: state.investigationUrl,
    error: state.error,
    result: state.result,
    updatedAt: state.updatedAt
  };
}

function matchesStoredSelection(state, targetAgent, scenarioId) {
  return state.targetAgent === targetAgent && state.scenarioId === scenarioId;
}

function createSimulatorServer(options = {}) {
  const dataDirectory = options.dataDirectory || path.join(repoRoot, ".caldova");
  const store = options.store || new StateStore(dataDirectory);
  const driver = options.driver || createDriver(repoRoot, options.driverMode);

  async function runAction({ learnerNumber, targetAgent, scenario, action }) {
    const key = String(learnerNumber);
    const controller = new AbortController();
    let release = null;
    try {
      release = store.acquire(learnerNumber, action);
      activeOperations.set(key, controller);
      const starting = {
        check: ["checking", "Checking configuration", 8],
        start: ["injecting", "Starting scenario", 8],
        verify: ["checking_recovery", "Checking recovery", 12],
        fix: ["checking_recovery", "Restoring learner service", 12],
        reset: ["resetting", "Resetting learner environment", 8]
      }[action];
      const current = store.read(learnerNumber);
      store.transition(learnerNumber, starting[0], {
        phase: starting[1],
        progress: starting[2],
        ready: action === "check" ? false : current.ready,
        active: action === "start" ? true : Boolean(current.active),
        targetAgent,
        scenarioId: scenario.id,
        error: null
      });
      const result = await driver.run({
        scenario,
        action,
        learnerNumber,
        targetAgent,
        signal: controller.signal,
        onPhase: ({ message, progress }) => store.write({
          ...store.read(learnerNumber),
          phase: message,
          progress
        })
      });

      if (action === "check") {
        store.transition(learnerNumber, "ready", {
          phase: "Configuration ready",
          progress: 100,
          ready: true,
          investigationUrl: result.investigationUrl || null,
          result
        });
      } else if (action === "start") {
        if (result.alertExpected !== false) {
          store.transition(learnerNumber, "waiting_alert", {
            phase: "Alert detected",
            progress: 96,
            investigationUrl: result.investigationUrl || store.read(learnerNumber).investigationUrl,
            result
          });
        }
        store.transition(learnerNumber, "investigating", {
          phase: result.alertExpected === false
            ? "Manual investigation ready"
            : "Investigation in progress",
          progress: 100,
          investigationUrl: result.investigationUrl || store.read(learnerNumber).investigationUrl,
          result
        });
      } else if (action === "verify") {
        store.transition(learnerNumber, result.recovered ? "recovered" : "investigating", {
          phase: result.recovered ? "Recovery verified" : "Impact is still present",
          progress: 100,
          result
        });
      } else if (action === "fix") {
        store.transition(learnerNumber, result.recovered ? "recovered" : "investigating", {
          phase: result.recovered ? "Recovery verified" : "Impact is still present",
          progress: 100,
          result
        });
      } else if (action === "reset") {
        store.transition(learnerNumber, "idle", {
          phase: "Baseline restored",
          progress: 100,
          ready: false,
          active: false,
          targetAgent: null,
          scenarioId: null,
          investigationUrl: null,
          error: null,
          result
        });
      }
    } catch (error) {
      const current = store.read(learnerNumber);
      const next = controller.signal.aborted ? "cancelled" : "error";
      store.transition(learnerNumber, next, {
        phase: controller.signal.aborted ? "Operation cancelled" : "Action required",
        progress: current.progress,
        ready: false,
        error: error.message
      });
    } finally {
      activeOperations.delete(key);
      release?.();
    }
  }

  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, "http://localhost");
      if (request.method === "GET" && url.pathname === "/api/catalog") {
        json(response, 200, loadCatalog());
        return;
      }
      if (request.method === "GET" && url.pathname === "/api/status") {
        const learnerNumber = assertLearnerNumber(url.searchParams.get("learnerNumber"));
        json(response, 200, publicState(store.read(learnerNumber)));
        return;
      }
      if (request.method === "POST" && /^\/api\/(check|start|verify|fix|reset)$/.test(url.pathname)) {
        const action = url.pathname.split("/").pop();
        const body = await readBody(request);
        const learnerNumber = assertLearnerNumber(body.learnerNumber);
        if (!allowedAgents.has(body.targetAgent)) throw new Error("Choose either the Preconfigured or Configure agent.");
        const scenario = getScenario(body.scenarioId);
        const current = store.read(learnerNumber);
        if (action === "start" && (!current.ready || current.targetAgent !== body.targetAgent || current.scenarioId !== scenario.id)) {
          json(response, 409, { error: "Run Check configuration for this learner, scenario, and target agent before starting." });
          return;
        }
        if (["verify", "fix", "reset"].includes(action) &&
            (!current.active || !current.scenarioId || !current.targetAgent || !matchesStoredSelection(current, body.targetAgent, scenario.id))) {
          json(response, 409, {
            error: `The requested ${action} does not match the active learner exercise. Use learner ${learnerNumber}, scenario '${current.scenarioId || "none"}', and target agent '${current.targetAgent || "none"}', or start the checked exercise first.`
          });
          return;
        }
        if (activeOperations.has(String(learnerNumber))) {
          json(response, 409, { error: "An operation is already running for this learner. Wait for it to finish or cancel it." });
          return;
        }
        void runAction({ learnerNumber, targetAgent: body.targetAgent, scenario, action });
        json(response, 202, { accepted: true, action });
        return;
      }
      if (request.method === "POST" && url.pathname === "/api/cancel") {
        const body = await readBody(request);
        const learnerNumber = assertLearnerNumber(body.learnerNumber);
        const controller = activeOperations.get(String(learnerNumber));
        if (!controller) {
          json(response, 409, { error: "No operation is running for this learner." });
          return;
        }
        controller.abort();
        json(response, 202, { accepted: true, action: "cancel" });
        return;
      }

      if (request.method !== "GET") {
        json(response, 404, { error: "Route not found." });
        return;
      }
      const relative = url.pathname === "/" ? "index.html" : url.pathname.replace(/^\/+/, "");
      const file = path.resolve(publicRoot, relative);
      if (!file.startsWith(`${publicRoot}${path.sep}`) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
        json(response, 404, { error: "Page not found." });
        return;
      }
      const extension = path.extname(file);
      const contentType = extension === ".css" ? "text/css" : extension === ".js" ? "text/javascript" : "text/html";
      response.writeHead(200, { "content-type": `${contentType}; charset=utf-8` });
      fs.createReadStream(file).pipe(response);
    } catch (error) {
      json(response, 400, { error: error.message });
    }
  });
  return { server, store };
}

if (require.main === module) {
  const port = Number(process.env.PORT || 7070);
  const { server } = createSimulatorServer();
  server.listen(port, "127.0.0.1", () => {
    console.log(`Caldova simulator listening on http://127.0.0.1:${port} driver=${process.env.SIMULATOR_DRIVER || "azure"}`);
  });
}

module.exports = { createSimulatorServer, publicState, matchesStoredSelection };
