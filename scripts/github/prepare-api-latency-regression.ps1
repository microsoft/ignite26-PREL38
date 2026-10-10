[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{4,32}$')][string]$InstanceToken,
    [string]$Remote = 'origin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$healthy = Join-Path $repoRoot 'src/api/lib/latency-profile.js'
$regression = Join-Path $repoRoot 'src/api/variants/latency-profile.bad.js'
$branch = "simulation/api-latency-$InstanceToken"

if (git -C $repoRoot status --porcelain) {
    throw 'The learner repository has uncommitted changes. Commit or discard them before preparing the regression branch.'
}

git -C $repoRoot switch -c $branch main
Copy-Item -LiteralPath $regression -Destination $healthy -Force
node --check $healthy
git -C $repoRoot add -- src/api/lib/latency-profile.js
git -C $repoRoot commit -m "Introduce quiz latency regression"
git -C $repoRoot push --set-upstream $Remote $branch

Write-Host "Prepared regression branch '$branch'. The learner repository workflow will build and deploy this commit."
Write-Host 'Recovery path: diagnose the deployed commit, open a PR that restores the healthy latency profile, merge to protected main, and verify the main workflow redeploys a healthy immutable digest.'
