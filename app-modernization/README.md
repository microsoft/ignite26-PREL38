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

## Prepared report names and repository lists

The prepared assessment reports were generated before the Zava-to-Caldova rename, so some report folders and pages still say `Zava`. Learners also had to switch from `repos.json` (six apps) to `repos-live.json` (one app) for the live assessment.

Run this during image preparation or pre-run, after the module repositories are in place and before the image is captured:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\app-modernization\Rename-PreparedReports.ps1 -WarningAction Stop
```

For every `module-*\start` and `module-*\finish` repository under `C:\lab\caldova\modules`, on every local branch, it:

- replaces `Zava`, `ZAVA` and `zava` with `Caldova`, `CALDOVA` and `caldova` in tracked text files and paths, and removes folders the renames leave empty;
- renames `.github\modernize\repos.json` to `repos-portfolio.json` and `repos-live.json` to `repos.json`, so the default path is the one-app list (skip with `-SkipRepoListSwap`);
- commits the result and returns to the original branch.

It refuses repositories with staged changes, leaves untracked and locally modified files unchanged, does not rewrite binary contents, and changes nothing when run again. It warns about skipped modified or missing tracked files; if either repository list has local changes, it also skips the list swap. It fails if no module repositories are found. It needs Git 2.26 or later.

The command above stops on warnings so an incomplete preparation is not mistaken for success. If it stops, inspect the working tree and resolve the warning before retrying; do not capture the image in that state.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\app-modernization\tests\Test-RenamePreparedReports.ps1
```

The check builds temporary repositories and removes them afterwards.

## Assessment defaults

Modernize CLI reads its interactive assessment defaults from `C:\Users\LabUser\.modernize\assessment-config.yaml`, not from the module's `assess-config.yaml`. If that file is missing or holds values from an earlier run (for example **Issue only** or **OpenJDK 25**), learners must reconfigure several settings by hand.

Run this as the lab user during image preparation, before the image is captured:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\app-modernization\Set-AssessmentDefaults.ps1
```

It saves **Full analysis**, **High** CVE severity, OpenJDK 21, .NET 10, Azure Container Apps and Linux, so the CLI's summary screen already matches the guide and learners select **Continue**. Running it again changes nothing.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\app-modernization\tests\Test-SetAssessmentDefaults.ps1
```

The check uses a temporary directory and removes it afterwards.

## Verify the learner image

Adding these scripts to the repository or running them in an existing learner VM does not update the shared image. Apply them to a clean image, with the assessment defaults set as `LabUser`, or use a lifecycle action only after verifying that it runs before learners see the VM and reports errors. Do not capture a VM containing an authenticated session or learner work.

Review the preparation output: warnings about skipped branches, modified or missing files, or binary content can mean the fix is incomplete. On a fresh learner instance, confirm that the prepared report shows `Caldova` names, the default `repos.json` selects only `CaldovaAuthGateway`, and the assessment settings match the guide before relying on the revised instructions.
