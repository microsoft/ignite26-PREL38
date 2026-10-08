# Caldova source context

Caldova is a simulated production service with a portal and API on Azure Container Apps, PostgreSQL data storage, a Linux reporting-worker VM, Application Gateway, Key Vault, and Azure Monitor telemetry.

Use `@@RG@@` as the learner investigation boundary. Correlate:

- Application Insights requests, dependencies, exceptions, and availability
- Log Analytics container, gateway, PostgreSQL, and VM signals
- current Azure resource configuration and recent activity
- the public Application Gateway health endpoint

Alerts describe user-visible symptoms only. Do not infer the cause from an alert title. Confirm the failing path with telemetry and current resource state before proposing or applying an action.
