# Prepared final-state validation

**Validated scope:** the three .NET applications, local HTTP/SOAP contracts, real local SQL-backed cooperation, locked NuGet graphs and actual Linux containers. This record is not a central CLI compliance report and does not grant exceptions to the workshop rulebook.

## Observed results

| Check | Result |
|---|---|
| Legacy RiskEngine characterization, before migration | 27 tests passed against the unchanged legacy service's rules and data contract |
| AuthGateway tests | 13 passed |
| LoanPortal tests | 16 passed |
| Modernized RiskEngine tests | 33 passed, including the unchanged characterization cases plus SOAP/HTTP checks |
| Track-wide contract/integration tests | 26 passed, including six real local SQL-backed cases |
| Total final suite | **88 passed; zero failed or skipped** |
| NuGet advisory audit | **134 resolved package/version pairs; zero High/Critical findings** in GitHub Advisory Database results |
| Container builds | All three Release Linux/amd64 images built |
| Container runtime | All three ran with UID **1654**, .NET/ASP.NET Core **10.0.14**, port 8080 |
| Container smoke checks | Gateway identity/login, portal authentication challenge, RiskEngine WSDL and all liveness routes passed |
| Unconfigured database readiness | All three returned **503**, rather than incorrectly claiming database readiness |

The local SQL tests exercise successful gateway sign-in, portal cookie authentication, wizard navigation, gateway session revocation after portal logout, risk model updates/factor reads, and risk scoring of a loan actually submitted through the portal. They also check that invalid submissions are not shown as saved and that navigating back cannot render a client-supplied HTML review summary.

One high-severity transitive dependency family was found during validation: the older XML cryptography stack brought by CoreWCF. The final source pins patched XML/PKCS packages and locks the resulting graphs; the repeat audit found no High/Critical entries. This audit covers NuGet packages, including test dependencies, not all application-code or container-OS vulnerabilities.

## Deliberate compatibility and reliability decisions

- Preserve the old SOAP endpoint, operation names and data-contract namespace using CoreWCF. The prepared plan's REST-only wording was not treated as permission to break callers; REST endpoints are additive.
- Preserve gateway/portal `.aspx` and `.ashx` aliases, the cookie name and the gateway identity response.
- Validate session revocation and reject expired/locked-out sessions. Carry the portal's return destination through sign-in, constrained to trusted origins.
- Use a non-cookie-sharing HTTP handler for gateway validation, so one user's response cookie cannot be reused by a pooled client for another user.
- Keep SQL calls asynchronous and parameterized; use Entra-only, encrypted, certificate-validating production connection strings.
- Separate database-save success from external origination forwarding. A missing or failed external service is visible, not a fabricated end-to-end success.
- Distinguish liveness from database readiness and use generic service-error responses.

## Still environment-dependent

| Item | Status |
|---|---|
| Azure SQL managed-identity authentication and the supplied database/schema | Not exercised here; local integration uses an isolated SQL fixture |
| Central rulebook loading/provenance in live Modernize planning/execution | Not claimed; the rehearsal's intended central configuration was absent |
| Azure Monitor ingestion | Not exercised; unconfigured export is explicitly reported |
| Azure Container Apps deployment | Not performed |
| External loan-origination service | Not supplied by this three-app package; forwarding availability is reported separately |
| Cross-host cookie routing and durable/protected production Data Protection keys | Deployment configuration still required; test-only ephemeral keys are not a production configuration |
| Production identity/security approval | Not claimed; compatibility with the existing training credential schema is retained |

No resource provisioning or access grants are part of this result. The supplied `rulebook` remains unchanged. Use the evidence to check the applicable rules; do not mark the remaining environment-dependent rules satisfied merely because the tests passed.

## Evidence

- `evidence/tests.json`: final test counters and named cases.
- `evidence/containers.json`: actual image IDs, runtime versions, UID and route results.
- `evidence/package-audit.json`: dated package/version advisory results and coverage boundaries.
- `manifest.json`: SHA-256 values for the packaged files.

The original start/finish review examples are preserved. The validated final state is a separate teaching checkpoint.
