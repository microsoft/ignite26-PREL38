# Caldova healthy application baseline

## Runtime contract

| Component | Healthy responsibility | Verification |
|---|---|---|
| Application Gateway | Public front door for the portal | `GET /health`, `/ready`, and `/api/*` |
| Portal container | Learner workspace and API proxy | `GET /health`; `/ready` checks the API |
| API container | Courses, assessments, quizzes, grades, exports | `GET /health` checks PostgreSQL |
| PostgreSQL | Durable learning and reporting records | `node scripts/db-check.js` inside the API container |
| Reporting-worker VM | One-minute CSV export and operational heartbeat | `caldova-reporting` Syslog in Log Analytics |

## Preserved incident surfaces

- **NSG/Application Gateway:** the public request still crosses the gateway and Container Apps subnet boundary.
- **PostgreSQL performance:** quiz launch counts an indexed 120,000-row question bank before loading curated questions.
- **Container Apps revision:** portal and API remain independently versioned images with single active revisions.
- **Application telemetry:** both Node services send requests, dependencies, exceptions, and Caldova cloud-role labels to Application Insights while retaining structured console logs in Log Analytics.
- **Code regression:** `CALDOVA-PERF-INJECT-POINT` marks the API quiz hot path for a later code-release scenario.
- **Prebuilt latency variant:** `src/api/Dockerfile.latency` preserves health endpoints while adding a deterministic 1,250 ms delay to quiz and assessment requests. It is published before the workshop and never built by the learner simulator.
- **Reporting VM:** the timer, managed identity, Key Vault read, PostgreSQL query, local export, and Syslog ingestion form an independent signal chain.

## Build and local smoke test

Use `src/` as the Docker context. For a local smoke test, start the API with `CALDOVA_DATA_MODE=memory` on port 8081, then start the portal with `CALDOVA_API_BASE_URL=http://localhost:8081` on port 8080. Production deployments do not set memory mode.
