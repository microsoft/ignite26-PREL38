# Facilitator scenario slice

The learner UI intentionally exposes neutral symptoms only. Use this mapping only for facilitation and Azure validation.

| Choice | Planted condition | Snapshot and recovery contract | Detection |
|---|---|---|---|
| Course recommendations are unavailable (default) | Sets only the API Container App's non-secret `CALDOVA_RECOMMENDATIONS_MODE` value to `unavailable`. The dedicated route returns 503; all core paths remain healthy. | Saves the setting presence/value and ready revision. Break is idempotent, produces deterministic App Insights requests, and does not wait when the guided alert is absent. Fix/Reset set `available`, require HTTP 200 plus core/gateway health, and Reset removes scenario state. | Initially none. After the learner creates `Course-recommendations-unavailable`, Start detects that exact rule and performs a bounded alert wait. The alert title intentionally does not match the prepared `titleContains: Caldova` response plan. |
| Scenario 1 | Adds only `caldova-quiz-launch-scenario-1` at priority 220 on the internal Container Apps subnet policy. The baseline gateway allow remains at 300; NRMS-reserved priorities 101–109 are never mutation targets. | Discovers the learner VNet, delegated application subnet, attached policy, and entry subnet from tags/prefixes and live relationships. Snapshot-less reset deletes only a rule matching the complete planted fingerprint. | Shared `Caldova-quiz-launch-failing` five-minute workspace query over Application Gateway access records for 5xx responses on `/api/quiz/` only |
| Scenario 2 | Changes the single health-check path referenced by the active backend settings to `/caldova-scenario-2-unavailable`. | Saves the complete health-check object plus its original path. Fix/Reset restore the captured path and verify read-back. | Shared `Caldova-quiz-launch-failing` five-minute workspace query over Application Gateway access records for 5xx responses on `/api/quiz/` only |
| Scenario 3 | Captures the quiz API image, replica bounds, revision mode, and active healthy state, switches to multiple-revision mode, then deactivates only the captured state. | Fix/Reset create a ready state from the pinned image and exact bounds, restore the captured revision mode, and verify readiness. No application or revision is deleted. | Shared `Caldova-quiz-launch-failing` five-minute workspace query over Application Gateway access records for 5xx responses on `/api/quiz/` only |
| Quiz search responses are slow | Removes only `idx_question_bank_assessment_active`, the lab-owned composite lookup for the 120,000-row question bank, through `az containerapp exec`. | Saves the exact index identity and refuses to start unless it exists. Fix/Reset run the checked-in `CREATE INDEX IF NOT EXISTS`, `REINDEX`, and `ANALYZE`, then measure public latency. | Existing `Caldova-quiz-response-time-elevated` five-minute rule |
| Quiz requests fail intermittently | Creates a bounded API revision with a pool size of 1, a 250 ms acquisition timeout, and a 1.5 second per-request hold; sends only 12 concurrent requests. | Saves presence/value for only the three changed environment variables plus image and revision metadata. Restore sets original values or removes only variables that were absent. | Shared `Caldova-quiz-launch-failing` five-minute failed-request metric |
| Quiz requests fail consistently | Creates one API revision with the non-secret `CALDOVA_QUIZ_MODE=unavailable` setting. Only quiz launch returns a symptom-only 503; health, readiness, courses, and PostgreSQL remain healthy. | Saves presence/value for only the changed environment variable plus image and revision metadata. Restore sets the original value or removes the variable when it was absent. | Shared `Caldova-quiz-launch-failing` five-minute failed-request metric |
| Grade reports are missing | Fills only the dedicated 8 GiB export data volume with `/var/lib/caldova/.caldova-reporting-output-missing.filler`, then runs the worker once. | Verifies `/var/lib/caldova` is a mount, removes only the named filler, starts the worker, and requires both a new CSV and recent `caldova-reporting` success heartbeat. The OS volume is never targeted. | `Caldova-reporting-output-missing`, five-minute rule that fires only when the latest failure is newer than the latest success |

Alert-driven Start operations validate the selected agent and response plan, capture ownership once, prove a healthy baseline, generate bounded traffic or a controlled heartbeat, and wait for a fresh alert. The default guided scenario instead proves core health and initially generates evidence without an alert; after learner configuration it waits for the exact guided alert. Application Gateway access diagnostics emit one record for each public request, so each path-isolation scenario produces the same quiz-specific signal even when traffic never reaches the portal. The query excludes non-quiz routes and non-5xx responses. Related quiz failures intentionally share one symptom alert so one injected failure cannot create duplicate investigations. Private PostgreSQL actions run inside the API container; the learner workstation never needs network access or `psql`. Azure mutation remains gated by `CALDOVA_AZURE_MUTATION_ENABLED=YES` and `CALDOVA_AZURE_TARGET=skillable`.

Azure Monitor can retain a Closed scheduled-query instance with `monitorCondition=Fired` after the worker has recovered, which prevents a later recurrence from creating a distinct incident. The reporting lifecycle waits through a bounded recovery window and prefers normal stateful resolution. Only when a fresh non-empty export and success heartbeat are verified, every reporting alert is Closed, and the stale instance remains Fired does it delete and redeploy the dedicated reporting rule with the same name, scope, and response-plan match. Historical alert and incident-thread evidence remains intact.

Direct Log Analytics queries from the SRE Agent runtime can return HTTP 403. The agent must not claim a clean workspace query. Use Application Insights, Azure CLI/ARM, metrics, configuration, and, for reporting only, clearly labeled VM journal/worker evidence.

If a fresh reporting alert fires or is acknowledged but no automatic incident thread appears after a bounded supported thread-list wait, a facilitator may use supported `sreagent incidents create` with that exact alert. Record the fallback provenance. It is not the normal learner path.

## Delivery sequence

- Preconfigured path: 25–30 minutes.
- Configure path: 50 minutes.
- Learners choose exactly one path and exactly one live scenario.
- Recommend **Course recommendations are unavailable** for Configure. All other scenarios are four-hour-path or post-lab practice.
- The default guided injection/evidence step is immediate and does not wait for an alert until learner automation exists.
- Azure Monitor evaluates exercise alerts every 5 minutes. Allow 5–10 minutes for the alert, about 1–2 minutes for the thread, 3–10 minutes for investigation/mitigation, and 5–20 minutes for resolution.
- While propagation is pending, continue the next configuration or evidence-review step, then return to the incident. Do not start another scenario.
- Require **Recovery verified**, then a confirmed Reset and passing readiness before the environment is reused.
- If GitHub is unavailable, continue from the packaged local repository; GitHub is not required for either learner path.

See [Facilitator troubleshooting](troubleshooting.md) for readiness, configuration, simulator, and reset failures.

## Azure-only acceptance checks

1. Seed confirms exactly 120,000 question-bank rows and the named lookup exists.
2. Slow-search Start measures median latency at or above the catalog threshold; Fix measures below recovery threshold.
3. Bounded-pressure Start records at least one success and one failure from exactly 12 requests.
4. Quiz-availability Start returns consistent learner-visible failures while health, readiness, courses, and PostgreSQL stay healthy.
5. Reporting Start confirms the filler is on `/var/lib/caldova`, the alert fires within the expected window, and Fix produces a new export plus a success heartbeat.
6. Guided Start initially returns HTTP 503 only for recommendations while all core checks and gateway backends are healthy; after learner automation exists, the same traffic fires the unique alert and routes only to the guided responder.
