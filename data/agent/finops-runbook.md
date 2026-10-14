# Caldova FinOps evidence runbook

Scope all commands to `@@RG@@` and label observation time, currency, billing period, source, and coverage.

## Evidence order

The Preconfigured Agent and its FinOps Live Report use only `caldova-finops_get_caldova_finops`. The repository-owned stdio MCP server runs inside the SRE Agent container with the Preconfigured user-assigned managed identity, accepts no arguments, and is hard-scoped to the configured learner subscription and resource group.

1. Query Cost Management `ActualCost` at resource-group scope for month-to-date daily, service, and resource rows.
   - The connector serializes Cost Management requests and caches successful billed payloads for 30 minutes so concurrent report opens do not consume duplicate query-processing units.
   - When a live query is throttled, it may return a last-known-good billed payload for up to 24 hours. It labels the payload `cached`, reports the original cost capture time and cache age, and preserves the throttle detail.
   - If Cost Management reports an exhausted hourly quota, the connector does not retry or issue the Forecast request. Without a valid cache, billed cost remains unavailable rather than zero.
2. If Cost Management is unavailable or delayed, query consumption usage at the same resource-group scope and explicitly state whether monetary fields are present.
3. Inventory deployed SKUs, regions, and resource identities. Query Azure Retail Prices live; when runtime egress is unavailable, use the timestamped Retail Prices snapshot refreshed automatically by `scripts/configure-agent.mjs`. Produce a clearly labeled **estimate**, including source, snapshot time, assumptions, and exclusions.
4. Query budgets, Advisor cost recommendations, recent scaling/configuration changes, and relevant reliability alerts.

## Quality rules

- Actual cost, forecast, and potential savings are different measures; never add them together.
- Unknown, unauthorized, delayed, or empty data is not zero.
- Cached billed cost remains billed evidence, but it must be labeled **last-known-good** and must never be presented as a fresh query.
- Every finding must include provenance and freshness.
- Rank recommendations by expected impact, reliability risk, confidence, and effort.
- Do not resize, stop, or delete resources.

The SRE Agent principal is `@@AGENT_PRINCIPAL_ID@@`. `Reader` and `Cost Management Reader` must be validated at the resource-group scope using dynamically resolved role-definition IDs. If event-operations permissions prevent an assignment, report the exact prerequisite and continue only with evidence the identity can actually read.
