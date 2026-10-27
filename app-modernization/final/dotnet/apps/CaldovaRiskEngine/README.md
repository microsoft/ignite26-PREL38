# CaldovaRiskEngine: prepared .NET final state

.NET 10 ASP.NET Core service with CoreWCF compatibility for the existing SOAP contract. The prior framework/WCF hosting files have been replaced without requiring existing SOAP callers to change their operation names or data-contract namespace.

Preserved endpoint: `/CaldovaRiskEngine.svc`, with WSDL at `/CaldovaRiskEngine.svc?wsdl`.

- `ScoreLoanApplication(int applicationId)`
- `GetRiskFactors(int customerId)`
- `UpdateRiskModel(RiskModelUpdateRequest modelParams)`

Additive REST routes are `/api/risk/score/{applicationId}`, `/api/risk/factors/{customerId}` and `/api/risk/model`. They do not replace the SOAP contract. `/Health.ashx` and `/health` return `OK`; `/health/ready` checks database connectivity. Unexpected SOAP failures return a generic fault instead of database details.

The scoring formulas, rating boundaries, approval multipliers and response contract were characterized against the unchanged legacy source before migration. Database operations are asynchronous and parameterized. Production configuration uses `DB_HOST` and `DB_NAME`, Entra authentication and validated TLS, without SQL password settings.

The original behavior that creates `RiskModelParameters` when absent is retained. The assigned database must already contain that table or permit the application's existing initialization step. The local integration fixture is not a migration script for the shared Azure database.

Set `APPLICATIONINSIGHTS_CONNECTION_STRING` only to the assigned telemetry destination. Missing configuration is explicitly reported and does not count as successful export. The default listener is port 8080; the Microsoft-based container runs non-root.

Original training application: [Caldova Bank sample](https://github.com/bradygaster/Build2026GHCPAppModDemoWare).
