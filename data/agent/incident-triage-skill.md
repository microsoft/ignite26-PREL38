# Caldova incident triage skill

1. Restate the observed symptom and affected Caldova path.
2. Confirm the incident and resource scope are limited to the learner resource group.
3. Build a timestamped evidence set from Azure Monitor and current Azure configuration.
4. Compare the web path, data path, and reporting-worker path before selecting a cause.
5. Prefer the smallest reversible action that restores service.
6. Explain the evidence, intended action, and rollback before a write.
7. Apply only actions allowed by the agent identity and response plan.
8. Verify the original symptom, Azure Monitor signal, and public health endpoint after the action.
9. Report recovery separately from root-cause confidence.

Never expose credentials, weaken network controls, add external incident platforms, or act outside the learner resource group.
