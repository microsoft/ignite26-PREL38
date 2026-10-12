# Caldova source context

Caldova is a simulated production service with a portal and API on Azure Container Apps, PostgreSQL data storage, a Linux reporting-worker VM, Application Gateway, Key Vault, and Azure Monitor telemetry.

Use `@@RG@@` as the learner investigation boundary. Correlate:

- Application Insights appId `@@APP_INSIGHTS_APP_ID@@` for application queries;
- Log Analytics workspace GUID `@@LAW_WORKSPACE_GUID@@` for workspace queries;
- Application Insights requests, traces, dependencies, exceptions, and availability;
- Log Analytics container, gateway, PostgreSQL, and VM signals;
- current Azure resource configuration and recent activity
- the public Application Gateway health endpoint

The SRE Agent execution identity is managed identity principal `@@AGENT_PRINCIPAL_ID@@` (`@@AGENT_IDENTITY_RESOURCE_ID@@`). Its evidence access must be validated explicitly; a query failure is a permission gap, not an empty result.

Alerts describe user-visible symptoms only. Do not infer the cause from an alert title. Confirm the failing path with telemetry and current resource state before proposing or applying an action.

The optional course recommendations route is deliberately outside core health and readiness. Its initial guided-learning state has no Azure Monitor alert or response-plan owner. Investigate it manually with Application Insights requests/traces/events and current Container Apps configuration. Do not infer core outage from that feature's degraded state and do not rely on the blocked Log Analytics runtime query.

The active source of truth is the isolated private learner repository generated from the `microsoft/ignite26-PREL38` template. Use both Code Access for semantic/file/commit evidence and the GitHub OAuth connector for branches, pull requests, and workflows. The deterministic fallback is the locally packaged source, dependency lockfiles, generated `caldova-deployment-evidence` memory, and immutable deployed image digests. Never request or store an attendee personal access token.

For every conclusion, separate:

- source or dependency evidence;
- deployed image and revision evidence;
- Azure configuration and telemetry evidence;
- missing or stale evidence.

Load `caldova-operations-handbook` before an incident or scheduled review. It is the canonical architecture, dependency, reliability-objective, telemetry, ownership, escalation, remediation-boundary, risk, repository-map, and glossary reference.
