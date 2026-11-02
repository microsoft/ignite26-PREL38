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

function New-Repo([string]$Path, [string[]]$Branches, [switch]$WithoutBinary) {
    $reports = Join-Path $Path '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts'
    $null = New-Item -ItemType Directory -Force -Path $reports
    Set-Content -LiteralPath (Join-Path $reports 'data.md') -Value 'ZavaAuthGateway uses .ZAVAAUTH and zava-loans' -NoNewline
    [IO.File]::WriteAllText((Join-Path $reports 'utf16.txt'), 'Zava in UTF-16', [Text.Encoding]::Unicode)
    if (-not $WithoutBinary) {
        [IO.File]::WriteAllBytes((Join-Path $reports 'blob.bin'), [byte[]](0, 1, 2) + [Text.Encoding]::ASCII.GetBytes('zava'))
    }
    Set-Content -LiteralPath (Join-Path $Path '.github/modernize/repos.json') -Value '{"repos":[{"name":"CaldovaAuthGateway","path":"C:/lab/caldova/apps/CaldovaAuthGateway"},{"name":"CaldovaLoanPortal","path":"C:/lab/caldova/apps/CaldovaLoanPortal"},{"name":"CaldovaRiskEngine","path":"C:/lab/caldova/apps/CaldovaRiskEngine"},{"name":"App4","path":"C:/lab/caldova/apps/App4"},{"name":"App5","path":"C:/lab/caldova/apps/App5"},{"name":"App6","path":"C:/lab/caldova/apps/App6"}]}'
    Set-Content -LiteralPath (Join-Path $Path '.github/modernize/repos-live.json') -Value '{"repos":[{"name":"CaldovaAuthGateway","path":"C:/lab/caldova/apps/CaldovaAuthGateway"}]}'
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
        $one = Get-Content -Raw -LiteralPath (Join-Path $repo '.github/modernize/repos.json') | ConvertFrom-Json
        $six = Get-Content -Raw -LiteralPath (Join-Path $repo '.github/modernize/repos-portfolio.json') | ConvertFrom-Json
        Assert-True (@($one.repos).Count -eq 1 -and $one.repos[0].name -eq 'CaldovaAuthGateway') 'repos.json is not the one-app list.'
        Assert-True (@($six.repos).Count -eq 6) 'repos-portfolio.json is not the six-app list.'
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

    $multiRoot = Join-Path $temporary 'multiple-repositories/modules'
    $layout = @(
        @{ Repo = 'module-01-assess/start'; Branches = @() }
        @{ Repo = 'module-01-assess/finish'; Branches = @() }
        @{ Repo = 'module-02-plan/start'; Branches = @('modernization/dotnet') }
        @{ Repo = 'module-02-plan/finish'; Branches = @('modernization/dotnet', 'modernization/java') }
        @{ Repo = 'module-03-execute/start'; Branches = @('modernization/dotnet', 'modernization/java') }
        @{ Repo = 'module-03-execute/finish'; Branches = @('modernization/dotnet', 'modernization/java') }
    )
    foreach ($item in $layout) {
        New-Repo (Join-Path $multiRoot $item.Repo) $item.Branches -WithoutBinary
    }
    $divergentRepo = Join-Path $multiRoot 'module-02-plan/start'
    git -C $divergentRepo checkout -q modernization/dotnet
    $divergentList = Join-Path $divergentRepo '.github/modernize/repos-live.json'
    $divergentText = (Get-Content -Raw -LiteralPath $divergentList).Replace('CaldovaAuthGateway', 'ZavaAuthGateway')
    Set-Content -LiteralPath $divergentList -Value $divergentText -NoNewline
    git -C $divergentRepo add -A
    git -C $divergentRepo -c user.name=t -c user.email=t@t commit -q -m 'Use legacy names on one branch'
    git -C $divergentRepo checkout -q main

    $multiResults = @(& $script -ModulesRoot $multiRoot -WarningAction Stop)
    Assert-True ($multiResults.Count -eq 13) "Expected thirteen branch results, got $($multiResults.Count)."
    Assert-True (@($multiResults | Where-Object { -not $_.Committed -or -not $_.Swapped }).Count -eq 0) 'Every branch should be committed and have its lists swapped.'
    foreach ($item in $layout) {
        $repo = Join-Path $multiRoot $item.Repo
        foreach ($branch in @('main') + $item.Branches) {
            $one = (git -C $repo show "${branch}:.github/modernize/repos.json") | ConvertFrom-Json
            $six = (git -C $repo show "${branch}:.github/modernize/repos-portfolio.json") | ConvertFrom-Json
            $report = git -C $repo show "${branch}:.github/modernize/assessment-prebuilt/reports-1/repos/CaldovaAuthGateway/facts/data.md"
            Assert-True ($one.repos.Count -eq 1 -and $one.repos[0].name -ceq 'CaldovaAuthGateway' -and $one.repos[0].path -match '/CaldovaAuthGateway$') "Incorrect one-app list in $($item.Repo) ($branch)."
            Assert-True ($six.repos.Count -eq 6) "Incorrect portfolio list in $($item.Repo) ($branch)."
            Assert-True ($report -match 'CaldovaAuthGateway') "Report was not renamed in $($item.Repo) ($branch)."
        }
        Assert-True ((git -C $repo branch --show-current) -eq 'main') "The original branch was not restored in $($item.Repo)."
        Assert-True (-not (git -C $repo status --porcelain --untracked-files=no)) "Tracked changes were left in $($item.Repo)."
    }
    $multiAgain = @(& $script -ModulesRoot $multiRoot -WarningAction Stop)
    Assert-True ($multiAgain.Count -eq 13 -and @($multiAgain | Where-Object { $_.Committed -or $_.Changed -or $_.Renamed -or $_.Swapped }).Count -eq 0) 'Preparing the six repositories a second time changed something.'
    $passed++

    foreach ($list in 'repos.json', 'repos-live.json') {
        $dirtyRoot = Join-Path $temporary "dirty-$list/modules"
        $repo = Join-Path $dirtyRoot 'module-01-assess/start'
        New-Repo $repo @()
        $listPath = Join-Path $repo ".github/modernize/$list"
        Set-Content -LiteralPath $listPath -Value '{"repos":["local changes"]}'
        $before = git -C $repo rev-parse HEAD
        try {
            $null = & $script -ModulesRoot $dirtyRoot -WarningAction Stop
            throw "Expected a modified $list to stop preparation."
        }
        catch {
            Assert-True ($_.Exception.Message -like '*locally modified files:*') "Unexpected error for ${list}: $_"
        }
        Assert-True ((git -C $repo rev-parse HEAD) -eq $before) "A commit was made with a modified $list."
        Assert-True (Test-Path -LiteralPath (Join-Path $repo '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts/data.md')) 'Reports changed before the modified-list warning.'
        $result = @(& $script -ModulesRoot $dirtyRoot -WarningAction SilentlyContinue)
        Assert-True (-not $result[0].Swapped) "A locally modified $list was swapped."
        Assert-True ((Get-Content -Raw -LiteralPath $listPath).Trim() -eq '{"repos":["local changes"]}') "Local changes to $list were lost."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $repo '.github/modernize/repos-portfolio.json'))) 'The portfolio list was created despite local changes.'
        Assert-True ((git -C $repo diff --name-only HEAD) -contains ".github/modernize/$list") "Local changes to $list were committed."
    }
    $passed++

    $dirtyPreparedRoot = Join-Path $temporary 'dirty-prepared/modules'
    $dirtyPrepared = Join-Path $dirtyPreparedRoot 'module-01-assess/start'
    New-Repo $dirtyPrepared @()
    git -C $dirtyPrepared mv .github/modernize/repos.json .github/modernize/repos-portfolio.json
    git -C $dirtyPrepared mv .github/modernize/repos-live.json .github/modernize/repos.json
    git -C $dirtyPrepared -c user.name=t -c user.email=t@t commit -q -m 'Prepare lists'
    $portfolioPath = Join-Path $dirtyPrepared '.github/modernize/repos-portfolio.json'
    Set-Content -LiteralPath $portfolioPath -Value '{"repos":["local changes"]}'
    $before = git -C $dirtyPrepared rev-parse HEAD
    try {
        $null = & $script -ModulesRoot $dirtyPreparedRoot -WarningAction Stop
        throw 'Expected a modified prepared list to stop preparation.'
    }
    catch {
        Assert-True ($_.Exception.Message -like '*locally modified files:*') "Unexpected warning for the prepared list: $_"
    }
    Assert-True ((git -C $dirtyPrepared rev-parse HEAD) -eq $before) 'A commit was made with a modified prepared list.'
    Assert-True ((Get-Content -Raw -LiteralPath $portfolioPath).Trim() -eq '{"repos":["local changes"]}') 'The modified prepared list was changed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $dirtyPrepared '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts/data.md')) 'Reports changed before the prepared-list warning.'
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

    foreach ($case in 'missing-live', 'missing-live-worktree', 'missing-lists', 'portfolio-collision', 'tracked-portfolio-collision', 'prepared-live-collision') {
        $listRoot = Join-Path $temporary "$case/modules"
        $listRepo = Join-Path $listRoot 'module-01-assess/start'
        New-Repo $listRepo @()
        git -C $listRepo rm -q -- '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts/blob.bin'
        git -C $listRepo -c user.name=t -c user.email=t@t commit -q -m 'Remove binary fixture'
        switch ($case) {
            'missing-live' {
                git -C $listRepo rm -q -- '.github/modernize/repos-live.json'
                git -C $listRepo -c user.name=t -c user.email=t@t commit -q -m 'Remove live list'
            }
            'missing-live-worktree' {
                git -C $listRepo update-index --skip-worktree -- '.github/modernize/repos-live.json'
                Remove-Item -LiteralPath (Join-Path $listRepo '.github/modernize/repos-live.json')
            }
            'missing-lists' {
                git -C $listRepo rm -q -- '.github/modernize/repos.json' '.github/modernize/repos-live.json'
                git -C $listRepo -c user.name=t -c user.email=t@t commit -q -m 'Remove lists'
            }
            'portfolio-collision' {
                Set-Content -LiteralPath (Join-Path $listRepo '.github/modernize/repos-portfolio.json') -Value 'untracked data'
            }
            'tracked-portfolio-collision' {
                Set-Content -LiteralPath (Join-Path $listRepo '.github/modernize/repos-portfolio.json') -Value 'tracked data'
                git -C $listRepo add -A
                git -C $listRepo -c user.name=t -c user.email=t@t commit -q -m 'Add conflicting portfolio'
            }
            'prepared-live-collision' {
                git -C $listRepo mv .github/modernize/repos.json .github/modernize/repos-portfolio.json
                git -C $listRepo mv .github/modernize/repos-live.json .github/modernize/repos.json
                git -C $listRepo -c user.name=t -c user.email=t@t commit -q -m 'Prepare lists'
                Set-Content -LiteralPath (Join-Path $listRepo '.github/modernize/repos-live.json') -Value 'untracked data'
            }
        }
        $before = git -C $listRepo rev-parse HEAD
        try {
            $null = & $script -ModulesRoot $listRoot -WarningAction Stop
            throw "Expected $case to stop preparation."
        }
        catch {
            Assert-True ($_.Exception.Message -like '*repository list*') "Unexpected error for ${case}: $_"
        }
        Assert-True ((git -C $listRepo rev-parse HEAD) -eq $before) "A commit was made for $case."
        Assert-True (-not (git -C $listRepo status --porcelain --untracked-files=no)) "Tracked files changed for $case."
        if ($case -eq 'portfolio-collision') {
            Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $listRepo '.github/modernize/repos-portfolio.json')).Trim() -eq 'untracked data') 'The untracked portfolio file was changed.'
        }
        if ($case -eq 'prepared-live-collision') {
            Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $listRepo '.github/modernize/repos-live.json')).Trim() -eq 'untracked data') 'The untracked live list was changed.'
        }
    }
    $passed++

    foreach ($case in 'invalid-live', 'invalid-prepared', 'invalid-path', 'invalid-count', 'invalid-portfolio', 'invalid-portfolio-entry', 'invalid-portfolio-name', 'invalid-portfolio-path', 'invalid-json') {
        $listRoot = Join-Path $temporary "$case/modules"
        $listRepo = Join-Path $listRoot 'module-01-assess/start'
        New-Repo $listRepo @()
        git -C $listRepo rm -q -- '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts/blob.bin'
        git -C $listRepo -c user.name=t -c user.email=t@t commit -q -m 'Remove binary fixture'
        if ($case -eq 'invalid-prepared') {
            git -C $listRepo mv .github/modernize/repos.json .github/modernize/repos-portfolio.json
            git -C $listRepo mv .github/modernize/repos-live.json .github/modernize/repos.json
            $invalidPath = Join-Path $listRepo '.github/modernize/repos.json'
        }
        elseif ($case -like 'invalid-portfolio*') {
            $invalidPath = Join-Path $listRepo '.github/modernize/repos.json'
        }
        else {
            $invalidPath = Join-Path $listRepo '.github/modernize/repos-live.json'
        }
        switch ($case) {
            'invalid-path' {
                $contents = '{"repos":[{"name":"CaldovaAuthGateway","path":"C:/lab/caldova/apps/WrongApp"}]}'
                $expectedError = '*CaldovaAuthGateway*'
            }
            'invalid-count' {
                $contents = '{"repos":[{"name":"CaldovaAuthGateway","path":"C:/lab/apps/CaldovaAuthGateway"},{"name":"CaldovaLoanPortal","path":"C:/lab/apps/CaldovaLoanPortal"}]}'
                $expectedError = '*CaldovaAuthGateway*'
            }
            'invalid-portfolio' {
                $contents = '{"repos":[]}'
                $expectedError = '*six-app portfolio*'
            }
            'invalid-portfolio-entry' {
                $contents = '{"repos":[null,null,null,null,null,null]}'
                $expectedError = '*six-app portfolio*'
            }
            'invalid-portfolio-name' {
                $contents = '{"repos":[{"name":"","path":"C:/lab/apps/App1"},null,null,null,null,null]}'
                $expectedError = '*six-app portfolio*'
            }
            'invalid-portfolio-path' {
                $contents = '{"repos":[{"name":"App1","path":""},null,null,null,null,null]}'
                $expectedError = '*six-app portfolio*'
            }
            'invalid-json' {
                $contents = '{invalid'
                $expectedError = '*Cannot read repository list*'
            }
            default {
                $contents = '{"repos":[{"name":"WrongApp","path":"C:/lab/caldova/apps/WrongApp"}]}'
                $expectedError = '*CaldovaAuthGateway*'
            }
        }
        Set-Content -LiteralPath $invalidPath -Value $contents
        git -C $listRepo add -A
        git -C $listRepo -c user.name=t -c user.email=t@t commit -q -m 'Commit invalid one-app list'
        $before = git -C $listRepo rev-parse HEAD
        try {
            $null = & $script -ModulesRoot $listRoot -WarningAction Stop
            throw "Expected $case to stop preparation."
        }
        catch {
            Assert-True ($_.Exception.Message -like $expectedError) "Unexpected error for ${case}: $_"
        }
        Assert-True ((git -C $listRepo rev-parse HEAD) -eq $before) "A commit was made for $case."
        Assert-True (-not (git -C $listRepo status --porcelain --untracked-files=no)) "Tracked files changed for $case."
    }
    $passed++

    $legacyRoot = Join-Path $temporary 'legacy-list/modules'
    $legacyRepo = Join-Path $legacyRoot 'module-01-assess/start'
    New-Repo $legacyRepo @()
    git -C $legacyRepo rm -q -- '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts/blob.bin'
    Set-Content -LiteralPath (Join-Path $legacyRepo '.github/modernize/repos.json') -Value '{"repos":[{"name":"ZavaAuthGateway","path":"C:/lab/caldova/apps/ZavaAuthGateway"},{"name":"CaldovaLoanPortal","path":"C:/lab/caldova/apps/CaldovaLoanPortal"},{"name":"CaldovaRiskEngine","path":"C:/lab/caldova/apps/CaldovaRiskEngine"},{"name":"App4","path":"C:/lab/caldova/apps/App4"},{"name":"App5","path":"C:/lab/caldova/apps/App5"},{"name":"App6","path":"C:/lab/caldova/apps/App6"}]}'
    Set-Content -LiteralPath (Join-Path $legacyRepo '.github/modernize/repos-live.json') -Value '{"repos":[{"name":"ZavaAuthGateway","path":"C:/lab/caldova/apps/ZavaAuthGateway"}]}'
    git -C $legacyRepo add -A
    git -C $legacyRepo -c user.name=t -c user.email=t@t commit -q -m 'Use legacy app name in list'
    $null = & $script -ModulesRoot $legacyRoot -WarningAction Stop
    $one = Get-Content -Raw -LiteralPath (Join-Path $legacyRepo '.github/modernize/repos.json') | ConvertFrom-Json
    $six = Get-Content -Raw -LiteralPath (Join-Path $legacyRepo '.github/modernize/repos-portfolio.json') | ConvertFrom-Json
    Assert-True ($one.repos[0].name -ceq 'CaldovaAuthGateway' -and $one.repos[0].path -match '/CaldovaAuthGateway$') 'The legacy one-app list was not converted.'
    Assert-True ($six.repos[0].name -ceq 'CaldovaAuthGateway') 'The legacy portfolio list was not converted.'
    Assert-True (-not (git -C $legacyRepo status --porcelain --untracked-files=no)) 'Converted list changes were left uncommitted.'
    $passed++

    $skipRoot = Join-Path $temporary 'skip-lists/modules'
    $skipRepo = Join-Path $skipRoot 'module-01-assess/start'
    New-Repo $skipRepo @()
    git -C $skipRepo rm -q -- '.github/modernize/repos.json' '.github/modernize/repos-live.json' '.github/modernize/assessment-prebuilt/reports-1/repos/ZavaAuthGateway/facts/blob.bin'
    git -C $skipRepo -c user.name=t -c user.email=t@t commit -q -m 'Remove repository lists'
    $result = @(& $script -ModulesRoot $skipRoot -SkipRepoListSwap -WarningAction Stop)
    Assert-True ($result.Count -eq 1 -and $result[0].Committed -and -not $result[0].Swapped) 'Skipping repository lists did not preserve report preparation.'
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
