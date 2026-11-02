<#
.SYNOPSIS
Renames Zava to Caldova in the prepared module repositories and makes repos.json the one-app list.
.DESCRIPTION
Run during image preparation, before the image is captured. For every module repository under
-ModulesRoot and on every local branch, it replaces Zava, ZAVA and zava with Caldova, CALDOVA and
caldova in tracked text files and in their paths, removes the folders the renames leave empty, and
commits. It also renames .github\modernize\repos.json (six apps) to repos-portfolio.json and
repos-live.json (one app) to repos.json, so learners can accept the default path. Untracked files,
locally modified files and binary files are not changed. Running it again changes nothing.
#>
[CmdletBinding()]
param(
    [string]$ModulesRoot = 'C:\lab\caldova\modules',
    [switch]$SkipRepoListSwap
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$pairs = @(@('Zava', 'Caldova'), @('ZAVA', 'CALDOVA'), @('zava', 'caldova'))
$latin1 = [Text.Encoding]::GetEncoding(28591)

function Convert-Brand([string]$Text) {
    foreach ($pair in $pairs) { $Text = $Text.Replace($pair[0], $pair[1]) }
    $Text
}

# A simple function (no param block), so git options such as -c and --literal-pathspecs reach git unchanged.
function Invoke-Git {
    $repo = $args[0]
    $gitArgs = @($args | Select-Object -Skip 1)
    $ErrorActionPreference = 'Continue'
    $out = & git -C $repo -c core.quotepath=off @gitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($gitArgs -join ' ') failed in ${repo}: $out" }
    $out | ForEach-Object { "$_" }
}

function Read-RepoList([string]$Path) {
    try { $list = [IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    catch { throw "Cannot read repository list ${Path}: $($_.Exception.Message)" }
    if ($null -eq $list -or $list -is [array] -or
        $null -eq $list.PSObject.Properties['repos'] -or $list.repos -isnot [array]) {
        throw "Repository list $Path must contain a repos array."
    }
    $list
}

function Get-RepoListAction([string]$Repo, [string[]]$Modified, [string[]]$Tracked) {
    if ($SkipRepoListSwap) { return 'skip' }
    $default = '.github/modernize/repos.json'
    $live = '.github/modernize/repos-live.json'
    $portfolio = '.github/modernize/repos-portfolio.json'
    $hasDefault = $Tracked -contains $default
    $hasLive = $Tracked -contains $live
    $hasPortfolio = $Tracked -contains $portfolio
    $livePath = Join-Path $Repo $live
    $portfolioPath = Join-Path $Repo $portfolio

    if ($hasDefault -and $hasLive -and -not $hasPortfolio -and -not (Test-Path -LiteralPath $portfolioPath)) {
        $one = $live
        $all = $default
        $action = 'swap'
    }
    elseif ($hasDefault -and -not $hasLive -and $hasPortfolio -and -not (Test-Path -LiteralPath $livePath)) {
        $one = $default
        $all = $portfolio
        $action = 'ready'
    }
    else {
        Write-Warning "Skipped repository list swap in ${Repo}: the tracked lists are missing, incomplete, or conflict with existing files."
        return 'skip'
    }

    $changedLists = @($one, $all | Where-Object { $Modified -contains $_ })
    if ($changedLists.Count) {
        Write-Warning "Skipped repository list swap in ${Repo}: locally modified files: $($changedLists -join ', ')."
        return 'skip'
    }
    foreach ($rel in $one, $all) {
        if (-not (Test-Path -LiteralPath (Join-Path $Repo $rel) -PathType Leaf)) {
            Write-Warning "Skipped repository list swap in ${Repo}: tracked file $rel is missing."
            return 'skip'
        }
    }

    $onePath = Join-Path $Repo $one
    $oneList = Read-RepoList $onePath
    $allList = Read-RepoList (Join-Path $Repo $all)
    if ($oneList.repos.Count -ne 1 -or $null -eq $oneList.repos[0] -or
        $null -eq $oneList.repos[0].PSObject.Properties['name'] -or
        $oneList.repos[0].name -isnot [string] -or
        $null -eq $oneList.repos[0].PSObject.Properties['path'] -or
        $oneList.repos[0].path -isnot [string] -or
        (Convert-Brand $oneList.repos[0].name) -cne 'CaldovaAuthGateway' -or
        (Convert-Brand $oneList.repos[0].path) -notmatch '[\\/]CaldovaAuthGateway[\\/]?$') {
        throw "Repository list $onePath must select only CaldovaAuthGateway with a path to that app."
    }
    $portfolioError = "Repository list $(Join-Path $Repo $all) must contain the six-app portfolio with a name and path for each app."
    if ($allList.repos.Count -ne 6) { throw $portfolioError }
    foreach ($entry in $allList.repos) {
        if ($null -eq $entry -or $null -eq $entry.PSObject.Properties['name'] -or
            $entry.name -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.name) -or
            $null -eq $entry.PSObject.Properties['path'] -or
            $entry.path -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.path)) {
            throw $portfolioError
        }
    }
    $action
}

function Repair-Branch([string]$Repo) {
    $modified = @(Invoke-Git $Repo diff --name-only HEAD)
    $trackedLists = @(Invoke-Git $Repo ls-files -- .github/modernize)
    $listAction = Get-RepoListAction $Repo $modified $trackedLists
    $staged = New-Object Collections.Generic.List[string]
    $emptied = New-Object Collections.Generic.HashSet[string]
    $result = [ordered]@{ Changed = 0; Renamed = 0; Binary = 0; Swapped = $false; Committed = $false }
    foreach ($rel in @(Invoke-Git $Repo ls-files)) {
        $path = [IO.Path]::GetFullPath((Join-Path $Repo $rel))
        if ($modified -contains $rel) { Write-Warning "Skipped locally modified file: $path"; continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Warning "Skipped missing tracked file: $path"; continue }
        $bytes = [IO.File]::ReadAllBytes($path)
        $prefix = 0
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = [Text.Encoding]::Unicode; $prefix = 2 }
        elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $encoding = [Text.Encoding]::BigEndianUnicode; $prefix = 2 }
        elseif ([Array]::IndexOf($bytes, [byte]0, 0, [Math]::Min(8192, $bytes.Length)) -ge 0) { $encoding = $null }
        else { $encoding = $latin1 }
        if ($null -eq $encoding) {
            if ($latin1.GetString($bytes).ToLowerInvariant().Contains('zava')) { $result.Binary++; Write-Warning "Binary file not changed: $path" }
        }
        else {
            $text = $encoding.GetString($bytes, $prefix, $bytes.Length - $prefix)
            $updated = Convert-Brand $text
            if ($updated -cne $text) {
                $body = $encoding.GetBytes($updated)
                $out = New-Object byte[] ($prefix + $body.Length)
                [Array]::Copy($bytes, $out, $prefix)
                [Array]::Copy($body, 0, $out, $prefix, $body.Length)
                [IO.File]::WriteAllBytes($path, $out)
                $staged.Add($rel); $result.Changed++
            }
        }
        $newRel = Convert-Brand $rel
        if ($newRel -cne $rel) {
            $target = [IO.Path]::GetFullPath((Join-Path $Repo $newRel))
            if (Test-Path -LiteralPath $target) { throw "Cannot rename $path because $target already exists." }
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)
            Move-Item -LiteralPath $path -Destination $target
            $staged.Add($rel); $staged.Add($newRel); $result.Renamed++
            $parent = Split-Path -Parent $path
            while ($parent.Length -gt $Repo.Length) { $null = $emptied.Add($parent); $parent = Split-Path -Parent $parent }
        }
    }
    $emptied | Sort-Object Length -Descending | Where-Object { (Test-Path -LiteralPath $_) -and -not (Get-ChildItem -LiteralPath $_ -Force) } |
        ForEach-Object { Remove-Item -LiteralPath $_ }

    if ($listAction -eq 'swap') {
        $null = Invoke-Git $Repo mv .github/modernize/repos.json .github/modernize/repos-portfolio.json
        $null = Invoke-Git $Repo mv .github/modernize/repos-live.json .github/modernize/repos.json
        $null = $staged.Remove('.github/modernize/repos-live.json')
        $staged.Add('.github/modernize/repos.json')
        $staged.Add('.github/modernize/repos-portfolio.json')
        $result.Swapped = $true
    }

    if ($staged.Count) {
        $pathspecs = [IO.Path]::GetTempFileName()
        try {
            [IO.File]::WriteAllLines($pathspecs, $staged)
            $null = Invoke-Git $Repo --literal-pathspecs add -A "--pathspec-from-file=$pathspecs"
        }
        finally { Remove-Item -LiteralPath $pathspecs }
    }
    $null = & git -C $Repo diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        $null = Invoke-Git $Repo -c 'user.name=Caldova Lab' -c 'user.email=lab@caldova.invalid' commit -q -m 'Use Caldova names in prepared reports and make repos.json the one-app list'
        $result.Committed = $true
    }
    elseif ($LASTEXITCODE -ne 0) {
        throw "Could not check staged changes in $Repo (git exit code $LASTEXITCODE)."
    }
    [pscustomobject]$result
}

