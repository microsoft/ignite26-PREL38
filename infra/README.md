# Caldova infrastructure

`main.bicep` is the local-authoring subscription-scoped deployment entry point. It creates one learner resource group containing:

- a private Azure Container Registry with admin access disabled
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
- `recommendationsMode` (`unavailable` for the prepared guided-learning state; `available` only for a repaired baseline)
- an SSH public key

Passwords are secure deployment parameters supplied in memory by `scripts/provision.ps1`; they are never stored in this repository.

For a new isolated deployment, deploy `bootstrap.bicep` first. It creates only the tagged learner resource group and secure registry so immutable images can be built before `main.bicep` deploys the complete environment. Container Apps pull from the registry with the Caldova user-assigned managed identity and `AcrPull`; registry admin credentials are never enabled.

Skillable must deploy [`skillable.bicep`](skillable.bicep) into the resource group it already created. The template is resource-group scoped and never creates, selects, or deletes a resource group. It consumes immutable images from an event-managed ACR and grants the learner application identity `AcrPull`; it does not create an empty per-instance registry. [`skillable.parameters.example.json`](skillable.parameters.example.json) documents the placeholder-only parameter contract; the event platform supplies registry coordinates, secrets, and generated keys at deployment time.

The lab image also supplies these configuration-only values to `scripts/configure.ps1` as environment variables rather than ARM parameters:

- `CALDOVA_GITHUB_REPOSITORY` — isolated writable `https://github.com/<owner>/<repo>` URL
- GitHub App mode: `CALDOVA_GITHUB_APP_CLIENT_ID`, `CALDOVA_GITHUB_APP_PRIVATE_KEY_SECRET_URI`, and `CALDOVA_GITHUB_APP_KEY_VAULT_IDENTITY_ID`
- temporary authoring fallback only: `CALDOVA_GITHUB_PAT`

Never persist these credentials in a parameter file, deployment output, state file, or lab log.

The API has two immutable workshop artifacts:

- `ApiImage`: healthy image built with `src/api/Dockerfile`
- `ApiLatencyImage`: elevated-response-time image built with `src/api/Dockerfile.latency`

Build and publish both before the workshop. Example build contexts:

```powershell
docker build -f src/api/Dockerfile -t <registry>/caldova-api:healthy-<version> src
docker build -f src/api/Dockerfile.latency -t <registry>/caldova-api:latency-<version> src
```

Attendee scripts never build images. Initial provisioning and reset always pin `ApiImage`.

The API Container App receives `CALDOVA_RECOMMENDATIONS_MODE` as a plain, discoverable configuration value. It is not a secret. The default `unavailable` value affects only `GET /recommendations/health`; it is excluded from liveness/readiness and every existing alert query. No guided alert or response-plan resource is deployed by the main templates.

The reporting-worker receives cloud-init from [`../src/reporting-worker/cloud-init.yaml`](../src/reporting-worker/cloud-init.yaml). Its system-assigned identity can read only the PostgreSQL password secret needed for the one-minute export. PostgreSQL remains private; seed and readiness checks execute through the internal API container rather than opening a public database path.

The Skillable image must preinstall Node.js 22+, Azure CLI, `@azure/mcp@3.0.0-beta.43`, and the approved `srectl` global tool for agent configuration. After provisioning, run `scripts/configure.ps1 -LearnerNumber N -CheckOnly` to validate the configuration prerequisites without applying artifacts.

## Ownership boundary

Bicep owns durable Azure resources. The scripts in [`../scripts/`](../scripts/) own ordered setup, seeded data, SRE Agent configuration, readiness, scenario state, reset, and teardown.
