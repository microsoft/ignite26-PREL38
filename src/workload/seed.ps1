[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apiName = az containerapp list `
    --resource-group $ResourceGroupName `
    --query "[?starts_with(name, 'ca-caldova-api-')].name | [0]" `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($apiName)) {
    throw "Caldova API container app was not found in '$ResourceGroupName'. Verify provisioning completed for user$LearnerNumber."
}

$output = az containerapp exec `
    --resource-group $ResourceGroupName `
    --name $apiName `
    --command "node /app/scripts/seed.js" 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Caldova database seed failed inside '$apiName'. Azure CLI output:`n$($output | Out-String)"
}

$seedLine = $output | Where-Object { $_ -match '"status"\s*:\s*"seeded"' } | Select-Object -Last 1
if (-not $seedLine) {
    throw "Caldova seed command completed without a seeded status record. Output:`n$($output | Out-String)"
}

Write-Host "Caldova data seed completed in $apiName."
Write-Host $seedLine
