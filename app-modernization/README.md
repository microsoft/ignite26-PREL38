# Part 2: application modernization

`final/dotnet` contains the validated three-app teaching checkpoint for CaldovaAuthGateway, CaldovaLoanPortal and CaldovaRiskEngine. It is the same source and evidence as the reviewed final-state package; its manifest records the file hashes.

The immutable [October 27 ZIP](final/part2-validated-final-dotnet-20261027.zip) is also included for direct delivery. Its SHA-256 is `b109e6bf489552cd0050ce7044c4d07f1c0d85d926a568883a464d331c4fa6dd`. It extracts to a `dotnet` directory and contains no Git history or credentials.

The scoped `.gitattributes` preserves the final snapshot's exact bytes even in Windows checkouts using `core.autocrlf=true`, so checkout line-ending conversion does not invalidate the manifest.

Keep the existing classroom flow: start a scoped modernization, inspect the deliberately flawed review example, then open this prepared final state. Do not replace the existing `start` or `finish` folders.

## Delivery to Skillable

A repository clone contains the files **only when it includes the commit that adds this directory**. Existing VM clones do not update automatically when GitHub changes. A feature branch is not part of a default-branch clone until it is merged.

Once the prepared repository on the VM includes this directory, run this offline copy during image preparation or pre-run:

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

Read [the final-state guide](final/dotnet/README.md) and [the validation record](final/dotnet/VALIDATION.md). The source passed 88 tests, including real local SQL-backed cooperation, and all three Linux containers built and ran non-root. These are prepared results, not proof of a new central-rulebook-loaded execution or an Azure deployment.

## Installer checks

```powershell
pwsh -NoProfile -File .\app-modernization\tests\Test-InstallFinalState.ps1
```

These checks use a temporary directory, do not need Azure or database access, and remove only their own test directory.
