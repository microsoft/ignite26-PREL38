# Configure Agent path

**Time:** 50 minutes
**Use:** `sre-caldova-config-userN`, where `N` is your learner number.

> [!IMPORTANT]
> Choose **exactly one scenario**. Keep the default **Course recommendations are unavailable** scenario. The 50-minute module does not allow time to complete every scenario. The remaining scenarios are optional four-hour-path or post-lab practice.

The default scenario is recommended because it gives you immediate Application Insights and configuration evidence before an alert exists, then supports the complete manual alert → skill → custom agent → incident response plan learning flow.

## Timing and timeboxes

| Activity | Timebox |
|---|---:|
| Review context and capture the before-state | 5 minutes |
| Run the evidence-only symptom and investigate | 8 minutes |
| Draft and save the reusable skill | 7 minutes |
| Create the alert, custom agent, connector, and response plan | 15 minutes |
| Reset, retrigger, review automatic handling, and clean up | 15 minutes |

Azure Monitor uses a **5-minute evaluation interval** for the exercise. Detection is typically **5–10 minutes**, the incident thread usually appears **1–2 minutes later**, investigation and mitigation take **3–10 minutes**, and monitor resolution can take **5–20 minutes** after recovery.

While propagation is pending, continue the next configuration or inspection step and return to the incident when it appears. Do not refresh repeatedly and do not start another scenario.

## 1. Review context and capture the before-state

Open **Getting started: Caldova operations**. Confirm:

- the assigned learner resource group;
- the Application Insights appId and source-evidence links;
- core health and readiness expectations;
- the Log Analytics runtime-query limitation: a 403 is missing access, never an empty or healthy result;
- safe evidence alternatives: Application Insights, Azure CLI/ARM, metrics, configuration, and clearly labeled VM journal fallback.

Review:

- [`../docs/architecture.md`](../docs/architecture.md)
- [`../docs/application-baseline.md`](../docs/application-baseline.md)
- [`../data/agent/source-context.md`](../data/agent/source-context.md)
- [`../data/agent/guided-course-recommendations/README.md`](../data/agent/guided-course-recommendations/README.md)

Open the portal. Confirm the optional **Course recommendations** card is degraded while health, readiness, courses, quizzes, database-backed operations, reporting, and Application Gateway remain healthy.

Capture the Configure Agent **before** screenshots from [Screenshot inventory](screenshot-inventory.md). Configure must have no guided skill, custom agent, alert, response plan, or incident thread.

## 2. Investigate the symptom manually

Start the simulator:

```powershell
pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber N
```

1. Select **Configure**.
2. Keep **Course recommendations are unavailable**.
3. Select **Check configuration**, then **Start scenario** once.
4. The first run creates deterministic evidence immediately. No alert or automatic incident is expected.
5. Ask:

   > Investigate why course recommendations are unavailable. Prove that core learning remains healthy, map the request and Azure resource path, use Application Insights plus current Container Apps configuration, separate confirmed evidence from inference, and propose the smallest reversible remediation. Do not use Log Analytics or make changes yet.

Require the agent to identify the non-secret configuration/revision setting, show the evidence timestamp, and state the rollback and post-fix checks.

## 3. Draft and apply the reusable skill

Ask:

> Draft a reusable skill for diagnosing and safely remediating this exact symptom. Include evidence order, the resource-group boundary, action and rollback, core-path isolation, post-fix checks, monitor resolution, and alert closure. Do not assign tools to the skill. Then explain how to create it manually.

Create the skill:

- Name: `course-recommendations-recovery`
- App Insights evidence first
- Azure configuration second
- Core-health isolation required
- No skill-owned tools

Compare with [`course-recommendations-recovery`](../data/agent/guided-course-recommendations/skill/SKILL.md).

## 4. Build the response chain manually

Create and capture each artifact separately.

### 4.1 Azure Monitor alert

- Name: `Course-recommendations-unavailable`
- Scope: learner Application Insights component only
- Signal: degraded `CaldovaRecommendationsHealth` evidence for `/recommendations/health`
- Evaluation interval: 5 minutes
- Window: 5 minutes
- Auto-resolution: enabled
- Initial state: disabled until the whole chain is connected
- Reference: [`alert.bicep`](../data/agent/guided-course-recommendations/alert.bicep)

### 4.2 Custom agent

- Name: `caldova-guided-feature-responder`
- Allowed skill: only `course-recommendations-recovery`
- Agent-owned tools: `RunAzCliReadCommands`, `RunAzCliWriteCommands`, `GetAzCliHelp`
- Additional evidence tools only as required for memory, Python, and Microsoft Learn
- No Azure MCP dependency
- Reference: [`caldova-guided-feature-responder.yaml`](../data/agent/guided-course-recommendations/agent/caldova-guided-feature-responder.yaml)

### 4.3 Alert-closure connector

Add `caldova-guided-alerts` with its managed identity. It exposes only `close_guided_alert`, rejects broader scopes or active alerts, and can close only the exact resolved guided alert.

### 4.4 Incident response plan

- Name: `course-recommendations-learning-response`
- Exact title match: `Course-recommendations-unavailable`
- Handling agent: `caldova-guided-feature-responder`
- Merge: disabled
- Initial state: disabled
- Reference: [`course-recommendations-learning-response.yaml`](../data/agent/guided-course-recommendations/incident-filter/course-recommendations-learning-response.yaml)

Connect alert → response plan → custom agent → skill, verify every link, then enable the alert and response plan.

The alert title intentionally does not match the prepared broad Caldova response plan. Do not create a broader filter or reuse that plan.

## 5. Reset, retrigger, and prove automatic handling

1. Select **Fix** if required, then **Reset**.
2. Select **Check configuration** again.
3. Select **Start scenario** once.
4. While the 5–10 minute alert window runs, inspect the saved skill, custom agent tools, connector scope, and response-plan links.
5. Verify:
   - a fresh alert;
   - the exact response plan;
   - guided custom agent and skill selection;
   - Application Insights and current configuration evidence;
   - the one-setting remediation and rollback;
   - HTTP 200, a ready revision, and healthy core paths;
   - monitor condition `Resolved`;
   - alert state `Closed`;
   - a completed incident summary.
6. Select **Check recovery**, then **Reset** and wait for **Baseline restored**.

If alert propagation is still pending near the end of the module, preserve the alert/investigation link, complete the configuration review, and hand the scenario to the facilitator for cleanup. Do not start another scenario.

## 6. Cleanup

Disable the response plan first and the alert second. Retain the completed skill, custom agent, connector, and incident evidence.

Facilitator/API lifecycle verification:

```powershell
pwsh -NoProfile -File scripts/configure-guided-recommendations.ps1 -LearnerNumber N -Operation Verify -Expected disabled
```

The helper prepares and verifies the **Preconfigured AFTER-state** only; it does not replace the learner’s manual Configure Agent steps.

## Evidence conventions

- **Before:** Configure Agent has no guided artifacts.
- **Manual steps:** capture each alert, skill, agent, connector, response-plan, link, and enable action.
- **After:** use the Preconfigured Agent reference artifacts and retained completed incident as the finished example.

Use [Screenshot inventory](screenshot-inventory.md) for exact filenames and callouts.
