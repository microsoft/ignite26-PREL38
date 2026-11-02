#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ModulesRoot = 'C:\lab\caldova\modules',
    [string]$BaselinePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Git([string]$Repo, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $output = @(& git -C $Repo @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in ${Repo}: $($output -join ' ')"
    }
    $output | ForEach-Object { "$_" }
}

function Read-BranchJson([string]$Repo, [string]$Branch, [string]$Path) {
    (@(Invoke-Git $Repo @('show', ($Branch + ':' + $Path))) -join "`n") | ConvertFrom-Json
}

if ($env:USERNAME -ine 'LabUser') { throw 'Run this check as LabUser.' }
$repos = @(Get-ChildItem -LiteralPath $ModulesRoot -Directory -Filter 'module-*' | ForEach-Object {
    foreach ($side in 'start', 'finish') {
        $repo = Join-Path $_.FullName $side
        if (Test-Path -LiteralPath (Join-Path $repo '.git')) { $repo }
    }
})
if ($repos.Count -ne 6) { throw "Expected six repositories; found $($repos.Count)." }
$baseline = if ($BaselinePath) { @(Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json) } else { @() }
$assessment = Join-Path $ModulesRoot 'module-01-assess\start'
$expectedPath = 'C:/lab/caldova/modules/module-01-assess/start/apps/CaldovaAuthGateway'
if (-not (Test-Path -LiteralPath $expectedPath -PathType Container)) { throw 'Assessment checkout is missing.' }
$count = 0

foreach ($repo in $repos) {
    $current = Invoke-Git $repo @('symbolic-ref', '--short', 'HEAD')
    if ($current -cne 'main') { throw "Original main branch was not restored in $repo." }
    if (@(Invoke-Git $repo @('status', '--porcelain', '--untracked-files=all')).Count) {
        throw "Repository is not clean: $repo."
    }
    $branches = @(Invoke-Git $repo @('for-each-ref', '--format=%(refname:short)', 'refs/heads'))
    if ($BaselinePath) {
        $before = @($baseline | Where-Object { $_.Path -ieq $repo })
        if ($before.Count -ne 1 -or $before[0].Branch -cne $current) { throw "Baseline mismatch for $repo." }
        $oldBranches = @($before[0].Refs | ForEach-Object { ($_ -split ':', 2)[0] })
        if (@(Compare-Object $oldBranches $branches).Count) { throw "Local branches changed in $repo." }
    }
    foreach ($branch in $branches) {
        $one = Read-BranchJson $repo $branch '.github/modernize/repos.json'
        $six = Read-BranchJson $repo $branch '.github/modernize/repos-portfolio.json'
        if ($one.repos -isnot [array] -or $one.repos.Count -ne 1 -or
            $one.repos[0].name -cne 'CaldovaAuthGateway' -or
            $one.repos[0].path -notmatch '[\\/]CaldovaAuthGateway[\\/]?$' -or
            $six.repos -isnot [array] -or $six.repos.Count -ne 6 -or
            @($six.repos | Where-Object { $_.name -match '(?i)zava' -or $_.path -match '(?i)zava' }).Count) {
            throw "Incorrect repository lists in $repo ($branch)."
        }
        if ($repo -ieq $assessment -and $branch -ceq 'main' -and
            $one.repos[0].path -cne $expectedPath) {
            throw 'The assessment default points to the wrong checkout.'
        }
        $paths = @(Invoke-Git $repo @('ls-tree', '-r', '--name-only', $branch))
        if ($paths -contains '.github/modernize/repos-live.json' -or
            @($paths | Where-Object { $_ -match '(?i)zava' }).Count) {
            throw "A legacy tracked path remains in $repo ($branch)."
        }
        $reports = @($paths | Where-Object { $_ -match '^\.github/modernize/assessment(-prebuilt)?/' })
        if ($repo -ieq $assessment -and $branch -ceq 'main' -and
            @($reports | Where-Object { $_ -cmatch 'CaldovaAuthGateway' }).Count -eq 0) {
            throw 'The prepared CaldovaAuthGateway report is missing.'
        }
        $ErrorActionPreference = 'Continue'
        $matches = @(& git -C $repo grep -I -i -l zava $branch -- `
            .github/modernize/assessment-prebuilt .github/modernize/assessment 2>&1)
        $grepExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($grepExit -ne 1) {
            throw "Report branding check failed in $repo ($branch), exit ${grepExit}: $($matches -join ', ')."
        }
        $count++
    }
}
if ($count -ne 12) { throw "Expected twelve prepared branches; found $count." }
$defaults = Join-Path $HOME '.modernize\assessment-config.yaml'
$hash = (Get-FileHash -LiteralPath $defaults -Algorithm SHA256).Hash
if ($hash -ine 'd8ba1e9b5bb7b6016df2b14349abf8e41d47bf0a1ffe4feb9fb2d0a424db8195') {
    throw 'LabUser assessment defaults do not match the tested configuration.'
}
Write-Host "PASSED: $($repos.Count) clean repositories, $count prepared branches, original branches restored."
Write-Host 'PASSED: Caldova report paths and text; one-app defaults; six-app portfolios; exact assessment checkout.'
Write-Host 'PASSED: LabUser assessment defaults match the tested bytes.'
