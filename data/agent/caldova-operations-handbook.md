# Caldova operations handbook

## Scope and environments

- Production-simulation boundary: Azure resource group `@@RG@@` in subscription `@@SUBSCRIPTION_ID@@`.
- No shared or external production incident dependency is in scope.
- SRE Agent execution identity: principal `@@AGENT_PRINCIPAL_ID@@`, managed identity resource `@@AGENT_IDENTITY_RESOURCE_ID@@`.
- Log Analytics workspace resource: `@@LAW_WORKSPACE_RESOURCE_ID@@`.
- Log Analytics workspace GUID for data-plane queries: `@@LAW_WORKSPACE_GUID@@`.
- Application Insights resource: `@@APP_INSIGHTS_RESOURCE_ID@@`.
- Application Insights appId for query APIs: `@@APP_INSIGHTS_APP_ID@@`.

Never substitute a workspace resource name for the workspace GUID or an Application Insights resource name for the appId.

## Architecture and request paths

```text
Learner -> public Application Gateway -> portal Container App
                                      -> API Container App -> PostgreSQL
Reporting worker VM -> PostgreSQL -> /var/lib/caldova/exports
All services -> Azure Monitor / Log Analytics / Application Insights
```

Application Gateway is the only learner-facing entry point. The Container Apps environment and PostgreSQL path are private. The portal calls the API for course, quiz, and summary operations. The reporting worker runs independently and emits heartbeat/export evidence.

## Dependency and service catalog

| Service | Depends on | Primary evidence | Failure effect |
|---|---|---|---|
| Application Gateway | DNS, backend FQDN, probe, routing, network path | backend health, access logs, metrics, resource config | public 502/timeout |
| Portal Container App | ACA environment, image, API base URL | revisions, replicas, console traces, request metrics | site unavailable or API proxy failures |
| API Container App | ACA environment, image, Key Vault reference, PostgreSQL | revisions, traces, dependencies, latency | quiz/course/data failures |
| PostgreSQL | private DNS/subnet, credentials, capacity | availability, connections, storage, dependency failures | consistent/intermittent API failures |
| Reporting worker | VM, systemd service, disk, PostgreSQL | Syslog, journal heartbeat, export timestamps | missing reports |
| Key Vault | managed identity and secret references | reference metadata and access failures, never secret values | app revision/startup or connection failures |

## Reliability objectives

These are lab operating objectives, not contractual customer SLAs:

- Public health and readiness endpoints should return HTTP 200.
- Healthy quiz requests should normally complete below 600 ms; the alert threshold is 900 ms p95.
- Application Gateway should have at least one healthy backend.
- API and portal should each have at least one ready replica and an immutable image digest.
- Reporting heartbeat and a successful export should be present within five minutes.
- PostgreSQL should be available with no sustained failed-connection or storage-saturation signal.

## Telemetry query recipes

Use UTC and state the query time range.

```bash
az monitor log-analytics query \
  --workspace '@@LAW_WORKSPACE_GUID@@' \
  --analytics-query 'AppTraces | where TimeGenerated > ago(30m) | where Message startswith "caldova_request" | project TimeGenerated, Message'
```

```bash
az monitor app-insights query \
  --app '@@APP_INSIGHTS_APP_ID@@' \
  --analytics-query 'traces | where timestamp > ago(30m) | where message startswith "caldova_request" | project timestamp, message'
```

For the latency path, parse `ms=` from Caldova request traces and calculate p95. For gateway incidents, query `AGWAccessLogs` by request URI and HTTP status. For reporting, query Syslog for `caldova-reporting` heartbeat and failure messages. If a data-plane query returns authorization failure, record the missing role/scope and use only clearly labeled ARM/metric evidence.

## Ownership and RACI

| Role | Responsible | Accountable | Consulted | Informed |
|---|---|---|---|---|
| Incident responder | triage, bounded mitigation, verification, summary, closure | event operations lead | application/platform owners | session facilitator |
| Application owner | code/runtime diagnosis and durable recommendation | application lead | incident responder | event operations |
| Platform owner | gateway, network, ACA, PostgreSQL platform changes | platform lead | incident responder | application owner |
| Event operations | subscription/RBAC prerequisites and blocked closure | event operations lead | security/platform owners | facilitator |
| Facilitator | scenario operation and learner support | session owner | event operations | attendees |

No real personal names belong in this artifact.

## Escalation matrix

- **Sev1:** public quiz launch unavailable or gateway has no healthy backend. Escalate immediately to event operations and platform owner.
- **Sev2:** sustained latency, intermittent failures, or reporting unavailable. Escalate when mitigation is not identified within ten minutes.
- **Evidence/RBAC blocker:** hand off to event operations with principal ID, role name, role-definition ID, exact scope, failed command, UTC, and correlation ID.
- **Security exposure:** stop writes, preserve evidence, and escalate to the security owner role.

## Incident and change process

1. Acknowledge and timestamp the symptom-only alert.
2. Investigate with read-only Azure CLI and telemetry first.
3. State evidence, mitigation, and rollback before a permitted write.
4. Apply the smallest reversible live mitigation.
5. Verify the original symptom and before/after telemetry.
6. Produce the incident summary and 5 Whys.
7. Close the Azure alert through the supported Alerts Management state API and verify `Closed`.
8. Preserve the incident thread. Close it when a supported mutation exists; otherwise record the limitation.
9. Recommend durable IaC/code/process changes without applying unsupported external workflows.

## Permitted remediation boundary

Allowed inside `@@RG@@`: reversible Container App revision/traffic/scale changes, Application Gateway probe/backend corrections, exact planted route/NSG cleanup, service restart, and restoration of known-good secret references without reading secret values.

Never change IAM, create role assignments during an incident, reveal secrets, change address spaces, delete data, resize paid service tiers, disable monitoring, or act outside `@@RG@@`.

## Known risks

- Log Analytics and Application Insights data-plane access can be absent even when ARM reads succeed.
- Alert state and monitor condition are distinct; recovery does not automatically mean `alertState=Closed`.
- Console-session and Alerts Management APIs enforce quotas; use bounded retry/backoff.
- Missing Defender, SBOM, cost, or dependency evidence must remain explicitly inconclusive.
- A stale or unresolved alert can prevent a fresh incident from being created.

## Repository map

- `src/portal/` — learner portal.
- `src/api/` — quiz/course API and database helpers.
- `infra/` — Azure baseline and alert definitions.
- `scripts/scenarios/` — reversible scenario lifecycle.
- `data/agent/` — agent, skills, context, tasks, and response-plan source of truth.
- `instructions/` — attendee flow.
- `docs/` — supporting facilitator/reference material.

## Glossary

- **ACA:** Azure Container Apps.
- **AGW:** Azure Application Gateway.
- **LAW:** Log Analytics workspace.
- **appId:** Application Insights application identifier used by its query API.
- **Monitor condition:** Azure Monitor evaluation state such as Fired or Resolved.
- **Alert state:** operator workflow state such as New, Acknowledged, or Closed.
- **IRP:** incident response plan/filter that routes alerts to an SRE Agent.
- **Closure ledger:** final record proving symptom recovery, summary completion, alert closure, and thread status.
