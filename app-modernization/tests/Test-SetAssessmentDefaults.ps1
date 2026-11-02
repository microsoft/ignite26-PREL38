#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'Set-AssessmentDefaults.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('prel38-assessment-test-' + [Guid]::NewGuid().ToString('N'))
$path = Join-Path $temporary '.modernize/assessment-config.yaml'
$expected = (@(
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
) -join "`r`n") + "`r`n"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    $result = & $script -Path $path
    Assert-True ($result -eq "Saved: $path") 'The defaults were not created.'
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'The defaults have an unexpected UTF-8 BOM.'
    Assert-True ([IO.File]::ReadAllText($path) -ceq $expected) 'The defaults do not match the lab settings.'

    $timestamp = [DateTime]::SpecifyKind([DateTime]'2000-01-01', [DateTimeKind]::Utc)
    [IO.File]::SetLastWriteTimeUtc($path, $timestamp)
    $result = & $script -Path $path
    Assert-True ($result -eq "Already set: $path") 'A second run did not report an unchanged file.'
    Assert-True ([IO.File]::GetLastWriteTimeUtc($path) -eq $timestamp) 'A second run rewrote an unchanged file.'

    [IO.File]::WriteAllText($path, 'old settings')
    $result = & $script -Path $path
    Assert-True ($result -eq "Saved: $path") 'Outdated defaults were not updated.'
    Assert-True ([IO.File]::ReadAllText($path) -ceq $expected) 'Updated defaults do not match the lab settings.'
    'Passed 3 checks.'
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
