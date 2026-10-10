# Caldova source context

Caldova is a simulated production service with a portal and API on Azure Container Apps, PostgreSQL data storage, a Linux reporting-worker VM, Application Gateway, Key Vault, and Azure Monitor telemetry.

Use `@@RG@@` as the learner investigation boundary. Correlate:

- Application Insights requests, dependencies, exceptions, and availability
- Log Analytics container, gateway, PostgreSQL, and VM signals
- current Azure resource configuration and recent activity
- the public Application Gateway health endpoint

Alerts describe user-visible symptoms only. Do not infer the cause from an alert title. Confirm the failing path with telemetry and current resource state before proposing or applying an action.

The active source of truth is the isolated private learner repository generated from the `microsoft/ignite26-PREL38` template. Use both Code Access for semantic/file/commit evidence and the GitHub OAuth connector for branches, pull requests, and workflows. The deterministic fallback is the locally packaged source, dependency lockfiles, generated `caldova-deployment-evidence` memory, and immutable deployed image digests. Never request or store an attendee personal access token.

For every conclusion, separate:

- source or dependency evidence;
- deployed image and revision evidence;
- Azure configuration and telemetry evidence;
- missing or stale evidence.
