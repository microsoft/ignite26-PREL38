# Skillable hosting runbook

This runbook is for image authors and lab operators. Attendee workstations must be fully prepared before the learner session and must not download packages at runtime.

## Image-authoring prerequisites

Install and cache these components in the image:

- Node.js 22 or later, including npm;
- PowerShell 7 or later;
- Azure CLI with Bicep available through `az bicep`;
- global `@azure/mcp@3.0.0-beta.43`, including `azmcp`;
- approved `srectl` version `1.0.43`;
- npm package cache entries required by `src/api/package-lock.json` and `src/portal/package-lock.json`;
- the complete packaged repository, including `data/agent/`, `infra/`, `scripts/`, `simulator/`, and `src/`.

Run offline setup while authoring the image or in a platform pre-run:

```powershell
pwsh -NoProfile -File scripts/setup-workstation.ps1 -Mode ImageAuthoring
pwsh -NoProfile -File scripts/check-workstation.ps1
```

`setup-workstation.ps1` uses `npm ci --offline`; it fails rather than contacting a registry. Populate the npm cache and install the base tools before running it. Do not expose these commands as attendee installation steps.

## Required environment and inputs

The platform supplies these values per learner:

| Input | Contract |
|---|---|
| `SubscriptionId` | Subscription containing the learner deployment. |
| `Location` | Primary Azure region. |
| `LearnerNumber` | Whole number from 1 through 999. |
| `DeploymentToken` | Four through 32 letters, numbers, underscores, or hyphens; used only for deterministic uniqueness. |
| `ImageRegistrySubscriptionId` | Subscription containing the event-managed ACR. The deployment identity must be able to create an `AcrPull` role assignment on this registry. |
| `ImageRegistryResourceGroupName` | Resource group containing the event-managed ACR. |
| `ImageRegistryName` | Event-managed ACR containing the immutable Caldova images. It must be reachable from the Skillable tenant; do not reference an authoring registry in another tenant. |
| `PortalImage` | Immutable digest-pinned Caldova portal image in the event-managed ACR. |
| `ApiImage` | Immutable digest-pinned healthy API image in the event-managed ACR. |
| `ApiLatencyImage` | Different immutable digest-pinned latency API image in the event-managed ACR. |
| `QuizLatencyThresholdMs` | Optional; defaults to 900. |
| `VmAdminSshPublicKey` | Complete approved OpenSSH public key. |
| `PostgresLocation` | Optional regional override. |
| `PostgresAdminPassword` | Protected ARM-template input, at least 16 characters. Never display it to learners, pass it on the command line, or write it to logs. |
| `RecommendationsMode` | Prepared-state value `unavailable`. |
| `CALDOVA_AZURE_MUTATION_ENABLED` | Set to the exact value `YES` in the prepared learner environment. |
| `CALDOVA_AZURE_TARGET` | Set to the exact value `skillable` in the prepared learner environment. |

The Azure identity must be authenticated before orchestration and authorized for the subscription deployment, learner resource group, both SRE Agent resources, Azure Monitor, and the required data-plane configuration.

`infra/skillable.bicep` does not create an empty per-instance registry. It grants each learner deployment's user-assigned application identity `AcrPull` on the event-managed registry, then configures Container Apps to use that identity. Event operations must replicate the approved immutable images into that registry before launching instances.

## Provision, configure, prepare, readiness

The Skillable cloud resource template runs `infra/skillable.bicep` as the **Provision** stage. After that deployment succeeds, run these workstation actions in order:

```powershell
pwsh -NoProfile -File scripts/initialize-skillable-state.ps1 `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -LearnerNumber $LearnerNumber `
    -DeploymentToken $DeploymentToken `
    -PortalImage $PortalImage `
    -ApiImage $ApiImage `
    -ApiLatencyImage $ApiLatencyImage `
    -ImageRegistrySubscriptionId $ImageRegistrySubscriptionId `
    -ImageRegistryResourceGroupName $ImageRegistryResourceGroupName `
    -ImageRegistryName $ImageRegistryName `
    -QuizLatencyThresholdMs 900

