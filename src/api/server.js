"use strict";

const express = require("express");
const { createStore } = require("./lib/store");
const { loadLatencyProfile } = require("./lib/latency-profile-loader");
const { getRecommendationsHealth, getRecommendationsMode } = require("./lib/recommendations");
const { getQuizAvailability, getQuizMode } = require("./lib/quiz-mode");

const PORT = Number(process.env.PORT || 8080);
const SERVICE = "caldova-api";
let telemetryClient = null;

if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  const applicationInsights = require("applicationinsights");
  applicationInsights
    .setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING)
    .setAutoCollectConsole(true, true)
    .start();
  telemetryClient = applicationInsights.defaultClient;
  const roleKey = telemetryClient?.context?.keys?.cloudRole;
  if (roleKey) telemetryClient.context.tags[roleKey] = SERVICE;
}

const store = createStore();
const latencyProfile = loadLatencyProfile();
const app = express();

app.disable("x-powered-by");
app.use(express.json({ limit: "64kb" }));
app.use((req, res, next) => {
  const started = process.hrtime.bigint();
  res.on("finish", () => {
    const elapsedMs = Math.round(Number(process.hrtime.bigint() - started) / 1e6);
    console.log(`caldova_request service=${SERVICE} method=${req.method} path=${req.path} status=${res.statusCode} ms=${elapsedMs}`);
    if (latencyProfile.appliesTo(req.path) && telemetryClient) {
      telemetryClient.trackMetric({
        name: "CaldovaQuizApiResponseLatencyMs",
        value: elapsedMs,
        properties: {
          route: req.path,
          statusCode: String(res.statusCode)
        }
      });
    }
  });
  next();
});
app.use(asyncRoute(async (req, _res, next) => {
  if (latencyProfile.appliesTo(req.path)) {
    await latencyProfile.beforeRequest();
  }
  next();
}));

function asyncRoute(handler) {
  return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
}

app.get("/health", asyncRoute(async (_req, res) => {
  const database = await store.health();
  res.json({ status: "ok", service: SERVICE, dataMode: store.mode, database, timestamp: new Date().toISOString() });
}));

app.get("/ready", asyncRoute(async (_req, res) => {
  await store.health();
  res.json({ status: "ready", service: SERVICE });
}));

app.get("/summary", asyncRoute(async (_req, res) => {
  res.json({ generatedAt: new Date().toISOString(), ...(await store.summary()) });
}));

app.get("/courses", asyncRoute(async (_req, res) => {
  const courses = await store.courses();
  res.json({ count: courses.length, courses });
}));

app.get("/courses/:id", asyncRoute(async (req, res) => {
  const course = await store.course(req.params.id.toUpperCase());
  if (!course) return res.status(404).json({ error: "course_not_found", id: req.params.id });
  res.json(course);
}));

app.get("/recommendations/health", (req, res) => {
  const health = getRecommendationsHealth();
  console.log(`caldova_feature_status feature=course_recommendations status=${health.body.status} source=configuration`);
  telemetryClient?.trackEvent({
    name: "CaldovaRecommendationsHealth",
    properties: {
      feature: health.body.feature,
      featureStatus: health.body.status,
      route: req.path
    }
  });
  res.status(health.statusCode).json(health.body);
});

app.get("/assessments/:id", asyncRoute(async (req, res) => {
  const assessment = await store.assessment(req.params.id.toUpperCase());
  if (!assessment) return res.status(404).json({ error: "assessment_not_found", id: req.params.id });
  res.json(assessment);
}));

app.get("/quiz/:id", asyncRoute(async (req, res) => {
  const availability = getQuizAvailability();
  if (!availability.available) {
    console.log("caldova_quiz_availability status=unavailable source=configuration");
    return res.status(availability.statusCode).json(availability.body);
  }
  const quiz = await store.quiz(req.params.id.toUpperCase());
  if (!quiz) return res.status(404).json({ error: "assessment_not_found", id: req.params.id });
  res.json(quiz);
}));

app.post("/quiz/:id/submit", asyncRoute(async (req, res) => {
  const learnerId = typeof req.body?.learnerId === "string" ? req.body.learnerId.trim() : "";
  const answers = Array.isArray(req.body?.answers) ? req.body.answers.map(Number) : [];
  if (!learnerId || answers.some((answer) => !Number.isInteger(answer))) {
    return res.status(400).json({ error: "invalid_submission", detail: "learnerId and integer answers are required." });
  }
  const result = await store.submit(req.params.id.toUpperCase(), learnerId, answers);
  if (!result) return res.status(404).json({ error: "assessment_not_found", id: req.params.id });
  res.status(201).json(result);
}));

app.get("/grades/learner/:id", asyncRoute(async (req, res) => {
  res.json(await store.grades(req.params.id));
}));

app.get("/exports/recent", asyncRoute(async (_req, res) => {
  const exports = await store.exports();
  res.json({ count: exports.length, exports });
}));

app.use((req, res) => res.status(404).json({ error: "route_not_found", path: req.path }));
app.use((error, _req, res, _next) => {
  console.error(`caldova_request_failed service=${SERVICE} message=${JSON.stringify(error.message)}`);
  res.status(503).json({ error: "service_unavailable", detail: "Caldova could not complete the request. Check database connectivity and service logs." });
});

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`caldova_service_started service=${SERVICE} port=${PORT} data_mode=${store.mode} latency_profile=${latencyProfile.name} recommendations_mode=${getRecommendationsMode()} quiz_mode=${getQuizMode()}`);
});

async function shutdown(signal) {
  console.log(`caldova_service_stopping service=${SERVICE} signal=${signal}`);
  server.close(async () => {
    await store.close();
    process.exit(0);
  });
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
