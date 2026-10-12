# Course recommendations guided response reference

These artifacts support the Configure Agent learning exercise and the Preconfigured completed AFTER-state. The main `scripts/configure-agent.mjs` lifecycle does **not** apply them during initial lab preparation. They remain excluded from `data/agent/configuration.json`; `scripts/configure-guided-recommendations.ps1` applies them only to the Preconfigured Agent during AFTER-state preparation.

The Configure Agent before-state has:

- an isolated `GET /api/recommendations/health` symptom;
- core Caldova health, readiness, courses, quizzes, database, reporting, and gateway paths healthy;
- no `Course-recommendations-unavailable` alert;
- no `course-recommendations-recovery` skill;
- no `caldova-guided-feature-responder` custom agent;
- no `course-recommendations-learning-response` incident response plan.

The Preconfigured AFTER-state keeps the skill and custom agent visible but leaves the guided alert and response plan disabled. This preserves the default evidence-only experience while showing the completed configuration. The alert name intentionally omits `Caldova`, so it does not match the prepared `caldova-azure-monitor-response` plan whose title filter is `Caldova`.

## Lifecycle helper

```powershell
pwsh -NoProfile -File scripts/configure-guided-recommendations.ps1 -LearnerNumber N -Operation Apply
pwsh -NoProfile -File scripts/configure-guided-recommendations.ps1 -LearnerNumber N -Operation Enable
pwsh -NoProfile -File scripts/configure-guided-recommendations.ps1 -LearnerNumber N -Operation Verify -Expected enabled
pwsh -NoProfile -File scripts/configure-guided-recommendations.ps1 -LearnerNumber N -Operation Disable
pwsh -NoProfile -File scripts/configure-guided-recommendations.ps1 -LearnerNumber N -Operation Verify -Expected disabled
```

`Apply` is idempotent, registers the managed-identity `caldova-guided-alerts` connector on Preconfigured, and restores Configure Agent isolation. The connector exposes only one mutation: close the exact resolved guided alert in the configured learner resource group. `Enable` activates the exact alert-to-plan chain for the automatic exercise. `Disable` turns off routing first, then alert evaluation, and closes any recovered guided alert state without deleting incident evidence.

## Reference artifacts

| Artifact | File | Learner action |
|---|---|---|
| App Insights alert | [`alert.bicep`](alert.bicep) | Create manually after the first evidence-only investigation. |
| Diagnostic/remediation skill | [`skill/SKILL.md`](skill/SKILL.md) | Create or paste in the Skills authoring experience. |
| Custom agent | [`agent/caldova-guided-feature-responder.yaml`](agent/caldova-guided-feature-responder.yaml) | Configure with agent-owned Azure CLI tools. |
| Alert closure tool | [`../../../scripts/caldova-guided-alerts-mcp.py`](../../../scripts/caldova-guided-alerts-mcp.py) | Register on Preconfigured with its managed identity; reject non-guided, active, or out-of-scope alerts. |
| Azure Monitor response plan | [`incident-filter/course-recommendations-learning-response.yaml`](incident-filter/course-recommendations-learning-response.yaml) | Connect only the exact guided alert to the guided custom agent and skill. |
| Completed example | [`completed-example.md`](completed-example.md) | Compare after completing the manual investigation and authoring steps. |

Replace `@@RG@@` and `@@APP_INSIGHTS_ID@@` only with values from the learner state and Azure resource inventory. Do not add credentials or broaden the scope.
