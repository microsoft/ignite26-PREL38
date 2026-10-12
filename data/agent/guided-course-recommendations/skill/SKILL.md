---
metadata:
  api_version: azuresre.ai/v2
  kind: Skill
name: course-recommendations-recovery
description: Diagnose and safely recover the optional Caldova course recommendations experience without changing core learning, data, identity, networking, or reporting paths.
---

# Course recommendations recovery

Resource group: `@@RG@@`.

Use this skill only when the observed symptom is that `GET /api/recommendations/health` is unavailable while `/health`, `/ready`, `/api/courses`, `/api/quiz/OPS-201-M1`, `/api/exports/recent`, and Application Gateway backend health remain healthy.

## Diagnose

1. Record the alert or manual-investigation start time, request URL, HTTP result, and evidence marker.
2. Query Application Insights with the configured appId for:
   - `requests` named `GET /recommendations/health`;
   - result codes, duration, operation IDs, and timestamps;
   - matching `traces` containing `caldova_feature_status`;
   - `customEvents` named `CaldovaRecommendationsHealth`.
3. Use read-only Azure CLI to identify the single `ca-caldova-api-*` app in `@@RG@@`.
4. Read the active and ready revision names, image, traffic weights, replica state, and environment-variable **names and non-secret values**.
5. Confirm the core paths and adjacent resources are healthy before selecting a cause.
6. Treat missing App Insights or Azure configuration evidence as unknown. Do not use the blocked Log Analytics query path as a substitute.

## Remediate

When evidence confirms `CALDOVA_RECOMMENDATIONS_MODE` is not `available`:

1. State the exact current non-secret value, proposed value, expected effect, and rollback.
2. Update only the API Container App setting:

   ```text
   CALDOVA_RECOMMENDATIONS_MODE=available
   ```

3. Wait until the latest revision is the latest ready revision.
4. Do not change images, replica bounds, secrets, IAM, networking, PostgreSQL, reporting, or any other environment variable.

## Verify and close

1. Require HTTP 200 and state `available` from `/api/recommendations/health`.
2. Re-check every core path and Application Gateway backend health.
3. Query App Insights for post-change HTTP 200 evidence.
4. Require the alert condition to resolve, then call `caldova-guided-alerts_close_guided_alert` with the full alert resource ID. This managed-identity tool rejects any non-guided, non-resolved, or out-of-scope alert. Read back `alertState=Closed`.
5. Preserve the incident thread and report any product limitation if thread close is unavailable.