$repos = @(Get-ChildItem -LiteralPath $ModulesRoot -Directory | ForEach-Object {
    foreach ($side in 'start', 'finish') {
        $repo = Join-Path $_.FullName $side
        if (Test-Path -LiteralPath (Join-Path $repo '.git')) { $repo }
    }
})
if ($repos.Count -eq 0) { throw "No module repositories found under $ModulesRoot." }
foreach ($repo in $repos) {
    $null = & git -C $repo diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw "$repo has staged changes. Commit or unstage them first." }
    $current = Invoke-Git $repo symbolic-ref --short HEAD
    $hasLocalChanges = [bool](Invoke-Git $repo status --porcelain --untracked-files=no)
    $branches = @($current) + @(Invoke-Git $repo for-each-ref '--format=%(refname:short)' refs/heads | Where-Object { $_ -ne $current })
    foreach ($branch in $branches) {
        if ($branch -ne $current) {
            if ($hasLocalChanges) { Write-Warning "Skipped branch $branch in ${repo}: the current branch has local changes."; continue }
            $null = Invoke-Git $repo checkout -q $branch
        }
        try { Repair-Branch $repo | Select-Object @{ n = 'Repository'; e = { $repo } }, @{ n = 'Branch'; e = { $branch } }, * }
        finally { if ($branch -ne $current) { $null = Invoke-Git $repo checkout -q $current } }
    }
}
