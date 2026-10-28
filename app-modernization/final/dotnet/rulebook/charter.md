# Charter

## Metadata

| Field | Value |
|-------|-------|
| Rulebook Name | Caldova Bank Application Modernization Standard |
| Version | 0.2 (DRAFT) |
| Document ID | CB-MOD-001 |
| Owners | Caldova Bank Security, Governance, and Platform teams |

## Scope

### Covered Applications and Languages

Applies to every Caldova Bank application written in .NET Framework 4.x or Java 8 / 11 / 17 that is modernized for Azure.

### Application Types

**Included:** Customer-facing web applications, internal web applications, HTTP/SOAP services.

**Excluded:** Mainframe, COBOL, and packaged vendor software.

### Constraints

Applications that belong to the same business flow are modernized as one connected group. Providers (services that other applications call) are modernized before their callers.

## Modernization Strategy (6R Guidelines)

Of the 6R strategies, this rulebook covers **Rehost**, **Replatform**, and **Refactor** — the three that involve app modernization. Retire, Retain, and Repurchase are outside the scope of app modernization.

Supported strategies: **Rehost** (lift-and-shift, no code changes), **Replatform** (minimal code changes — containerize, adopt managed services), **Refactor** (modify code/architecture — decompose, upgrade).

| Application Type | Default Strategy | Override Conditions |
|------------------|-----------------|---------------------|
| .NET Framework web application or service | Refactor: upgrade to the target .NET version and containerize | Replatform only (containerize, keep framework) if the architect records an exception |
| Java application on an end-of-life framework (Struts 1.x, Struts 2.x) | Refactor: migrate to Spring Boot | None |
| Java servlet application or service | Replatform: upgrade Java, containerize, adopt managed services | Refactor if a CVE fix requires a framework change |

## Principles

1. Providers are upgraded before the applications that depend on them.
2. Public API, service, and library contracts stay compatible unless an architect explicitly approves a change.
3. Existing business behavior is preserved.
4. Every change is validated by a build and tests before the next task starts.
5. The same rules apply to .NET and Java. Rules are written as intent, and each ecosystem implements them with its own libraries.
