"use strict";

const express = require("express");
const applicationInsights = require("applicationinsights");

const PORT = Number(process.env.PORT || 8080);
const SERVICE = "caldova-portal";
const API_BASE_URL = (process.env.CALDOVA_API_BASE_URL || "http://localhost:8081").replace(/\/$/, "");

if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  applicationInsights
    .setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING)
    .setAutoCollectConsole(true, true)
    .start();
  const roleKey = applicationInsights.defaultClient?.context?.keys?.cloudRole;
  if (roleKey) applicationInsights.defaultClient.context.tags[roleKey] = SERVICE;
}

const app = express();

app.disable("x-powered-by");
app.use(express.json({ limit: "64kb" }));
app.use((req, res, next) => {
  const started = process.hrtime.bigint();
  res.on("finish", () => {
    const elapsedMs = Math.round(Number(process.hrtime.bigint() - started) / 1e6);
    console.log(`caldova_request service=${SERVICE} method=${req.method} path=${req.path} status=${res.statusCode} ms=${elapsedMs}`);
  });
  next();
});

async function apiRequest(path, options = {}, timeoutMs = 8000) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: { "content-type": "application/json", ...(options.headers || {}) },
    signal: AbortSignal.timeout(timeoutMs)
  });
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = { error: "invalid_upstream_response" };
  }
  if (!response.ok) {
    const error = new Error(`Caldova API returned HTTP ${response.status}`);
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: SERVICE, timestamp: new Date().toISOString() });
});

app.get("/ready", async (_req, res) => {
  try {
    await apiRequest("/ready", {}, 4000);
    res.json({ status: "ready", service: SERVICE });
  } catch (error) {
    console.error(`caldova_dependency_failed service=${SERVICE} dependency=api message=${JSON.stringify(error.message)}`);
    res.status(503).json({ status: "degraded", service: SERVICE, dependency: "api" });
  }
});

for (const path of ["/summary", "/courses", "/exports/recent"]) {
  app.get(`/api${path}`, async (_req, res) => {
    try {
      res.json(await apiRequest(path));
    } catch (error) {
      console.error(`caldova_request_failed service=${SERVICE} upstream_path=${path} message=${JSON.stringify(error.message)}`);
      res.status(502).json({ error: "caldova_service_unavailable", detail: "Caldova data is temporarily unavailable." });
    }
  });
}

app.get("/api/courses/:id", async (req, res) => {
  try {
    res.json(await apiRequest(`/courses/${encodeURIComponent(req.params.id)}`));
  } catch (error) {
    res.status(error.status === 404 ? 404 : 502).json(error.body || { error: "caldova_service_unavailable" });
  }
});

app.get("/api/recommendations/health", async (_req, res) => {
  try {
    res.json(await apiRequest("/recommendations/health"));
  } catch (error) {
    const status = error.status === 503 ? 503 : 502;
    res.status(status).json(error.body || {
      status: "unknown",
      feature: "course_recommendations",
      message: "Course recommendations status could not be determined."
    });
  }
});

app.get("/api/assessments/:id", async (req, res) => {
  try {
    res.json(await apiRequest(`/assessments/${encodeURIComponent(req.params.id)}`));
  } catch (error) {
    res.status(error.status === 404 ? 404 : 502).json(error.body || { error: "caldova_service_unavailable" });
  }
});

app.get("/api/quiz/:id", async (req, res) => {
  try {
    const quiz = await apiRequest(`/quiz/${encodeURIComponent(req.params.id)}`);
    console.log(`caldova_quiz_launch status=ok assessment=${JSON.stringify(req.params.id)}`);
    res.json(quiz);
  } catch (error) {
    console.error(`caldova_quiz_launch_failed assessment=${JSON.stringify(req.params.id)} message=${JSON.stringify(error.message)}`);
    res.status(error.status === 404 ? 404 : 502).json(error.body || { error: "quiz_launch_failed" });
  }
});

