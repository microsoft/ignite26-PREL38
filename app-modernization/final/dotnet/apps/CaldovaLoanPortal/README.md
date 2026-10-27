# CaldovaLoanPortal: prepared .NET final state

.NET 10 MVC/Razor consumer of CaldovaAuthGateway. It forwards the current request's `.CALDOVAAUTH` cookie to `/WhoAmI.ashx` rather than sharing a pooled HTTP client's cookie jar.

The loan wizard reads and writes the existing database through asynchronous, parameterized `Microsoft.Data.SqlClient` calls. Failed persistence is not presented as a successful submission. Missing or failed external loan-origination forwarding is reported separately from a successful database save. Going back to the review step rebuilds its encoded summary instead of trusting submitted HTML.

Configuration:

- `DB_HOST`, `DB_NAME`: assigned database endpoint and name; Entra authentication and validated TLS are used.
- `PUBLIC_BASE_URL`: the portal's public origin, used for the return destination after gateway sign-in.
- `AUTH_GATEWAY_WHOAMI_URL`, `AuthGatewayLoginUrl`, `AuthGatewayLogoutUrl`: the assigned gateway URLs.
- `LoanOriginationApiUrl`: the existing external origination service, when that integration is supplied. It is not one of the three applications in this package.
- `APPLICATIONINSIGHTS_CONNECTION_STRING`: assigned telemetry configuration.
- `ASPNETCORE_URLS`: optional listener override; default port is 8080.

Use a same-origin routing arrangement or an approved shared cookie domain. Independent, unrelated public hostnames do not share a browser cookie automatically.

Legacy `/Default.aspx`, `/Login.aspx` and `/Logout.aspx` paths are retained alongside MVC routes. Logout forwards the browser to the gateway without first deleting the cookie needed to revoke its session. `/health` is anonymous liveness; `/health/ready` checks the database.

The Dockerfile now builds with Microsoft .NET images, runs non-root and exposes port 8080. See `VALIDATION.md` at the package root for measured evidence and boundaries.

Original training application: [Caldova Bank sample](https://github.com/bradygaster/Build2026GHCPAppModDemoWare).
