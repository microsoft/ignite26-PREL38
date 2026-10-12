# Skillable lifecycle contract

Skillable invokes the scripts in order with the same `learnerNumber` and `deploymentToken`.

## Provision

`scripts/provision.ps1`

- validates Azure CLI, Bicep, learner inputs, image references, SSH key, and secure password inputs
- requires distinct, immutable healthy and latency API images built before the workshop
- deploys `infra/main.bicep`
- deploys the healthy API image initially and writes both image references to `.caldova/state-userN.json`
- fails before deployment when Caldova application images are unavailable

## Configure

`scripts/configure.ps1`

- defaults to the repository-owned `scripts/configure-agent.mjs` adapter
- supports `-CheckOnly` so Skillable can validate Node.js 22+, Azure CLI authentication, the connector runtime, `srectl`, provider/API availability, bundle integrity, and both agent endpoints without changing configuration
- configures Microsoft Learn and Caldova source context on both agents
- configures the hard-scoped managed-identity FinOps connector, GitHub/source evidence, tasks, reports, skills, custom agent, and response plan on Preconfigured only
- applies the native `SKILL.md`, custom-agent YAML, and Azure Monitor incident-filter YAML only to `sre-caldova-prerun-userN`
- leaves `sre-caldova-config-userN` with only the secure connections and context prerequisites required for the learner exercise
- accepts `-AdapterPath` only as a test override; the repository adapter is the Skillable default

The Skillable image must preinstall Node.js 22 or later, PowerShell 7 or later, Azure CLI/Bicep, `@azure/mcp@3.0.0-beta.43` for supported connector/report surfaces, approved `srectl` `1.0.43`, and the repository npm dependencies. `scripts/setup-workstation.ps1` and `scripts/check-workstation.ps1` are image-authoring/pre-run tools; setup uses npm offline mode and never downloads attendee-time packages. The active Azure identity must be able to read and configure both SRE Agent resources. Runtime connectors use the agents' managed identities and never load credentials from files or environment variables. The incident custom agent uses agent-owned Azure CLI tools, not Azure MCP.

## Skillable orchestration

`scripts/skillable-orchestrate.ps1`

- verifies the prepared workstation
- invokes Provision → Configure → Prepare → Readiness for one learner
- stops at the first failed stage with the learner number and stage name
- prints learner-specific portal, agent, and simulator links without printing credentials or secret values
- intentionally excludes reset and teardown

## Prepare

`scripts/prepare.ps1`

- verifies the public health endpoint before changing data
- applies the idempotent schema and seed through `az containerapp exec` in the private API network path
- generates measured baseline traffic through Application Gateway
- verifies PostgreSQL from the API container and waits for a successful reporting-worker heartbeat in Log Analytics
- records the HTTP measurements and verification evidence in `.caldova/baseline-userN.json`

## Readiness

`scripts/readiness.ps1`

- verifies ARM resources, both agents, public portal/API paths through Application Gateway, PostgreSQL through the API container, and a recent reporting heartbeat
- returns a nonzero exit code until every required check passes
- verifies the API is pinned to the healthy image, core paths are healthy, the intentionally degraded recommendations path is explicitly allowed, the guided chain is disabled, and exercise alerts evaluate every five minutes

## Learner simulator

`scripts/start-simulator.ps1 -LearnerNumber N`

- starts an attached local Node.js process and verifies the learner URL plus status endpoint over HTTP
- serves the local workstation UI at `http://127.0.0.1:7070/?learnerNumber=N`
- opens the URL unless `-NoBrowser` is supplied and stops cleanly with Ctrl+C
- reads the checked-in scenario catalog from `simulator/scenarios.json`
- validates the selected agent and response plan before Start is enabled
- uses a per-learner file lock so duplicate browser actions cannot overlap
- requires `CALDOVA_AZURE_MUTATION_ENABLED=YES` and `CALDOVA_AZURE_TARGET=skillable` before any start or reset action can change Azure
- never builds an attendee image
- defaults to the isolated course-recommendations exercise and also packages extended quiz/network/reporting scenarios for four-hour or post-lab use
- snapshots the exact live values it changes under `.caldova/`; the two path-isolation exercises also prove the portal and private API remain healthy from inside the internal Container Apps environment
- assigns exactly one response-plan owner during an exercise and restores the captured ownership state on Reset

## Reset

`scripts/reset.ps1`

The simulator invokes this aggregate entry point rather than calling a scenario reset directly. It runs the selected scenario restore once, then runs `scripts/readiness.ps1`; simulator state returns to idle only after both steps succeed.

- invokes the checked-in scenario reset entry point
- for `-Scenario api-latency`, pins the healthy API image and restores baseline response-plan ownership
- for `-Scenario quiz-launch-scenario-1|2|3`, restores the saved live baseline, verifies the public path and backend health, restores response-plan ownership, and removes only that scenario's snapshot
- for the recommendations scenario, verifies the feature can recover without affecting core health and removes only its captured state
- for reporting, removes only the named data-volume filler, restores the reserved-block baseline, requires a fresh six-row export plus heartbeat, and uses the guarded rule lifecycle only after verified recovery
- re-runs readiness after reset
- fails if no scenario reset implementation exists

## Teardown

`scripts/teardown.ps1`

- verifies the calculated learner resource group
- requires explicit confirmation unless `-Force` is supplied by the lab platform
- deletes only that learner resource group
