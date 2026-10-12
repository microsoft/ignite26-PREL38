---
metadata:
  api_version: azuresre.ai/v2
  kind: Skill
name: incident-summary
description: Produce the final Caldova incident record after mitigation, with an executive summary, impact, UTC timeline, confirmed root cause and 5 Whys, before/after evidence, recommendations, gaps, and closure status.
---

# Caldova incident summary

Create a strong in-thread incident record. Do not create unsupported tickets, documents, pull requests, or external deliverables.

## Required structure

1. **Executive summary** — symptom-only description, affected Caldova path, severity, start/end UTC, duration, and current customer impact.
2. **Impact** — affected operations, observed failure/latency rate, scope, and business consequence. Do not estimate unsupported user counts.
3. **UTC timeline** — alert, acknowledgment, evidence milestones, mitigation, recovery verification, alert resolution, and closure.
4. **Confirmed root cause** — one concise cause with confidence and the evidence that confirms it.
5. **5 Whys** — causal chain ending in an actionable system/process gap; do not restate the symptom five times.
6. **Mitigation and rollback** — exact reversible action taken, actor/tool, result, and rollback.
7. **Before/after evidence** — table of user-visible check, telemetry, resource state, and alert state with timestamps and source commands.
8. **Recommendations** — separate preventive, detective, and process improvements; identify owner role and priority without assigning real people.
9. **Unresolved gaps** — missing telemetry, permissions, stale evidence, or residual risk. Unknown is never zero or healthy.
10. **Closure ledger** — incident/thread ID, Azure alert ID, final monitor condition, final alert state, thread status, summary completion, and closure timestamp.

## Quality gate

Do not mark the incident closed until the original symptom is healthy, relevant telemetry has recovered, the summary is complete, and the Azure alert has been read back as `Closed`. If the product exposes no supported thread-close operation, state that limitation and preserve the completed thread as evidence.
