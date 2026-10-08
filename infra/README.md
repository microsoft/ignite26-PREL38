# Caldova infrastructure

`main.bicep` is the subscription-scoped deployment entry point. It creates one learner resource group containing:

- Azure Container Apps for the Caldova portal and API
- Azure Database for PostgreSQL
- a Linux reporting-worker VM
- a virtual network, subnets, and network security groups
- Azure Application Gateway
- Azure Key Vault
- Application Insights and Log Analytics
- symptom-only Azure Monitor alerts
- `sre-caldova-prerun-userN` and `sre-caldova-config-userN`

## Parameters

The stable learner inputs are:

- `learnerNumber`
- `deploymentToken`
- `location`
- application image references
- an SSH public key

Passwords are secure deployment parameters supplied in memory by `scripts/provision.ps1`; they are never stored in this repository.

The API has two immutable workshop artifacts:

- `ApiImage`: healthy image built with `src/api/Dockerfile`
- `ApiLatencyImage`: elevated-response-time image built with `src/api/Dockerfile.latency`

Build and publish both before the workshop. Example build contexts:

```powershell
docker build -f src/api/Dockerfile -t <registry>/caldova-api:healthy-<version> src
docker build -f src/api/Dockerfile.latency -t <registry>/caldova-api:latency-<version> src
```

Attendee scripts never build images. Initial provisioning and reset always pin `ApiImage`.

The reporting-worker receives cloud-init from [`../src/reporting-worker/cloud-init.yaml`](../src/reporting-worker/cloud-init.yaml). Its system-assigned identity can read only the PostgreSQL password secret needed for the one-minute export. PostgreSQL remains private; seed and readiness checks execute through the internal API container rather than opening a public database path.

The Skillable image must preinstall Node.js 22+, Azure CLI, `@azure/mcp@3.0.0-beta.43`, and the approved `srectl` global tool for agent configuration. After provisioning, run `scripts/configure.ps1 -LearnerNumber N -CheckOnly` to validate the configuration prerequisites without applying artifacts.

## Ownership boundary

Bicep owns durable Azure resources. The scripts in [`../scripts/`](../scripts/) own ordered setup, seeded data, SRE Agent configuration, readiness, scenario state, reset, and teardown.
