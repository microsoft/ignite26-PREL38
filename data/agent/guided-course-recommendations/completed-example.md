# Completed course recommendations example

This example is a comparison artifact, not a diagnosis to copy before collecting evidence.

## Manual investigation

- Symptom: `GET /api/recommendations/health` returned HTTP 503 with feature state `degraded`.
- Isolation proof: `/health`, `/ready`, courses, quiz launch, exports, PostgreSQL check, reporting heartbeat, and Application Gateway backend health remained healthy.
- Application Insights evidence: failed recommendation-health requests and `caldova_feature_status` traces began in the same window.
- Azure configuration evidence: the active API revision exposed the non-secret `CALDOVA_RECOMMENDATIONS_MODE` setting with a value other than `available`.
- Confidence: high only after request telemetry and live revision configuration agreed.

## Reusable skill proposal

The generated skill should:

1. query App Insights requests, traces, and custom events;
2. prove adjacent core paths healthy;
3. inspect only the learner API Container App and its active revision;
4. permit only the one-setting reversible correction;
5. verify endpoint, revision, core health, alert resolution, and alert closure.

See [`skill/SKILL.md`](skill/SKILL.md) for the completed native artifact.

## Completed automation

- Alert: `Course-recommendations-unavailable`
- Skill: `course-recommendations-recovery`
- Custom agent: `caldova-guided-feature-responder`
- Response plan: `course-recommendations-learning-response`
- Initial prepared ownership: none
- Completed ownership: exact alert → exact response plan → guided custom agent → guided skill
- Prepared AFTER-state: skill and custom agent remain visible; alert and response plan are disabled until the exercise is explicitly enabled.

The existing `caldova-azure-monitor-response` plan is not selected because its `titleContains: Caldova` filter does not match this alert title.
