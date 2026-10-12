# Caldova Azure Monitor response plan

## Trigger

Start when an Azure Monitor incident targets a Caldova symptom-only alert in the learner resource group.

## Investigate

1. Capture the incident title, fired time, affected resource, and alert query.
2. Query Log Analytics with the workspace `customerId` GUID and Application Insights with the component `appId`; resource names are not query identifiers.
3. Inspect the path in order: Application Gateway health and configuration, VNet/route/NSG state, Container Apps revisions/replicas/images, then PostgreSQL or reporting-worker evidence when relevant.
4. Use Microsoft Learn only for supported product behavior that needs confirmation.
5. Identify one evidence-backed cause and one reversible recovery action. Label missing access or telemetry as an evidence gap, never a clean result.

## Act

1. State the proposed change and rollback.
2. Apply the minimum scoped change.
3. Do not create integrations or resources outside the learner resource group.
4. Do not broaden role assignments, retrieve secret values, or use an undocumented API.

## Verify

1. Re-run the public health check.
2. Confirm healthy application or worker telemetry.
3. Confirm the alert condition is no longer present.
4. For a recovered Azure alert that is still `New` or `Acknowledged`, use the supported Alerts Management `changeState` operation to set `newState=Closed`.
5. Verify `monitorCondition=Resolved` and `alertState=Closed`. Do not delete the completed incident thread, and do not invent an unsupported thread-close endpoint.
6. Invoke the `incident-summary` skill and record the executive summary, UTC timeline, confirmed root cause, 5 Whys, mitigation, before/after evidence, recommendations, remaining gaps, and closure ledger.

## Ownership

- The Preconfigured Agent owns the enabled response plan, incident skills, custom responder, weekly tasks, and reports.
- The Configure Agent starts with evidence context and onboarding only; the learner authors its operational artifacts.
- Agent tools are declared on the `ExtendedAgent`. Skills describe ordered procedures and inherit those tools.
