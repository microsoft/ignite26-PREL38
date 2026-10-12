# Simulator and reset

Use the local packaged simulator; GitHub is not required.

> [!IMPORTANT]
> Run exactly one scenario in the 50-minute module. Keep the default **Course recommendations are unavailable** scenario. The other scenarios are extended/four-hour-path or post-lab practice.

## Start and select

```powershell
pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber N
```

1. Confirm the learner number.
2. Select **Preconfigured** or **Configure**.
3. Keep the default guided scenario.
4. Select **Check configuration**.
5. Select **Start scenario** once.

The guided feature is isolated: health, readiness, courses, quizzes, database-backed operations, reporting, and Application Gateway remain healthy.

On the initial run, Start creates deterministic Application Insights evidence immediately. No alert or automatic incident is expected. After the Configure path creates and enables the exact alert and response chain, the second run waits for a fresh incident.

## Alert timing

| Stage | Typical time |
|---|---:|
| Azure Monitor evaluation interval | 5 minutes |
| Symptom to alert | 5–10 minutes |
| Alert to incident thread | about 1–2 minutes |
| Investigation and permitted mitigation | 3–10 minutes |
| Healthy recovery to monitor resolution | 5–20 minutes |

Continue configuration or evidence inspection while propagation is pending. Do not refresh repeatedly and do not start a second scenario.

## Progress and cancellation

- Start is asynchronous and selectors remain locked until Reset.
- The progress region reports configuration, state capture, symptom activation, evidence generation, and alert detection when configured.
- Cancel stops the running operation. Run Reset before retrying.
- **Open investigation in Azure SRE Agent** opens the selected agent.

## Reporting incident fallback

The reporting scenario normally routes automatically through the enabled Caldova response plan. If the alert has fired or been acknowledged but no incident thread appears after a bounded supported thread-list wait, a facilitator may use the supported `sreagent incidents create` operation with the exact alert ID and scope.

This is an operator recovery for a product-ingestion gap, not the normal learner flow. Record that the thread was created through the fallback and preserve the original alert evidence.

## Recovery and reset

1. Apply or request only the evidence-backed reversible recovery.
2. Select **Check recovery**.
3. Require **Recovery verified**.
4. Select **Reset**, confirm, and wait for **Baseline restored**.

The Skillable preparation workflow—not attendee Reset—returns course recommendations to the intentionally degraded prepared state for the next fresh lab instance.
