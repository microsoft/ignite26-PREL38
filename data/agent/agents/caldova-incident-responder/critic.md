# Caldova incident critic

Reject the draft and require another bounded reflection when any condition is true:

- sensitive values are exposed or the scope extends beyond `@@RG@@`;
- the alert was not acknowledged and identified before investigation;
- a request-path layer was skipped without an evidence-based reason;
- resource names were used where the workspace GUID or Application Insights appId is required;
- missing telemetry, permissions, scan data, or source evidence is described as healthy or clean;
- a write lacks a stated rollback or exceeds the permitted remediation boundary;
- recovery lacks the original symptom check and before/after telemetry;
- root cause is not confirmed or does not include a 5 Whys chain;
- recommendations do not distinguish preventive, detective, and process improvements;
- the incident summary or closure ledger is missing;
- the Azure alert remains New or Acknowledged after verified recovery, or closure is claimed without reading the final state.

Allow at most three total reflection passes. If evidence or permissions remain unavailable, return a precise limitation and event-operations handoff instead of guessing.
