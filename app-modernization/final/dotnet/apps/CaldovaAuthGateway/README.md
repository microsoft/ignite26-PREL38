# CaldovaAuthGateway: prepared .NET final state

.NET 10 authentication provider for the Caldova Bank training estate. Database access uses `Microsoft.Data.SqlClient`, Entra authentication, encrypted connections and certificate validation.

Preserved public routes include `/Login.aspx`, `/Logout.aspx`, `/Default.aspx`, `/Health.ashx`, `/WhoAmI.ashx` and `/ApiAuthValidate.ashx`. The modern `/login`, `/logout`, `/health` and `/api/auth/validate` routes remain available. The same routes can be hosted under `/auth`.

`/WhoAmI.ashx` preserves the authenticated response fields `authenticated`, `username`, `displayName`, `sessionToken` and `roles`. An anonymous request returns exactly `{"authenticated":false}`. Cookie authentication also checks the database session's validity; logout revokes that session before clearing the cookie.

Configuration:

- `DB_HOST`, `DB_NAME`: assigned database endpoint and name. Production SQL passwords are not accepted.
- `AUTH_ALLOWED_RETURN_ORIGINS`: semicolon-separated, explicitly trusted portal origins. HTTPS is required except for loopback development origins.
- `AUTH_COOKIE_DOMAIN`: optional shared cookie domain for an approved same-site deployment.
- `APPLICATIONINSIGHTS_CONNECTION_STRING`: assigned telemetry configuration. Missing configuration produces an explicit warning; Azure export is not claimed.
- `ASPNETCORE_URLS`: optional listener override; default port is 8080.

`/health` is liveness. `/health/ready` actually checks database connectivity and returns 503 when unavailable. A live process is not proof that database authentication works.

See the package's `README.md` and `VALIDATION.md` for the prepared-state workflow and deployment boundaries. The existing database's password-hash format is retained for compatibility with the training users; this package is not a production identity-system redesign.

Original training application: [Caldova Bank sample](https://github.com/bradygaster/Build2026GHCPAppModDemoWare).
