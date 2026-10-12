# Completed investigation example

This example demonstrates evidence quality and report structure. It is not a diagnosis for any simulator scenario.

## Symptom and scope

- User-visible symptom: quiz launch requests are not completing normally.
- Scope: one learner resource group.
- Incident time: record the Azure Monitor fired time before querying telemetry.

## Evidence set

1. Record the public request result and observation time.
2. Record Application Gateway backend health.
3. Record active Container Apps revisions, images, replicas, and health.
4. Query the matching Application Insights window by component `appId` and Log Analytics window by workspace `customerId`.
5. Check adjacent data, network, identity, and reporting signals only as needed.
6. Mark any unavailable query, permission, or timestamp as **missing evidence**.

## Decision and action

- State one evidence-backed hypothesis and its confidence.
- Propose the smallest reversible action inside the learner resource group.
- State the rollback before a write.
- Do not retrieve secret values or broaden permissions.

## Verification

- Re-run the original learner-visible request.
- Confirm healthy telemetry and resource state.
- Confirm `monitorCondition=Resolved`.
- If the recovered alert remains `New` or `Acknowledged`, use the supported Alerts Management `changeState` operation and verify `alertState=Closed`.
- Retain the completed incident thread; no supported incident-thread close mutation is assumed.
- Report **service recovery** separately from **root-cause confidence**.

## Incident summary and closure ledger

Use the `incident-summary` skill in the same thread and record:

- executive summary and customer impact;
- UTC timeline;
- confirmed root cause and 5 Whys;
- reversible mitigation and rollback;
- before/after public and telemetry evidence;
- follow-up recommendations and owners;
- missing evidence or permission gaps;
- alert ID, incident/thread ID, final monitor condition, final alert state, and verification timestamp.
