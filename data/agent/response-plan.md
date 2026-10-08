# Caldova Azure Monitor response plan

## Trigger

Start when an Azure Monitor incident targets a Caldova symptom-only alert in the learner resource group.

## Investigate

1. Capture the incident title, fired time, affected resource, and alert query.
2. Query the corresponding telemetry window in Log Analytics or Application Insights.
3. Inspect the live Application Gateway, Container Apps, PostgreSQL, VM, VNet, NSG, and Key Vault configuration relevant to the symptom.
4. Identify one evidence-backed cause and one reversible recovery action.

## Act

1. State the proposed change and rollback.
2. Apply the minimum scoped change.
3. Do not create integrations or resources outside the learner resource group.

## Verify

1. Re-run the public health check.
2. Confirm healthy application or worker telemetry.
3. Confirm the alert condition is no longer present.
4. Record the evidence, action, result, and any follow-up.
