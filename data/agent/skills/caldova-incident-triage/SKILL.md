---
metadata:
  api_version: azuresre.ai/v2
  kind: Skill
name: caldova-incident-triage
description: Investigate and recover a Caldova symptom-only Azure Monitor incident within the learner resource group. Correlate Application Gateway, Container Apps, PostgreSQL, reporting-worker, network, Key Vault, Application Insights, and Log Analytics evidence before taking the smallest reversible action.
tools:
  - azure-mcp_azure
  - SearchMemory
---

# Caldova incident triage

Resource group: `@@RG@@`.

The alert is symptom-only. Never infer the cause from its title. Build a timestamped evidence set from Azure Monitor and current Azure resource configuration, compare the web, data, and reporting-worker paths, and identify one evidence-backed cause.

## Investigation

1. Restate the observed symptom, affected path, and incident time.
2. Query Application Insights and Log Analytics for the matching window.
3. Inspect the relevant Application Gateway, Container Apps, PostgreSQL, VM, VNet, NSG, and Key Vault configuration.
4. Confirm healthy adjacent layers before attributing the cause.
5. Propose the smallest reversible recovery action and its rollback.

## Action boundary

- Act only inside `@@RG@@`.
- Prefer non-destructive updates and restarts.
- Do not change IAM, VNet address spaces, service tiers, or delete data.
- Do not expose secrets or retrieve secret values.
- State the evidence, action, and rollback before a write.

## Verification

Re-run the original health check, confirm healthy telemetry, and verify the Azure Monitor alert condition has cleared. Report service recovery separately from root-cause confidence.