app.post("/api/quiz/:id/submit", async (req, res) => {
  try {
    const result = await apiRequest(`/quiz/${encodeURIComponent(req.params.id)}/submit`, {
      method: "POST",
      body: JSON.stringify(req.body)
    });
    res.status(201).json(result);
  } catch (error) {
    res.status(error.status === 400 || error.status === 404 ? error.status : 502)
      .json(error.body || { error: "quiz_submission_failed" });
  }
});

app.get("/api/grades/learner/:id", async (req, res) => {
  try {
    res.json(await apiRequest(`/grades/learner/${encodeURIComponent(req.params.id)}`));
  } catch (error) {
    res.status(502).json({ error: "gradebook_unavailable" });
  }
});

app.get("/", (_req, res) => {
  res.type("html").send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Caldova learning workspace</title>
  <style>
    :root { color-scheme: light; font-family: Aptos, "Segoe UI", ui-sans-serif, system-ui, sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #f4f7fb; color: #152238; }
    header { background: linear-gradient(120deg, #123d73, #0e7490); color: white; padding: 28px max(24px, calc((100vw - 1100px) / 2)); }
    header h1 { margin: 0 0 6px; font-size: 28px; }
    header p { margin: 0; color: #d9f2ff; }
    main { max-width: 1100px; margin: 28px auto; padding: 0 24px 40px; }
    .status, .panel, .card, .feature { background: white; border: 1px solid #dce5ef; border-radius: 12px; box-shadow: 0 8px 24px rgba(21,34,56,.06); }
    .status { display: flex; gap: 24px; padding: 16px 20px; margin-bottom: 22px; }
    .metric strong { display: block; font-size: 24px; color: #123d73; }
    .metric span { color: #607086; font-size: 13px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 16px; }
    .card { padding: 18px; }
    .card h2 { margin: 0 0 8px; font-size: 18px; }
    .meta { color: #607086; font-size: 13px; min-height: 38px; }
    button { background: #0e7490; border: 0; border-radius: 7px; color: white; cursor: pointer; font-weight: 650; padding: 9px 13px; }
    button:disabled { cursor: wait; opacity: .65; }
    .panel { margin-top: 20px; padding: 20px; display: none; }
    .feature { align-items: center; display: flex; gap: 16px; justify-content: space-between; margin-bottom: 22px; padding: 16px 20px; }
    .feature h2 { font-size: 17px; margin: 0 0 4px; }
    .feature p { color: #607086; margin: 0; }
    .feature-status { align-items: center; display: flex; gap: 10px; white-space: nowrap; }
    .feature-badge { background: #eef4f8; border-radius: 999px; color: #385067; font-size: 12px; font-weight: 700; padding: 5px 9px; text-transform: uppercase; }
    .feature[data-state="degraded"] { border-color: #e8bf74; }
    .feature[data-state="degraded"] .feature-badge { background: #fff3d6; color: #8a5700; }
    .feature[data-state="available"] .feature-badge { background: #dff7ec; color: #12633f; }
    .question { border-top: 1px solid #e7edf4; padding: 14px 0; }
    .error { color: #a51d2d; font-weight: 650; }
  </style>
</head>
<body>
  <header><h1>Caldova learning workspace</h1><p>Courses, assessments, progress, and reporting in one operational view.</p></header>
  <main>
    <section id="status" class="status" aria-live="polite">Loading Caldova baseline…</section>
    <section id="recommendations" class="feature" data-state="loading" aria-live="polite">
      <div><h2>Course recommendations</h2><p id="recommendations-message">Checking personalized recommendations…</p></div>
      <div class="feature-status"><span id="recommendations-badge" class="feature-badge">Checking</span><button id="recommendations-retry" type="button">Retry</button></div>
    </section>
    <section id="courses" class="grid" aria-live="polite"></section>
    <section id="quiz" class="panel" aria-live="polite"></section>
  </main>
  <script>
    const assessmentByCourse = { "OPS-201": "OPS-201-M1", "DATA-215": "DATA-215-M1", "BUS-140": "BUS-140-M1" };
    const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
    async function getJson(path) {
      const response = await fetch(path);
      const body = await response.json();
      if (!response.ok) throw new Error(body.detail || body.error || "Request failed");
      return body;
    }
    async function loadBaseline() {
      const status = document.getElementById("status");
      const courses = document.getElementById("courses");
      try {
        const [summary, catalog] = await Promise.all([getJson("/api/summary"), getJson("/api/courses")]);
        status.innerHTML = [
          ["Courses", summary.courses], ["Learners", summary.learners],
          ["Assessments", summary.assessments], ["Attempts", summary.attempts]
        ].map(([label, value]) => '<div class="metric"><strong>' + escapeHtml(value) + '</strong><span>' + label + '</span></div>').join("");
        courses.innerHTML = catalog.courses.map(course =>
          '<article class="card"><h2>' + escapeHtml(course.title) + '</h2>' +
          '<p class="meta">' + escapeHtml(course.id) + ' · ' + escapeHtml(course.discipline) + ' · ' + escapeHtml(course.units) + ' units</p>' +
          '<button type="button" onclick="launchQuiz(this, \\'' + escapeHtml(assessmentByCourse[course.id]) + '\\')">Launch assessment</button></article>'
        ).join("");
      } catch (error) {
        status.innerHTML = '<span class="error">Caldova could not load the healthy baseline. Retry after service recovery.</span>';
        courses.innerHTML = "";
      }
    }
    async function loadRecommendations() {
      const feature = document.getElementById("recommendations");
      const message = document.getElementById("recommendations-message");
      const badge = document.getElementById("recommendations-badge");
      const retry = document.getElementById("recommendations-retry");
      feature.dataset.state = "loading";
      message.textContent = "Checking personalized recommendations…";
      badge.textContent = "Checking";
      retry.disabled = true;
      try {
        const response = await fetch("/api/recommendations/health?evidence=" + Date.now());
        const body = await response.json();
        const state = response.ok ? "available" : body.status === "degraded" ? "degraded" : "unknown";
        feature.dataset.state = state;
        badge.textContent = state;
        message.textContent = body.message || "Course recommendations status could not be determined.";
      } catch {
        feature.dataset.state = "unknown";
        badge.textContent = "Unknown";
        message.textContent = "Course recommendations status could not be determined. Core learning remains available.";
      } finally {
        retry.disabled = false;
      }
    }
    async function launchQuiz(button, id) {
      const panel = document.getElementById("quiz");
      button.disabled = true;
      panel.style.display = "block";
      panel.textContent = "Loading assessment…";
      try {
        const quiz = await getJson("/api/quiz/" + encodeURIComponent(id));
        panel.innerHTML = '<h2>' + escapeHtml(quiz.title) + '</h2>' +
          quiz.questions.map((question, index) =>
            '<div class="question"><strong>' + (index + 1) + '. ' + escapeHtml(question.prompt) + '</strong><p>' +
            question.options.map(escapeHtml).join(" · ") + '</p></div>'
          ).join("");
      } catch (error) {
        panel.innerHTML = '<p class="error">This assessment could not be launched. Try again shortly.</p>';
      } finally {
        button.disabled = false;
      }
    }
    document.getElementById("recommendations-retry").addEventListener("click", loadRecommendations);
    loadBaseline();
    loadRecommendations();
  </script>
</body>
</html>`);
});

app.use((req, res) => res.status(404).json({ error: "route_not_found", path: req.path }));

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`caldova_service_started service=${SERVICE} port=${PORT} api_base=${JSON.stringify(API_BASE_URL)}`);
});

function shutdown(signal) {
  console.log(`caldova_service_stopping service=${SERVICE} signal=${signal}`);
  server.close(() => process.exit(0));
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
