# Part 2: application modernization

Use GitHub Copilot modernization to assess connected applications, plan scoped changes, start execution, and review the result against the workshop rulebook. This section contains the **prepared .NET final-state checkpoint** for that review, not the starting applications or the output of a learner's current agent run.

| Application | Prepared final state |
|---|---|
| [CaldovaAuthGateway](final/dotnet/apps/CaldovaAuthGateway/README.md) | .NET 10 / ASP.NET Core authentication and session provider |
| [CaldovaLoanPortal](final/dotnet/apps/CaldovaLoanPortal/README.md) | .NET 10 / MVC and Razor loan application UI |
| [CaldovaRiskEngine](final/dotnet/apps/CaldovaRiskEngine/README.md) | .NET 10 / CoreWCF risk scoring with the legacy SOAP contract preserved |

## Getting started

For the guided 60-minute application-modernization lab:

1. Use the assigned Skillable workstation and its existing **Assess -> Plan -> Start execution -> Review** instructions.
2. Inspect the deliberately flawed `finish` review example before opening the prepared final state. The original `start` and `finish` folders, Java track, and live modernization setup are supplied separately by the workshop; they are not included here.
3. Follow the [five-minute final-state review](final/dotnet/README.md#five-minute-final-state-review) and read the [validation record](final/dotnet/VALIDATION.md). Do not replace the original teaching examples with this checkpoint.

Reading the source and recorded evidence does not require Azure access. To run the installer, use [PowerShell 7 or later](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell). Reproducing the .NET checks requires the [.NET 10 SDK](https://learn.microsoft.com/en-us/dotnet/core/install/) and access to the locked NuGet packages. The full SQL-backed suite and container builds also require a working Docker engine with Linux/amd64 support. See the [final-state guide](final/dotnet/README.md) for the exact commands and environment requirements.

The supplied rulebook files are reference copies, not proof that the live modernization tool has loaded the central rulebook. Verify the workshop's live rulebook configuration separately before planning or execution. Azure deployment, managed-identity database access, and telemetry delivery remain separate environment checks.

## Included materials

| Path | Purpose |
|---|---|
| [final/dotnet/apps](final/dotnet/apps) | Three application sources, configuration guides, Dockerfiles, and application tests |
| [final/dotnet/tests](final/dotnet/tests) | Track-wide contract and SQL integration tests |
| [final/dotnet/evidence](final/dotnet/evidence) | Recorded test, container, and package-audit results |
| [final/dotnet/rulebook](final/dotnet/rulebook) | Supplied modernization charter, policies, and target technologies |
| [final/dotnet/manifest.json](final/dotnet/manifest.json) | SHA-256 hashes for the prepared checkpoint |
| [Install-FinalState.ps1](Install-FinalState.ps1) | Offline, manifest-verified copy into the workshop's final-state location |
| [tests](tests) | Installer checks using an isolated temporary directory |

The immutable [October 27 ZIP](final/part2-validated-final-dotnet-20261027.zip) contains the same source and evidence as `final/dotnet` for direct delivery. Its SHA-256 is `b109e6bf489552cd0050ce7044c4d07f1c0d85d926a568883a464d331c4fa6dd`. It extracts to a `dotnet` directory and contains no Git history or credentials.

The scoped `.gitattributes` preserves the final snapshot's exact bytes even in Windows checkouts using `core.autocrlf=true`, so checkout line-ending conversion does not invalidate the manifest. Keep the prepared snapshot and archive unchanged when updating the surrounding workshop documentation.

## Delivery to Skillable

During image preparation or pre-run, place this repository on the VM and run the following from the repository root in PowerShell 7 or later. Existing VM clones do not update automatically when GitHub changes.

```powershell
pwsh -NoProfile -File .\app-modernization\Install-FinalState.ps1
```

The default destination is:

```text
C:\lab\caldova\modules\module-03-execute\final\dotnet
```

The installer:

- verifies every manifest-listed source file before copying;
- copies only the listed files and the manifest;
- stages and verifies the copy before atomically creating the destination;
- leaves identical existing files untouched and refuses to replace a different final state;
- does not download packages, install tools, change accounts, configure cloud resources, or modify SRE content.

The files are also usable directly from `app-modernization/final/dotnet` in the repository. The copy simply keeps the learner-facing `C:\lab\caldova` path consistent.

The [recorded validation](final/dotnet/VALIDATION.md) reports 88 passing tests, including real local SQL-backed cooperation, and all three Linux containers built and ran non-root. These are prepared results, not proof of a new central-rulebook-loaded execution or an Azure deployment.

## Installer checks

Run from the repository root:

```powershell
pwsh -NoProfile -File .\app-modernization\tests\Test-InstallFinalState.ps1
```

These checks use a temporary directory, do not need Azure or database access, and remove only their own test directory.

## Technology documentation

- [GitHub Copilot modernization](https://learn.microsoft.com/en-us/azure/developer/github-copilot-app-modernization/)
- [.NET](https://learn.microsoft.com/en-us/dotnet/) and [ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/)
- [.NET container images](https://learn.microsoft.com/en-us/dotnet/core/docker/introduction)
- [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/) and [Microsoft Entra authentication](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)

[Back to the session overview](../README.md)
