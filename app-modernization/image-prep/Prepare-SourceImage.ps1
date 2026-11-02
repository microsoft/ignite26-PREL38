$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:USERNAME -ine 'LabUser') { throw 'Run preparation as LabUser.' }
$root = 'C:\lab\prel38-image-prep'
$modules = 'C:\lab\caldova\modules'
$repos = @(Get-ChildItem -LiteralPath $modules -Directory -Filter 'module-*' | ForEach-Object {
    foreach ($side in 'start', 'finish') {
        $path = Join-Path $_.FullName $side
        if (Test-Path -LiteralPath (Join-Path $path '.git')) { $path }
    }
})
if ($repos.Count -ne 6) { throw 'Expected six module repositories.' }
$baseline = @(
    foreach ($repo in $repos) {
        $branch = & git -C $repo symbolic-ref --short HEAD
        if ($LASTEXITCODE -ne 0 -or $branch -cne 'main') { throw "Unexpected branch: $repo" }
        $changes = @(& git -C $repo status --porcelain --untracked-files=all)
        if ($LASTEXITCODE -ne 0 -or $changes.Count) { throw "Repository is not clean: $repo" }
        $refs = @(& git -C $repo for-each-ref '--format=%(refname:short):%(objectname)' refs/heads)
        if ($LASTEXITCODE -ne 0) { throw "Could not read branches: $repo" }
        [pscustomobject]@{ Path = $repo; Branch = $branch; Refs = $refs }
    }
)
if (($baseline | ForEach-Object { $_.Refs } | Measure-Object).Count -ne 12) {
    throw 'Expected twelve local branches.'
}
$baseline | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$root\baseline.json"
Write-Host 'PRECHECK PASSED: six clean repositories, twelve branches, all on main.'

& "$root\app-modernization\Rename-PreparedReports.ps1" -WarningAction Stop
& "$root\app-modernization\Set-AssessmentDefaults.ps1"
& "$root\Verify-PreparedImage.ps1" -BaselinePath "$root\baseline.json"

$first = @($repos | ForEach-Object {
    $refs = @(& git -C $_ for-each-ref '--format=%(refname):%(objectname)' refs/heads)
    if ($LASTEXITCODE -ne 0) { throw 'Could not record prepared branches.' }
    $refs
})
& "$root\app-modernization\Rename-PreparedReports.ps1" -WarningAction Stop
& "$root\app-modernization\Set-AssessmentDefaults.ps1"
$second = @($repos | ForEach-Object {
    $refs = @(& git -C $_ for-each-ref '--format=%(refname):%(objectname)' refs/heads)
    if ($LASTEXITCODE -ne 0) { throw 'Could not recheck prepared branches.' }
    $refs
})
if (@(Compare-Object $first $second).Count) { throw 'The second preparation changed branch commits.' }
& "$root\Verify-PreparedImage.ps1" -BaselinePath "$root\baseline.json"
Write-Host 'SOURCE IMAGE PREPARATION PASSED; SECOND RUN UNCHANGED.'
