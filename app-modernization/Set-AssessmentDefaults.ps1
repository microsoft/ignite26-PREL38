<#
.SYNOPSIS
Saves the lab's assessment settings as the Modernize CLI defaults for the lab user.
.DESCRIPTION
Run as the lab user during image preparation, before the image is captured. Modernize CLI reads its
interactive assessment defaults from $HOME\.modernize\assessment-config.yaml, not from the module's
.github\modernize\assess-config.yaml. Without this file, or with values saved by an earlier run,
learners must reconfigure several settings by hand. With it, the summary screen already shows Full
analysis, High CVE severity, OpenJDK 21, .NET 10, Azure Container Apps and Linux, so learners select
Continue.
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $HOME '.modernize\assessment-config.yaml')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$lines = @(
    'analysisCoverage: full'
    'security:'
    '  minimumCveSeverity: high'
    'java:'
    '  assessmentDomains:'
    '  - java-upgrade'
    '  - cloud-readiness'
    '  targetRuntime: openjdk21'
    '  targetComputeServices:'
    '  - azure-container-apps'
    '  targetOS:'
    '  - linux'
    'dotnet:'
    '  assessmentDomains:'
    '  - dotnet-upgrade'
    '  - cloud-readiness'
    '  targetRuntime: net10.0'
    '  targetComputeServices:'
    '  - ACA'
)
$content = ($lines -join "`r`n") + "`r`n"

$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
if ((Test-Path -LiteralPath $Path -PathType Leaf) -and ([IO.File]::ReadAllText($Path) -ceq $content)) {
    Write-Output "Already set: $Path"
    return
}
[IO.File]::WriteAllText($Path, $content, (New-Object Text.UTF8Encoding $false))
Write-Output "Saved: $Path"
