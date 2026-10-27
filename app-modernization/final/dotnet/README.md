# PREL38 Part 2: prepared final .NET track

This is the separately prepared three-application end state:

| Application | Final technology | Role |
|---|---|---|
| CaldovaAuthGateway | .NET 10 / ASP.NET Core | Authentication and session provider |
| CaldovaLoanPortal | .NET 10 / MVC and Razor | Loan application UI and gateway consumer |
| CaldovaRiskEngine | .NET 10 / ASP.NET Core and CoreWCF | Shared-database risk scoring, with the legacy SOAP contract preserved |

**This is prepared evidence, not the output of a learner's current agent run.** It does not replace the intentionally flawed primary-app review example in `module-03-execute\finish`. The Java track is unchanged.

## Use it in the 60-minute lab

Keep the existing Assess -> Plan -> Start execution -> Review sequence. After learners identify the faults in the review example, open this final state. They do not need to complete all transformations, rebuild all containers or run the full database suite during the hour.

Suggested facilitator placement after extracting the ZIP:

```text
C:\lab\caldova\modules\module-03-execute\final\dotnet
```

The ZIP contains the `dotnet` directory. Extract it into `module-03-execute\final`, not into an existing `start` or `finish` directory. If `final\dotnet` already exists, inspect/version it rather than overwriting it. This package has not automatically installed itself into the Skillable VM.

### Five-minute final-state review

1. Open `apps` and confirm that all three projects target `net10.0`, including RiskEngine.
2. Compare the portal's Microsoft-based, non-root Dockerfile with the earlier flawed example.
3. Read `VALIDATION.md`: distinguish local SQL integration, actual container checks, and the Azure/central-rulebook checks that have not run.
4. If time permits, use the supplied SDK and package access to run:

   ```powershell
   cd C:\lab\caldova\modules\module-03-execute\final\dotnet
   dotnet restore Caldova.FinalState.slnx --locked-mode
   dotnet test Caldova.FinalState.slnx --no-restore --filter "FullyQualifiedName!~ThreeAppSqlTests"
   ```

   This runs the fast tests without creating a SQL container. The database-backed suite is prepared evidence for the classroom, not a required download or setup activity.

5. Explain the handoff: the selected track has three modernized applications, compatible endpoints, container assets, locked dependencies and explicit database configuration requirements. Do not describe a healthy local route as proof of an Azure deployment.

## Reproduce the full validation outside the time-box

The full test suite requires a working Docker engine with Linux/amd64 support and the Microsoft SQL Server 2022 image. It creates one isolated local SQL container and test database, generates temporary credentials in memory, and removes the container afterward:

```powershell
dotnet test Caldova.FinalState.slnx --no-restore
```

The integration tests use SQL authentication only inside that disposable test fixture. Production applications retain Entra-only connection builders. No shared lab database, Azure resource, account grant or real application credential is used by the fixture.

Each application directory is a standalone Docker build context:

```powershell
docker build --platform linux/amd64 -t caldova-auth-final apps\CaldovaAuthGateway
docker build --platform linux/amd64 -t caldova-portal-final apps\CaldovaLoanPortal
docker build --platform linux/amd64 -t caldova-risk-final apps\CaldovaRiskEngine
```

The Dockerfiles restore locked dependencies. If the environment requires an approved alternative public feed, pass `--build-arg NUGET_SOURCE=<approved-feed-url>` explicitly. Do not put credentials in that argument.

## Running against the assigned environment

Use the facilitator-provided `DB_HOST`, `DB_NAME`, application URLs and identity access. The portal's public return origin must be allowed by the gateway, and browser cookie routing must use a same-origin arrangement or an approved shared cookie domain. See each application's README for its configuration.

All applications expose `/health` and `/health/ready`. Without a configured/accessible database, liveness can succeed while readiness correctly fails with 503. Azure telemetry export is disabled with an explicit warning when its connection string is absent.

Actual Azure SQL managed-identity access, Azure Monitor delivery, shared production key management and deployment are separate environment checks. For a multi-instance or restart-durable deployment, configure a durable, protected ASP.NET Core Data Protection key ring; the tests' ephemeral key provider is only a test fixture. This is a validated teaching snapshot, not a blanket production-security approval.

## Provenance

Prepared from the supplied .NET finish branch at `cb73b2cebb33a099a6f60fc220387aba4b35d6e3`, with explicit code corrections and independent validation. The local copies of the supplied rulebook guided the changes; no new central-rulebook-loaded CLI execution is claimed.

The original teaching folders and existing Skillable pages were left unchanged. Old agent task statuses and assessment reports are intentionally excluded from this package so they cannot be mistaken for evidence of this final-state work.
