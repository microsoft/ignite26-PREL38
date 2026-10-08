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
4. Query the matching Application Insights and Log Analytics window.
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
- Confirm the alert condition is no longer present.
- Report **service recovery** separately from **root-cause confidence**.

