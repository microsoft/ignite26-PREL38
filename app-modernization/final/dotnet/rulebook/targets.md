# Targets

Approved target technologies for .NET and Java modernization. Defines *what is approved* — not implementation steps.

## Target Frameworks

| Language | Target Version | Notes |
|----------|---------------|-------|
| .NET | .NET 10 (LTS) | SDK-style projects, `PackageReference` |
| Java | OpenJDK 21 (LTS) with Spring Boot 3.x | Confirm approved patch line |

## Target Compute Services

| Platform | Use When |
|----------|----------|
| Azure Container Apps | Default for every modernized web application and service |

## Target Data Services

| Service | Use When |
|---------|----------|
| Azure SQL Database | The application's source database is SQL Server. The database team chooses the service tier. Application plans connect using Microsoft Entra ID authentication with managed identity; endpoint read from environment settings. |

## Target Libraries

Source → target mappings for .NET and Java.

| Category | Source | Target |
|----------|--------|--------|
| .NET data access | `System.Data.SqlClient` | `Microsoft.Data.SqlClient` |
| .NET packaging | `packages.config` | `PackageReference` |
| .NET project format | Classic (non-SDK) project file | SDK-style project file |
| .NET configuration | `web.config` `appSettings` and `connectionStrings` | Environment variables and `appsettings.json` |
| Java web framework | Struts 1.x, Struts 2.x | Spring Boot 3.x (Spring MVC) |
| Java servlet API | `javax.servlet` | `jakarta.servlet` |
| Java SQL Server driver | Any `mssql-jdbc` below the current supported release | Current supported `mssql-jdbc` release |
| Azure identity | Credentials in configuration | `Azure.Identity` / `DefaultAzureCredential` (.NET), `azure-identity` (Java) |

## Target Artifacts

| Artifact | Notes |
|----------|-------|
| Dockerfile | One production-ready Dockerfile per application. Multi-stage build. Base image must be a Microsoft-published .NET or OpenJDK image. Runs as a non-root user. |
