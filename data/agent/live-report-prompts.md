# Caldova Live Report prompts

Live Reports are created in the Azure SRE Agent portal because the supported `azmcp` and `srectl` versions used by this lab do not expose report creation.

## FinOps

Create a Live Report named **Caldova FinOps** scoped only to `@@RG@@`. Use read-only Azure tools. Show 30-day actual cost and daily trend, top services and resources, budgets, cost anomalies, Advisor cost recommendations, and cost-versus-reliability context from Azure Monitor alerts. Separate actual cost, forecast, and potential savings. Include data freshness, included scope, excluded or unsupported sources, and a visible warning when cost data is delayed or unavailable. Use charts and sortable tables. Do not include write actions.

## Operations Command Center

Create a Live Report named **Caldova Operations Command Center** scoped only to `@@RG@@`. Use read-only Azure tools. Show public endpoint health, Application Gateway backend health, active Container Apps revisions and image digests, replicas and latency, PostgreSQL availability/capacity, reporting-worker heartbeat, active Azure Monitor alerts, recent resource changes, and scheduled-task status. Include observation times and explicit missing-evidence states. Use status indicators, trend charts, and sortable tables. Do not include write actions.
