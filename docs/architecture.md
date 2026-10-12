# Caldova implementation architecture

## Learner topology

Each learner receives one resource group and one shared Caldova workload. The same workload supports both learner paths:

- `sre-caldova-prerun-userN` uses the prepared response configuration.
- `sre-caldova-config-userN` starts with platform context and Azure Monitor connectivity, then the learner creates the custom agent, skill, and response plan.

The learner number is the stable human-readable suffix. The deployment token adds uniqueness to Azure resource names without exposing credentials.

## Request and telemetry flow

1. Application Gateway receives learner traffic.
2. The gateway resolves the internal Container Apps environment through a VNet-linked private DNS zone and routes to the Caldova portal.
3. The portal calls the Caldova API in the same Container Apps environment.
4. The API uses PostgreSQL and Key Vault through managed identities and private network paths.
5. The Linux reporting-worker VM produces operational signals independently of the web path.
6. Container Apps, Application Gateway, PostgreSQL, and the VM send telemetry to Log Analytics and Application Insights.
7. Symptom-only Azure Monitor alerts provide incident evidence without naming the planted cause.
8. Both SRE Agent resources use Azure Monitor as the only incident platform and scope their knowledge graph to the learner resource group.
9. The optional course recommendations route is isolated from readiness and core learning. Its prepared unavailable state produces App Insights request/event evidence but has no initial Azure Monitor alert or response-plan owner.

## Resource ownership

| Layer | Owner | Responsibility |
|---|---|---|
| Durable resources | Bicep | Network, compute, data, monitoring, identities, alerts, and SRE Agent resources |
| Ordered lifecycle | PowerShell wrappers | Provision, configure, prepare, readiness, reset, and teardown |
| Agent configuration adapter | `scripts/configure-agent.mjs` | Microsoft Learn and safe context on both agents; managed-identity FinOps evidence, GitHub source access, skills, custom agent, response plan, tasks, and reports on Preconfigured |
| Prepared response content | `data/agent/` | Applied operational artifacts plus the explicitly unapplied guided-course-recommendations learner references |
| Application images | `src/portal/`, `src/api/` | Deterministic Node.js container builds supplied explicitly to provisioning |
| Schema and healthy seed | `src/db/schema.sql`, `src/workload/seed.ps1` | Private, idempotent PostgreSQL initialization executed inside the API container |
| Reporting workload | `src/reporting-worker/cloud-init.yaml` | One-minute grade export plus `caldova-reporting` Syslog heartbeat |

## Security boundaries

- PostgreSQL uses private networking.
- Key Vault uses Azure RBAC and managed identities.
- Container Apps and SRE Agents use user-assigned managed identities.
- Password parameters are marked secure and passed only at deployment time.
- The repository contains no credentials.
- Agent action permissions are scoped to the learner resource group and split between read/monitoring and workload-specific control-plane contributor roles. Agent identities have no Key Vault secret-value data-plane role; they can inspect only ARM metadata exposed by their Reader permissions.
- Configuration uses the active Skillable Azure identity for setup and each agent's user-assigned managed identity for runtime connectors. The custom incident responder uses agent-owned Azure CLI tools, not Azure MCP.

## Healthy application baseline

The smallest coherent runtime is two Container Apps:

- the portal is the public experience and App Gateway backend;
- the API is internal and owns every data-backed learning operation.

This keeps later incident surfaces without unnecessary services: Application Gateway and NSG routing remain visible, API revisions and code regressions remain isolated, quiz lookups preserve PostgreSQL query-performance work, and the reporting VM provides an independent heartbeat/export path.

`GET /api/recommendations/health` is a non-critical feature route controlled by the non-secret API Container App setting `CALDOVA_RECOMMENDATIONS_MODE`. The prepared value is `unavailable`; the route returns a symptom-only 503 while `/health`, `/ready`, courses, quizzes, PostgreSQL-backed operations, reporting, and gateway health remain unaffected. The simulator can generate deterministic App Insights evidence immediately. The guided alert, skill, custom agent, and response plan are reference artifacts only until a learner creates them.

The seed creates three fictional Caldova courses, four learners, assessments, quiz questions, attempts, grade summaries, a reporting-export record, and a 120,000-row indexed question bank. No attendee or runtime content depends on the reference implementation.

Learner instructions, the local simulator, Skillable orchestration, and facilitator operations are linked from [`instructions/README.md`](../instructions/README.md) and [`docs/skillable-hosting.md`](skillable-hosting.md).
