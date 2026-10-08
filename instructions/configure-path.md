# Configure Agent path

**Time:** 45–60 minutes  
**Use:** `sre-caldova-config-userN`, where `N` is your learner number.

Complete this path only. Create one bounded response configuration and run exactly one live simulator scenario.

## 1. Review Caldova context

Read:

- [`../docs/architecture.md`](../docs/architecture.md)
- [`../docs/application-baseline.md`](../docs/application-baseline.md)
- [`../src/portal/server.js`](../src/portal/server.js)
- [`../src/api/server.js`](../src/api/server.js)
- [`../data/agent/source-context.md`](../data/agent/source-context.md)

The lab pre-run has already applied the secure Azure MCP and Microsoft Learn connectors plus the Caldova source context to the Configure-path agent. In the agent, confirm the context is present and scoped to your learner resource group. If the context is missing, add the checked-in document with the supported Azure MCP command:

```powershell
$state = Get-Content ".caldova/state-userN.json" -Raw | ConvertFrom-Json
$content = (Get-Content "data/agent/source-context.md" -Raw).Replace('@@RG@@', $state.resourceGroupName)
azmcp sreagent docs memories_add `
  --name caldova-architecture `
  --content $content `
  --agent $state.configuredAgentName `
  --subscription $state.subscriptionId `
  --resource-group $state.resourceGroupName
```

Replace `N` in the state-file name with your learner number. Do not add credentials, external incident platforms, or resources outside that group.

## 2. Create one bounded response configuration

Use the checked-in authoring artifacts:

| Create | Starter to review | Native reference |
|---|---|---|
| One skill | [`incident-triage-skill.md`](../data/agent/incident-triage-skill.md) | [`skills/caldova-incident-triage/SKILL.md`](../data/agent/skills/caldova-incident-triage/SKILL.md) |
| One custom agent | [`source-context.md`](../data/agent/source-context.md) | [`caldova-incident-responder.yaml`](../data/agent/agents/caldova-incident-responder/caldova-incident-responder.yaml) |
| One Azure Monitor response plan | [`response-plan.md`](../data/agent/response-plan.md) | [`caldova-azure-monitor-response.yaml`](../data/agent/incident-filters/caldova-azure-monitor-response.yaml) |

Keep the native kinds and boundaries shown in the references:

- skill: `api_version: azuresre.ai/v2`, `kind: Skill`;
- custom agent: `api_version: azuresre.ai/v2`, `kind: ExtendedAgent`;
- response plan: `api_version: azuresre.ai/v2`, `kind: IncidentFilter`, `incidentPlatform: AzMonitor`;
- one learner resource group only;
- symptom-first investigation, smallest reversible action, and explicit verification;
- no secret retrieval, IAM changes, data deletion, or cross-resource-group actions.

Use the SRE Agent authoring experience supplied on the workstation. The repository configurator proves the supported CLI contract with:

```text
srectl skill apply --name caldova-incident-triage --quiet
srectl agent apply --name caldova-incident-responder --quiet
srectl incident-filter apply --name caldova-azure-monitor-response --quiet
srectl incident-filter get --name caldova-azure-monitor-response
```

The native files must be in the `skills/`, `agents/`, and `IncidentFilters/` workspace layout used by [`../scripts/configure-agent.mjs`](../scripts/configure-agent.mjs). Replace `@@RG@@` only with your learner resource-group name. Do not invent another incident platform or unsupported tool name.

Review the completed examples after your version is saved:

- [Completed skill](../data/agent/skills/caldova-incident-triage/SKILL.md)
- [Completed custom agent](../data/agent/agents/caldova-incident-responder/caldova-incident-responder.yaml)
- [Completed response plan](../data/agent/incident-filters/caldova-azure-monitor-response.yaml)
- [Completed investigation example](../data/agent/investigation-example.md)

## 3. Run one incident

1. Start the simulator:

   ```powershell
   pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber N
   ```

2. Select **Configure** and one scenario.
3. Select **Check configuration**. A missing or mismatched Azure Monitor response plan blocks Start with an actionable message.
4. When the status is **Ready**, select **Start scenario** once.
5. Open the investigation link, follow the live investigation, and evaluate the evidence, proposed action, rollback, and verification.
6. After the agent reports recovery, select **Check recovery**.
7. When recovery is verified, complete the confirmed **Reset**.

See [Simulator and reset](simulator-and-reset.md) for timing, progress, cancellation, and reset behavior.

> **Knowledge check (optional):** Which constraint in your skill or custom agent prevents an unrelated alert from causing a broad change?
