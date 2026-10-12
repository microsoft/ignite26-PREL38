# Screenshot inventory

Capture screenshots only through the authenticated workshop browser profile. Do not invent or substitute screenshots.

Use this convention:

- **Configure before:** starter state with no guided artifacts.
- **Configure manual steps:** one capture for each learner action and relationship.
- **Preconfigured after:** completed reference artifacts and retained evidence.

## Configure Agent before

| Filename | Required callout |
|---|---|
| `configure-01-portal-prepared.png` | Core portal healthy; Course recommendations intentionally degraded. |
| `configure-02-agent-overview.png` | Configure Agent and Getting started thread. |
| `configure-03-no-guided-skill.png` | No `course-recommendations-recovery`. |
| `configure-04-no-guided-agent.png` | No `caldova-guided-feature-responder`. |
| `configure-05-no-guided-alert.png` | No `Course-recommendations-unavailable`. |
| `configure-06-no-guided-plan.png` | No `course-recommendations-learning-response`. |
| `configure-07-simulator-before.png` | Default scenario checked; no automatic incident expected. |

## Configure Agent manual investigation and setup

| Filename | Required callout |
|---|---|
| `configure-08-manual-investigation.png` | Application Insights evidence and healthy adjacent core paths. |
| `configure-09-container-app-setting.png` | Current revision/configuration and one-setting rollback. |
| `configure-10-skill-draft.png` | Generated reusable skill draft. |
| `configure-11-skill-saved.png` | Saved skill with no skill-owned tools. |
| `configure-12-alert-created.png` | Exact alert name, Application Insights scope, 5-minute evaluation/window, auto-resolution, disabled. |
| `configure-13-custom-agent.png` | Guided custom agent, only guided skill, agent-owned Azure CLI read/write/help, no Azure MCP dependency. |
| `configure-14-closure-connector.png` | Managed-identity connector with only `close_guided_alert`. |
| `configure-15-response-plan.png` | Exact title match, guided handler, merge disabled, disabled. |
| `configure-16-chain-linked.png` | Alert → response plan → custom agent → skill relationship. |
| `configure-17-alert-enabled.png` | Guided alert enabled. |
| `configure-18-plan-enabled.png` | Guided response plan enabled. |
| `configure-19-second-run.png` | Second simulator run waiting for or detecting the alert. |
| `configure-20-automatic-investigation.png` | Guided agent/skill selection and evidence-backed diagnosis. |
| `configure-21-remediation-recovery.png` | One-setting remediation, HTTP 200, ready revision, healthy core paths. |
| `configure-22-alert-closed.png` | Resolved monitor condition and Closed alert state. |
| `configure-23-cleanup.png` | Response plan disabled first, alert disabled second, completed evidence retained. |

## Preconfigured Agent after

| Filename | Required callout |
|---|---|
| `preconfigured-01-overview.png` | Prepared agent context, connectors, main response plan, and no active fault. |
| `preconfigured-02-guided-skill.png` | Completed skill with no owned tools. |
| `preconfigured-03-guided-agent.png` | Agent-owned Azure CLI tools and only the guided skill. |
| `preconfigured-04-guided-connector.png` | Single hard-scoped closure tool. |
| `preconfigured-05-guided-alert-disabled.png` | Disabled reference alert. |
| `preconfigured-06-guided-plan-disabled.png` | Disabled exact-match response plan. |
| `preconfigured-07-completed-incident.png` | Retained investigation, remediation, recovery, closure, and summary. |
| `preconfigured-08-five-tasks.png` | Exactly five Active weekly read-only tasks. |
| `preconfigured-09-finops-v2.png` | Actual/forecast/estimate provenance and `CALDOVA-FINOPS-V2`. |
| `preconfigured-10-occ-overview.png` | Operations Overview tab. |
| `preconfigured-11-occ-dependencies.png` | Dependency Mapping tab. |
| `preconfigured-12-occ-resources.png` | Resource Explorer tab. |
| `preconfigured-13-insights-consumption.png` | Session insights and consumption. |
| `preconfigured-14-final-prepared.png` | Core healthy, recommendations intentionally degraded, zero open alerts. |

Incident threads have no supported close mutation; a completed retained thread is the expected evidence state.
