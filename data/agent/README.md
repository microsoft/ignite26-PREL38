# Azure SRE Agent configuration bundle

`configuration.json` is consumed by the repository-owned `scripts/configure-agent.mjs` adapter.

| Artifact | Purpose | Applied to |
|---|---|---|
| `connectors.json` | Microsoft Learn plus the managed-identity, read-only Caldova FinOps stdio MCP definition | Learn on both agents; FinOps on Preconfigured only |
| `guided-course-recommendations/` | Alert, skill, custom-agent, response-plan, and completed-example references for the default learning scenario | Unapplied initially; learner-created during Configure path |
| `source-context.md` | Caldova architecture, identity, and exact telemetry identifiers uploaded as agent knowledge | Both agents |
| `caldova-operations-handbook.md` | Service catalog, reliability objectives, RACI, escalation, and operating model | Both agents |
| `finops-runbook.md` | Cost Management, consumption, inventory, and Retail Prices fallback hierarchy | Both agents |
| `cve-evidence-contract.md` | Fail-closed source, SBOM, image, Defender, and exposure correlation contract | Both agents |
| `live-report-prompts.md` | Exact prompts used by automated Preconfigured Agent authoring and the Configure Agent exercise | Both agents |
| `skills/caldova-incident-triage/SKILL.md` | Ordered symptom-to-cause investigation and reversible recovery workflow | Preconfigured agent only |
| `skills/incident-summary/SKILL.md` | Executive summary, timeline, 5 Whys, evidence, and closure ledger | Preconfigured agent only |
| `skills/caldova-audit-report/SKILL.md` | Shared, fail-closed workspace flow for validated branded PowerPoint audit attachments | Preconfigured cost and CVE tasks |
| `agents/*/*.yaml` and `critic.md` | Native `ExtendedAgent`, agent-owned tools, reflection, and closure quality gate | Preconfigured agent only |
| `incident-filters/*.yaml` | Native Azure Monitor incident response filter | Preconfigured agent only |
| `incident-triage-skill.md` and `response-plan.md` | Human-readable author and learner references | Repository only |
| `investigation-example.md` | Root-cause-neutral example of a completed evidence/action/verification report | Repository only |

The configurator resolves the Log Analytics workspace GUID, Application Insights appId, and each agent's managed-identity principal at apply time. It validates `Log Analytics Reader`, `Log Analytics Data Reader`, and the read-only `Privileged Monitoring Data Reader` on the isolated learner workspace, plus `Monitoring Reader` on the resource group for both agents and `Reader` plus `Cost Management Reader` for the Preconfigured Agent. The FinOps MCP server runs inside the SRE Agent container, is bound to that user-assigned identity, accepts no scope or mutation inputs, and exposes only `get_caldova_finops`. Its Retail Prices fallback uses a timestamped snapshot refreshed automatically during configuration when direct runtime egress to the Retail Prices API is unavailable. Role-definition IDs are resolved dynamically. If the operator cannot create a missing assignment, configuration stops with the exact principal, role, scope, and event-operations handoff.

The generated `caldova-deployment-evidence` memory records those identifiers, role-definition IDs, the source commit, dependency lockfile hashes, direct dependencies, and deployed revision/image identities. The Preconfigured Agent receives exactly five weekly read-only tasks: NSG, RBAC, cost, capacity, and CVE. The cost and CVE tasks use the supported agent workspace plus `SaveFileToBlob` to persist validated branded PowerPoint evidence decks on their execution threads; a missing generator or failed publication remains an explicit blocker and is never represented as an attachment. Changed same-name task definitions are replaced idempotently while unchanged tasks retain their IDs.

The Configure Agent receives safe evidence access, Microsoft Learn, source context, and one idempotent Getting started thread, but not the finished skills, custom agent, response plan, tasks, or reports. The thread is API-created once and recorded by a marker memory; no UI automation is required.

The guided course-recommendations artifacts are intentionally absent from `configuration.json`. Do not add them to the initial configure lifecycle: the first run must remain a manual investigation with no alert or automatic handling.

The custom incident responder uses agent-owned Azure CLI read/write/help, memory search, and Python tools. Skills remain procedural and do not declare tools. Recovered Caldova alerts in the learner resource group are explicitly moved to Azure Alerts Management state `Closed`; retained incident threads are verified rather than deleted because no supported thread-close mutation is available.

Direct Log Analytics queries from the runtime identity can return HTTP 403 even when setup roles are present. Treat that as unavailable evidence, never as zero events. Incident investigations use Application Insights, Azure CLI/ARM, metrics, current configuration, and, for reporting, explicitly labeled VM journal/worker evidence.
