# Preconfigured Agent path

**Time:** 25–35 minutes  
**Use:** `sre-caldova-prerun-userN`, where `N` is your learner number.

Complete this path only. Run exactly one live simulator scenario.

## 1. Review the prepared operating context

Open these local files:

- [`../docs/architecture.md`](../docs/architecture.md)
- [`../docs/application-baseline.md`](../docs/application-baseline.md)
- [`../src/portal/server.js`](../src/portal/server.js)
- [`../src/api/server.js`](../src/api/server.js)
- [`../data/agent/source-context.md`](../data/agent/source-context.md)

Ask the prepared agent only the following operational questions. Require current evidence and timestamps; if evidence is unavailable, require the agent to say what is missing rather than infer an answer.

1. **Resource inventory:** “Inventory the Caldova resources in my learner resource group and group them by role: entry point, application, data, identity/secrets, reporting, and observability.”
2. **Gateway and revisions:** “Report current Application Gateway backend health and the active Azure Container Apps revisions. Include resource names, health state, revision names, images, replica state, and observation time.”
3. **Alerts:** “List enabled Caldova alerts with severity, evaluation frequency, and the user-visible symptom each detects.”
4. **Quiz-launch path:** “From the checked-in source and deployed configuration, describe the expected request path for launching quiz `OPS-201-M1`. Separate source evidence from live Azure evidence.”
5. **Reporting evidence:** “Report the reporting VM power/provisioning state and the latest successful reporting heartbeat time. If either cannot be proven, explicitly report the missing evidence and the query or permission needed.”

## 2. Review the completed response configuration

Review the prepared examples before the live exercise:

- [Structured skill](../data/agent/skills/caldova-incident-triage/SKILL.md)
- [Custom agent](../data/agent/agents/caldova-incident-responder/caldova-incident-responder.yaml)
- [Azure Monitor response plan](../data/agent/incident-filters/caldova-azure-monitor-response.yaml)
- [Completed investigation example](../data/agent/investigation-example.md)

Notice the bounded resource group, evidence-first investigation, reversible action, and separate recovery/root-cause confidence statements.

## 3. Run one incident

1. Start the simulator:

   ```powershell
   pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber N
   ```

   Replace `N` with your assigned learner number.

2. In the simulator, select **Preconfigured**.
3. Select one scenario and keep that selection for the entire exercise.
4. Select **Check configuration**. Do not continue until the status is **Ready**.
5. Select **Start scenario** once. Start is asynchronous; keep the page and terminal open.
6. When the investigation link appears, open it and review the live evidence, proposed action, rollback, and verification.
7. After the agent reports recovery, select **Check recovery**.
8. When recovery is verified, complete the confirmed **Reset**.

See [Simulator and reset](simulator-and-reset.md) for timing and cancellation behavior.

> **Knowledge check (optional):** Which statement in the investigation was directly supported by live evidence, and which statement had the lowest confidence?

