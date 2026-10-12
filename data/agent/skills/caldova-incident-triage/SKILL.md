---
metadata:
  api_version: azuresre.ai/v2
  kind: Skill
name: caldova-incident-triage
description: Investigate and recover a Caldova symptom-only Azure Monitor incident within the learner resource group. Correlate Application Gateway, Container Apps, PostgreSQL, reporting-worker, network, Key Vault, Application Insights, and Log Analytics evidence before taking the smallest reversible action.
---

# Caldova incident triage

Resource group: `@@RG@@`.

The alert is symptom-only. Never infer the cause from its title. Build a timestamped evidence set from Azure Monitor and current Azure resource configuration, compare the web, data, and reporting-worker paths, and identify one evidence-backed cause.

## Ordered investigation

1. Redact sensitive fields and acknowledge the alert. Record alert ID, alert state, fired UTC, severity, affected resource, public symptom, and investigation owner.
2. Load `caldova-operations-handbook` and use its workspace GUID and Application Insights appId. Never pass a resource name where a GUID or appId is required.
3. Reproduce the symptom with a timestamped, read-only request.
4. Inspect the request path in order:
   - Application Gateway listener, routing rule, backend health, probe, access logs, and 4xx/5xx metrics.
   - VNet, subnet, NSG priorities/effective rules, UDRs, DNS resolution, and private endpoints.
   - Container Apps revisions, traffic weights, replicas, images/digests, environment variables by name only, restarts, console traces, request latency, and dependencies.
   - PostgreSQL availability, connection failures, storage/connection saturation, and application dependency evidence.
   - Reporting worker service state, disk, heartbeat, exports, and Syslog when the reporting path is affected.
5. Build a UTC timeline and explicitly mark each item as confirmed, inferred, or missing.
6. Confirm healthy adjacent layers and select one root cause only when the evidence explains the symptom and timing.
7. State the smallest reversible mitigation, expected effect, rollback, and verification plan before a write.
8. Apply at most two bounded mitigation attempts. Reflect after an error; never broaden permissions or scope to make a write succeed.

## Action boundary

- Act only inside `@@RG@@`.
- Prefer non-destructive updates and restarts.
- Do not change IAM, VNet address spaces, service tiers, or delete data.
- Do not expose secrets or retrieve secret values.
- State the evidence, action, and rollback before a write.
- Use Azure CLI help before an unfamiliar command. Use read commands for diagnosis and write commands only for the approved mitigation.

## Verification

1. Re-run the original symptom check and record the before/after result.
2. Confirm healthy resource state and telemetry for the affected path.
3. Verify the Azure Monitor condition has cleared.
4. Invoke `incident-summary`.
5. Close the Azure alert only after recovery, then read it back and require `alertState=Closed`.
6. Verify the incident thread is resolved/closed when a supported incident mutation exists. Otherwise preserve the thread and record the exact limitation.

Report service recovery, root-cause confidence, and closure status separately.
