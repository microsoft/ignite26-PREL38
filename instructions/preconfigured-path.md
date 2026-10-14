# Preconfigured Agent path

**Time:** 25–30 minutes
**Use:** `sre-caldova-prerun-userN`, where `N` is your learner number.

Choose this path to inspect the complete reference configuration and retained evidence. Do not configure a second scenario or enable the guided chain.

## 1. Review the completed configuration

Open **Getting started: Caldova operations** and review:

- Caldova architecture, request paths, ownership, and safe remediation boundaries;
- Microsoft Learn and secure GitHub/source evidence;
- the custom incident responder and its agent-owned Azure CLI tools;
- `caldova-incident-triage` and `incident-summary`;
- the Azure Monitor incident platform and enabled main response plan;
- exactly five weekly read-only tasks: NSG, RBAC, cost, capacity, and CVE;
- the two existing Live Reports:
  - **Caldova FinOps** (`CALDOVA-FINOPS-V2`) with ActualCost → consumption → inventory/Retail Prices fallback, explicit provenance, and no false zero;
  - **Caldova Operations Command Center** (`CALDOVA-OCC-V2`) with **Operations Overview**, **Dependency Mapping**, and **Resource Explorer** tabs;
- session insights, tool/skill usage, and consumption surfaces.

The incident custom agent uses agent-owned Azure CLI tools and does not depend on Azure MCP. Live Reports may use their own read-only connector surfaces.

## 2. Confirm the prepared state

The public health, readiness, courses, quizzes, database, gateway, and reporting path are healthy. The optional course-recommendations feature is intentionally unavailable and returns HTTP 503 without affecting readiness.

The Preconfigured Agent shows the completed guided skill, custom agent, and closure connector, but the guided alert and response plan remain disabled. The Configure Agent remains a starter experience.

## 3. Review the completed guided AFTER-state

Open and compare:

- [Guided skill](../data/agent/guided-course-recommendations/skill/SKILL.md)
- [Guided custom agent](../data/agent/guided-course-recommendations/agent/caldova-guided-feature-responder.yaml)
- [Guided response plan](../data/agent/guided-course-recommendations/incident-filter/course-recommendations-learning-response.yaml)
- [Completed investigation example](../data/agent/guided-course-recommendations/completed-example.md)

Confirm:

- the skill owns no tools;
- the custom agent owns narrowly scoped Azure CLI read/write/help tools;
- `caldova-guided-alerts` exposes only the exact resolved-alert closure operation;
- the alert and response plan are disabled in the prepared state;
- completed incident evidence remains available because incident-thread closure is not supported.

## 4. Inspect one completed incident

Identify:

- alert and response-plan match;
- selected custom agent and skills;
- evidence source and timestamp;
- confirmed cause versus inference;
- approved action and rollback;
- recovery evidence;
- monitor condition and alert state;
- completed incident summary.

Direct Log Analytics queries from the runtime can return 403. The agent must not present that as a clean result. Accept Application Insights, Azure CLI/ARM, metrics, configuration, or explicitly labeled VM journal evidence instead.

## 5. Inspect tasks and reports

Review one weekly task result and both Live Reports. Verify evidence freshness, scope, uncertainty, and read-only behavior. The completed cost and CVE task threads also include a branded, downloadable PowerPoint evidence deck generated through the supported workspace artifact flow.

For FinOps, distinguish actual cost, forecast, inventory/Retail Prices estimate, and potential savings. If live Retail Prices egress is unavailable, the connector uses its automatically refreshed timestamped snapshot and labels that provenance.

## 6. Optional single simulation

If time remains, run exactly one scenario. The recommended option is **Course recommendations are unavailable**, because it creates evidence immediately and does not wait for an alert in the default disabled state.

```powershell
pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber N
```

Select **Preconfigured**, keep the default scenario, run **Check configuration**, and start once. Ask the agent to investigate manually without enabling the guided chain. Finish with **Check recovery** and **Reset**.

Other scenarios are four-hour-path or post-lab practice.

## Timing notes

| Stage | Typical time |
|---|---:|
| Azure Monitor evaluation interval | 5 minutes |
| Symptom to alert | 5–10 minutes |
| Alert to incident thread | about 1–2 minutes |
| Investigation and permitted mitigation | 3–10 minutes |
| Healthy recovery to monitor resolution | 5–20 minutes |

While an optional alert is pending, inspect the completed tasks, reports, skills, and prior incident evidence. Do not refresh repeatedly or start another scenario.

Use [Screenshot inventory](screenshot-inventory.md) for the completed AFTER-state captures.