pwsh -NoProfile -File scripts/configure.ps1 -LearnerNumber $LearnerNumber
pwsh -NoProfile -File scripts/prepare.ps1 -LearnerNumber $LearnerNumber
pwsh -NoProfile -File scripts/readiness.ps1 -LearnerNumber $LearnerNumber
```

The ordered contract is:

1. Skillable deploys the RG-scoped compiled `infra/skillable.bicep` artifact.
2. `scripts/initialize-skillable-state.ps1` validates the deployment and writes the non-secret local state contract.
3. `scripts/configure.ps1`
4. `scripts/prepare.ps1`
5. `scripts/readiness.ps1`

The completion output hands off learner-specific portal, Preconfigured-agent, Configure-agent, and simulator links. It never prints the PostgreSQL password, access tokens, connector credentials, or secret values.

`scripts/skillable-orchestrate.ps1` remains an operator rehearsal path for a fresh subscription-scoped deployment. Do not run it after the Skillable cloud resource template, because that would attempt a second infrastructure deployment.

## Simulator handoff

Start one attached simulator process on the learner workstation:

```powershell
pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber $LearnerNumber
```

The wrapper verifies both the learner URL and `/api/status` through real HTTP before opening or printing:

```text
http://127.0.0.1:7070/?learnerNumber=$LearnerNumber
```

The process remains attached to the terminal. Ctrl+C stops it; no background detachment or scheduled process is created. For operator-only local validation, add `-Mock -NoBrowser`.

The 50-minute Configure module must use exactly one scenario. Keep the default **Course recommendations are unavailable** scenario. All other packaged scenarios are four-hour-path or post-lab practice. The learner screenshot sequence is Configure BEFORE → each manual alert/skill/agent/connector/response-plan action → Preconfigured AFTER evidence.

## Reset and teardown

Reset is separate from orchestration and must complete before another scenario or learner:

```powershell
pwsh -NoProfile -File scripts/reset.ps1 -LearnerNumber $LearnerNumber -Scenario api-latency
```

Pass the exact scenario id selected in the simulator. Reset invokes the scenario reset implementation and then reruns readiness.

Teardown is also separate. For a Skillable deployment it first removes only that learner identity's `AcrPull` assignment from the event-managed registry, then deletes the validated learner resource group:

```powershell
pwsh -NoProfile -File scripts/teardown.ps1 -LearnerNumber $LearnerNumber -Force
```

Do not combine reset and teardown with the provision/configure/prepare/readiness wrapper.

## Offline package contract

The packaged repository must include all application lockfiles and source artifacts. The image must include:

- populated npm cache entries for both lockfiles;
- installed global Azure MCP package at the pinned version;
- installed approved `srectl`;
- Azure CLI/Bicep binaries;
- no dependency on GitHub checkout, package registry access, or attendee credentials.

GitHub being unavailable does not block the lab. Learners read and author from local files, and the live exercise uses Azure SRE Agent, Azure Monitor, and the local simulator.

## Platform responsibility boundary

Skillable owns image preparation, immutable application images, provisioning, agent/report/task configuration, prepared-state creation, readiness, and cleanup. The attendee owns only the documented simulator and Azure SRE Agent interactions. Attendees do not install tools, handle deployment credentials, author infrastructure, or teardown resources.

## Concurrency and isolation

- Use one learner number, deployment token, resource group, pair of agents, and `.caldova/state-userN.json` per learner.
- Do not reuse a learner number concurrently on the same workstation.
- The simulator uses per-learner file locks and rejects overlapping operations.
- Use a different local port with `-Port` only when an operator intentionally hosts multiple isolated simulator processes.
- Never share `.caldova/` state between learner workstations.

## Diagnostics

| Failure | Operator action |
|---|---|
| Prerequisite check reports a missing or wrong tool | Repair the image; do not ask the attendee to download it. |
| `npm ci --offline` misses a package | Repopulate the image npm cache from the committed lockfiles. |
| Provision fails | Inspect the named subscription deployment and image references; do not continue to Configure. |
| Configure reports provider/API or endpoint unavailable | Confirm Microsoft.App registration, preview availability, identity permissions, and both agent provisioning states. |
| Prepare reports an unhealthy path or missing heartbeat | Inspect the workload before admitting the learner. |
| Readiness fails | Use every listed failure; readiness intentionally aggregates actionable evidence. |
| Simulator URL does not answer | Check port ownership, Node.js, and the attached terminal output. |
| Reset fails | Keep the learner environment out of rotation until the exact scenario reset and readiness both pass. |
