#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'Rename-PreparedReports.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('prel38-rename-test-' + [Guid]::NewGuid().ToString('N'))
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-Repo([string]$Path, [string[]]$Branches) {
    $reports = Join-Path $Path '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts'
    $null = New-Item -ItemType Directory -Force -Path $reports
    Set-Content -LiteralPath (Join-Path $reports 'data.md') -Value 'ZavaAuthGateway uses .ZAVAAUTH and zava-loans' -NoNewline
    [IO.File]::WriteAllText((Join-Path $reports 'utf16.txt'), 'Zava in UTF-16', [Text.Encoding]::Unicode)
    [IO.File]::WriteAllBytes((Join-Path $reports 'blob.bin'), [byte[]](0, 1, 2) + [Text.Encoding]::ASCII.GetBytes('zava'))
    Set-Content -LiteralPath (Join-Path $Path '.github/modernize/repos.json') -Value '{"repos":["six"]}'
    Set-Content -LiteralPath (Join-Path $Path '.github/modernize/repos-live.json') -Value '{"repos":["one"]}'
    git -C $Path init -q -b main
    git -C $Path add -A
    git -C $Path -c user.name=t -c user.email=t@t commit -q -m start
    foreach ($b in $Branches) { git -C $Path branch $b }
}

try {
    $root = Join-Path $temporary 'modules'
    New-Repo (Join-Path $root 'module-01-assess/start') @()
    New-Repo (Join-Path $root 'module-02-plan/finish') @('modernization/dotnet')
    $dirty = Join-Path $root 'module-01-assess/start'
    Set-Content -LiteralPath (Join-Path $dirty 'live-output.txt') -Value 'Zava untracked'

    $results = @(& $script -ModulesRoot $root -WarningAction SilentlyContinue)
    Assert-True ($results.Count -eq 3) "Expected three branch results, got $($results.Count)."
    Assert-True (@($results | Where-Object { -not $_.Committed }).Count -eq 0) 'Every branch should be committed.'
    $passed++

    foreach ($repo in $dirty, (Join-Path $root 'module-02-plan/finish')) {
        $facts = Join-Path $repo '.github/modernize/assessment-prebuilt/reports-1/repos/CaldovaAuthGateway/facts'
        Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $facts 'data.md')) -ceq 'CaldovaAuthGateway uses .CALDOVAAUTH and caldova-loans') 'Text content was not renamed.'
        Assert-True ([IO.File]::ReadAllText((Join-Path $facts 'utf16.txt'), [Text.Encoding]::Unicode) -ceq 'Caldova in UTF-16') 'UTF-16 content was not renamed.'
        Assert-True ([IO.File]::ReadAllBytes((Join-Path $facts 'blob.bin'))[0] -eq 0) 'Binary file was rewritten.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway'))) 'Old Zava folder was left behind.'
        Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $repo '.github/modernize/repos.json')).Trim() -eq '{"repos":["one"]}') 'repos.json is not the one-app list.'
        Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $repo '.github/modernize/repos-portfolio.json')).Trim() -eq '{"repos":["six"]}') 'repos-portfolio.json is not the six-app list.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo '.github/modernize/repos-live.json'))) 'repos-live.json was left behind.'
        Assert-True (-not (git -C $repo status --porcelain --untracked-files=no)) 'Tracked changes were left uncommitted.'
    }
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $dirty 'live-output.txt')).Trim() -eq 'Zava untracked') 'An untracked file was changed.'
    $branchFile = git -C (Join-Path $root 'module-02-plan/finish') show 'modernization/dotnet:.github/modernize/assessment-prebuilt/reports-1/repos/CaldovaAuthGateway/facts/data.md'
    Assert-True ($branchFile -match 'CaldovaAuthGateway') 'A second branch was not renamed.'
    Assert-True ((git -C (Join-Path $root 'module-02-plan/finish') branch --show-current) -eq 'main') 'The original branch was not restored.'
    $passed++

    $again = @(& $script -ModulesRoot $root -WarningAction SilentlyContinue)
    Assert-True (@($again | Where-Object { $_.Committed -or $_.Changed -or $_.Renamed -or $_.Swapped }).Count -eq 0) 'A second run changed something.'
    $passed++

    foreach ($list in 'repos.json', 'repos-live.json') {
        $dirtyRoot = Join-Path $temporary "dirty-$list/modules"
        $repo = Join-Path $dirtyRoot 'module-01-assess/start'
        New-Repo $repo @()
        $listPath = Join-Path $repo ".github/modernize/$list"
        Set-Content -LiteralPath $listPath -Value '{"repos":["local changes"]}'
        $result = @(& $script -ModulesRoot $dirtyRoot -WarningAction SilentlyContinue)
        Assert-True (-not $result[0].Swapped) "A locally modified $list was swapped."
        Assert-True ((Get-Content -Raw -LiteralPath $listPath).Trim() -eq '{"repos":["local changes"]}') "Local changes to $list were lost."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo '.github/modernize/repos-portfolio.json'))) 'The portfolio list was created despite local changes.'
        Assert-True ((git -C $repo diff --name-only HEAD) -contains ".github/modernize/$list") "Local changes to $list were committed."
    }
    $passed++

    $reportRoot = Join-Path $temporary 'dirty-report/modules'
    $reportRepo = Join-Path $reportRoot 'module-01-assess/start'
    New-Repo $reportRepo @()
    git -C $reportRepo rm -q -- '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts/blob.bin'
    git -C $reportRepo -c user.name=t -c user.email=t@t commit -q -m 'Remove binary fixture'
    $reportRel = '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts/data.md'
    $reportPath = Join-Path $reportRepo $reportRel
    Set-Content -LiteralPath $reportPath -Value 'Zava report with local changes' -NoNewline
    try {
        $null = & $script -ModulesRoot $reportRoot -WarningAction Stop
        throw 'Expected a modified report warning to stop preparation.'
    }
    catch {
        Assert-True ($_.Exception.Message -like '*Skipped locally modified file:*data.md*') "Unexpected warning failure: $_"
    }
    $warnings = @(& $script -ModulesRoot $reportRoot 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    Assert-True (@($warnings | Where-Object { "$_" -like '*Skipped locally modified file:*data.md' }).Count -ge 1) "A skipped modified report did not produce a warning: $($warnings -join '; ')"
    Assert-True ((Get-Content -Raw -LiteralPath $reportPath) -ceq 'Zava report with local changes') 'The modified report was changed.'
    Assert-True ((git -C $reportRepo diff --name-only HEAD) -contains $reportRel) 'The modified report was committed.'
    $passed++

    $missingRoot = Join-Path $temporary 'missing-report/modules'
    $missingRepo = Join-Path $missingRoot 'module-01-assess/start'
    New-Repo $missingRepo @()
    git -C $missingRepo update-index --skip-worktree -- $reportRel
    Remove-Item -LiteralPath (Join-Path $missingRepo $reportRel)
    $warnings = @(& $script -ModulesRoot $missingRoot 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    Assert-True (@($warnings | Where-Object { "$_" -like '*Skipped missing tracked file:*data.md' }).Count -ge 1) "A missing tracked report did not produce a warning: $($warnings -join '; ')"
    $passed++

    $emptyRoot = Join-Path $temporary 'empty/modules'
    $null = New-Item -ItemType Directory -Force -Path $emptyRoot
    try {
        & $script -ModulesRoot $emptyRoot
        throw 'Expected an empty modules directory to fail.'
    }
    catch {
        Assert-True ($_.Exception.Message -like 'No module repositories found*') "Unexpected error for an empty modules directory: $_"
    }
    $passed++

    "Passed $passed checks."
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
