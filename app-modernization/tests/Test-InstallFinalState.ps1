#requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-FinalState.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('prel38-final-install-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Rejected {
    param([scriptblock]$Action)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'Expected the installer to reject this input.'
}

try {
    $source = Join-Path $temporary 'source'
    $destination = Join-Path $temporary 'installed'
    $null = New-Item -ItemType Directory -Path (Join-Path $source '.github/skills/example')
    $file = Join-Path $source '.github/skills/example/SKILL.md'
    Set-Content -LiteralPath $file -Value 'Fixture content' -NoNewline
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = @{
        sourceRevision = ('a' * 40)
        files = @{ '.github/skills/example/SKILL.md' = $hash }
    }
    $manifestPath = Join-Path $source 'manifest.json'
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
    Set-Content -LiteralPath (Join-Path $source 'unlisted.txt') -Value 'Must not be copied'
    $result = & $installer -SourceDirectory $source -DestinationDirectory $destination
    Assert-True ($result.Action -eq 'Installed' -and $result.Files -eq 2) 'Fresh install failed.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destination 'unlisted.txt'))) 'Unlisted file was copied.'
    $passed++

    $result = & $installer -SourceDirectory $source -DestinationDirectory $destination
    Assert-True ($result.Action -eq 'AlreadyPresent') 'Identical install was not idempotent.'
    $passed++

    $installedFile = Join-Path $destination '.github/skills/example/SKILL.md'
    Set-Content -LiteralPath $installedFile -Value 'Learner edit' -NoNewline
    Assert-Rejected { & $installer -SourceDirectory $source -DestinationDirectory $destination }
    Assert-True ((Get-Content -LiteralPath $installedFile -Raw) -eq 'Learner edit') 'An existing edit was overwritten.'
    $passed++

    Set-Content -LiteralPath $file -Value 'Tampered source' -NoNewline
    $newDestination = Join-Path $temporary 'must-not-exist'
    Assert-Rejected { & $installer -SourceDirectory $source -DestinationDirectory $newDestination }
    Assert-True (-not (Test-Path -LiteralPath $newDestination)) 'Invalid source created a destination.'
    $passed++

    $manifest.files = @{ '../outside.txt' = $hash }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
    Assert-Rejected { & $installer -SourceDirectory $source -DestinationDirectory $newDestination }
    Assert-True (-not (Test-Path -LiteralPath $newDestination)) 'Unsafe manifest created a destination.'
    $passed++

    $actual = Join-Path $temporary 'actual-package'
    $result = & $installer -DestinationDirectory $actual
    Assert-True ($result.Action -eq 'Installed' -and $result.Files -eq 85) 'The actual validated package did not install.'
    $result = & $installer -DestinationDirectory $actual
    Assert-True ($result.Action -eq 'AlreadyPresent') 'The actual package did not verify on a repeat run.'
    $passed++

    Write-Host "Passed $passed installer checks."
} finally {
    [IO.Directory]::Delete($temporary, $true)
}
