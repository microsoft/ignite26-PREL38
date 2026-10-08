# Facilitator scenario slice

The learner UI intentionally exposes neutral symptoms only. Use this mapping only for facilitation and Azure validation.

| Choice | Planted condition | Snapshot and recovery contract | Detection |
|---|---|---|---|
| Scenario 1 | Adds only `caldova-quiz-launch-scenario-1` at priority 220 on the internal Container Apps subnet policy. The baseline gateway allow remains at 300; NRMS-reserved priorities 101–109 are never mutation targets. | Discovers the learner VNet, delegated application subnet, attached policy, and entry subnet from tags/prefixes and live relationships. Snapshot-less reset deletes only a rule matching the complete planted fingerprint. | Shared `Caldova-quiz-launch-failing` one-minute workspace query over Application Gateway access records for 5xx responses on `/api/quiz/` only |
| Scenario 2 | Changes the single health-check path referenced by the active backend settings to `/caldova-scenario-2-unavailable`. | Saves the complete health-check object plus its original path. Fix/Reset restore the captured path and verify read-back. | Shared `Caldova-quiz-launch-failing` one-minute workspace query over Application Gateway access records for 5xx responses on `/api/quiz/` only |
| Scenario 3 | Captures the quiz API image, replica bounds, revision mode, and active healthy state, switches to multiple-revision mode, then deactivates only the captured state. | Fix/Reset create a ready state from the pinned image and exact bounds, restore the captured revision mode, and verify readiness. No application or revision is deleted. | Shared `Caldova-quiz-launch-failing` one-minute workspace query over Application Gateway access records for 5xx responses on `/api/quiz/` only |
| Quiz search responses are slow | Removes only `idx_question_bank_assessment_active`, the lab-owned composite lookup for the 120,000-row question bank, through `az containerapp exec`. | Saves the exact index identity and refuses to start unless it exists. Fix/Reset run the checked-in `CREATE INDEX IF NOT EXISTS`, `REINDEX`, and `ANALYZE`, then measure public latency. | Existing `Caldova-quiz-response-time-elevated` one-minute rule |
| Quiz requests fail intermittently | Creates a bounded API revision with a pool size of 1, a 250 ms acquisition timeout, and a 1.5 second per-request hold; sends only 12 concurrent requests. | Saves presence/value for only the three changed environment variables plus image and revision metadata. Restore sets original values or removes only variables that were absent. | Shared `Caldova-quiz-launch-failing` one-minute failed-request metric |
| Quiz requests fail consistently | Repoints only the API’s existing managed credential reference to a nonexistent version and restarts only the captured active revision. | Saves the exact Key Vault URI, identity reference, API secretRef, revision mode, and revision names. Restore reapplies the exact reference and restarts the same captured revision. No secret value is read, written to state, or logged. | Shared `Caldova-quiz-launch-failing` one-minute failed-request metric |
| Grade reports are missing | Fills only the dedicated 8 GiB export data volume with `/var/lib/caldova/.caldova-reporting-output-missing.filler`, then runs the worker once. | Verifies `/var/lib/caldova` is a mount, removes only the named filler, starts the worker, and requires both a new CSV and recent `caldova-reporting` success heartbeat. The OS volume is never targeted. | `Caldova-reporting-output-missing`, one-minute missing-success/failure rule |

All Start operations validate the selected agent and response plan, capture ownership once, prove a healthy baseline, generate bounded traffic or a controlled heartbeat, and wait for a fresh alert. Application Gateway access diagnostics emit one record for each public request, so each path-isolation scenario produces the same quiz-specific signal even when traffic never reaches the portal. The query excludes non-quiz routes and non-5xx responses, including unrelated portal 404s. Related quiz failures intentionally share one symptom alert so one injected failure cannot create duplicate investigations. Private PostgreSQL actions run inside the API container; the learner workstation never needs network access or `psql`. Azure mutation remains gated by `CALDOVA_AZURE_MUTATION_ENABLED=YES` and `CALDOVA_AZURE_TARGET=skillable`.

## Delivery sequence

- Preconfigured path: 25–35 minutes.
- Configure path: 45–60 minutes.
- Learners choose one path and exactly one live scenario.
- Allow 3–7 minutes for injection and 1–8 minutes for alert detection.
- Require **Recovery verified**, then a confirmed Reset and passing readiness before the environment is reused.
- If GitHub is unavailable, continue from the packaged local repository; GitHub is not required for either learner path.

See [Facilitator troubleshooting](troubleshooting.md) for readiness, configuration, simulator, and reset failures.

## Azure-only acceptance checks

1. Seed confirms exactly 120,000 question-bank rows and the named lookup exists.
2. Slow-search Start measures median latency at or above the catalog threshold; Fix measures below recovery threshold.
3. Bounded-pressure Start records at least one success and one failure from exactly 12 requests.
4. Credential-reference Start returns consistent learner-visible failures without emitting credential values.
5. Reporting Start confirms the filler is on `/var/lib/caldova`, the alert fires within the expected window, and Fix produces a new export plus a success heartbeat.
