# Facilitator troubleshooting

Learner-facing instructions use symptom-only names. This facilitator document may use implementation details to diagnose setup and reset failures.

## Sequencing and timing

1. Image authoring/pre-run: offline setup and prerequisite check.
2. Per learner: provision → configure → prepare → readiness.
3. Learner: choose one path and one scenario.
4. Investigation: allow the catalog’s 3–7 minute injection and 1–8 minute detection windows.
5. Recovery check.
6. Confirmed reset and readiness before another scenario or learner.

Do not bypass readiness to save time. A learner should not start when the healthy image, public route, database check, reporting volume, heartbeat, alert rules, or either agent is unavailable.

## Common failures

| Signal | Likely area | Action |
|---|---|---|
| Node, PowerShell, Azure CLI/Bicep, Azure MCP, or srectl check fails | Workstation image | Repair during image authoring/pre-run. Attendee-time downloads are unsupported. |
| npm dependency check fails | Offline cache or pre-run | Run `scripts/setup-workstation.ps1` only after the lockfile packages are cached. |
| Configure cannot read an agent endpoint | SRE Agent provisioning/provider access | Verify `Microsoft.App/agents` preview access, `Succeeded` state, one user-assigned identity, and the active Azure identity. |
| Configure-path Start remains blocked | Learner artifact ownership | Confirm the Configure agent has the expected enabled Azure Monitor incident filter and custom agent. |
| Public health or ready check fails before injection | Gateway, portal, API, or data baseline | Restore baseline before the learner starts. |
| Reporting readiness fails | VM, timer, mount, managed identity, database, or Log Analytics ingestion | Inspect the VM state and latest `caldova-reporting` Syslog heartbeat. |
| Alert does not appear within the stated window | Telemetry, alert state, ownership, or ingestion | Confirm the rule is enabled, frequency is correct, fresh scoped telemetry exists, and one response-plan owner is assigned. |
| Simulator reports an existing operation | Per-learner lock | Wait, cancel from the UI, or complete reset; do not delete lock/state files while an Azure action may still be active. |
| Reset fails | Scenario-specific captured baseline or live recovery | Run the exact scenario reset, preserve its actionable output, and rerun readiness before reuse. |

For the planted-condition mapping and Azure acceptance checks, use [Facilitator scenario slice](facilitator-scenarios.md).

## GitHub-unavailable fallback

The attendee exercise does not require GitHub. Use the packaged local repository for source, architecture, native SRE Agent artifacts, and instructions. Use the local simulator wrapper and the Azure SRE Agent portal links emitted by orchestration. Do not ask learners to clone, pull, open a pull request, or install packages.

