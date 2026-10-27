# Policies

Enforceable standards and hard boundaries for .NET and Java modernization. Every policy here is validatable against generated artifacts.

## Security Requirements

### Authentication & Authorization

1. Azure resource access uses managed identity wherever the service supports it.
2. Database connections use Microsoft Entra ID authentication with managed identity. Credential-based production connections are removed.

### Secrets Management

1. Credentials, keys, and connection secrets are never committed to source control.
2. Secrets that cannot be replaced by managed identity are read from Azure Key Vault at runtime.
3. Cryptographic keys (for example ASP.NET `machineKey`) are never stored in configuration files.

### Encryption

1. Database connections require encryption and validate the server certificate. `TrustServerCertificate=true` is not allowed outside local development.

## Compliance Requirements

1. Personally identifiable information (PII), including customer names, Social Security numbers, and account numbers, must not appear in logs, error messages, or telemetry. The PII masking skill enforces this during execution.
2. Every modernized application produces evidence of rulebook compliance: build results, test results, and a vulnerability scan.

## Guardrails (Hard Boundaries)

### Prohibited Technologies

| ID | Technology | Approved Alternative |
|----|------------|----------------------|
| GRD-01 | Struts 1.x and Struts 2.x | Spring Boot 3.x |
| GRD-02 | `System.Data.SqlClient` | `Microsoft.Data.SqlClient` |
| GRD-03 | `mono` and other non-Microsoft base images in production Dockerfiles | .NET or OpenJDK images published by Microsoft |
| GRD-04 | Dependencies with a known vulnerability of severity High or Critical | A patched, compatible release |
| GRD-05 | Log4j versions below 2.17.1 | Log4j 2.17.1 or later, or the logging provided by Spring Boot |

### Prohibited Patterns

| ID | Pattern | Approved Alternative |
|----|---------|----------------------|
| GRD-10 | Hard-coded credentials, connection-string passwords, or keys in source or configuration | Managed identity, then Key Vault |
| GRD-11 | SQL built by string concatenation | Parameterized queries only |
| GRD-12 | Detailed error output and debug mode enabled in production (`customErrors Off`, `debug="true"`, `includeExceptionDetailInFaults`) | Generic error responses and structured logs |
| GRD-13 | Silent exception swallowing (empty `catch`) | Logged and handled exceptions |
| GRD-14 | Application state held in process memory or on local disk | Stateless application, external state stores |

### Required Elements

Every modernized application must include:

| ID | Element |
|----|---------|
| GRD-20 | A health check endpoint (liveness and readiness) |
| GRD-21 | Structured telemetry through OpenTelemetry exported to Azure Monitor / Application Insights |
| GRD-22 | Configuration through environment settings, with no environment-specific values in the image |
| GRD-23 | A production-ready Dockerfile that builds successfully |
| GRD-24 | Readiness for deployment to Azure Container Apps |

## Validation & Quality Gates

| ID | Gate |
|----|------|
| VAL-01 | The solution builds after every major task |
| VAL-02 | Tests pass after every major task. If the repository has no automated tests, a baseline smoke or contract test is created before code changes begin. |
| VAL-03 | The vulnerability scan after the build reports no remaining High or Critical findings introduced by the dependency graph |
| VAL-04 | The Dockerfile builds |
| VAL-05 | Public API and library contracts are unchanged, or the change carries an architect approval |
| VAL-06 | The rulebook compliance report lists every policy as satisfied or as an approved exception |

## Coding Style Guidelines

### .NET

- Nullable reference types enabled.
- `async` used for I/O operations.
- `ILogger` used for logging.

### Java

- Constructor injection.
- SLF4J for logging.
- No wildcard imports.
