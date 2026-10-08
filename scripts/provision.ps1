[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$Location,
    [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
    [Parameter(Mandatory)][string]$DeploymentToken,
    [Parameter(Mandatory)][string]$PortalImage,
    [Parameter(Mandatory)][string]$ApiImage,
    [Parameter(Mandatory)][string]$ApiLatencyImage,
    [ValidateRange(100, 10000)][int]$QuizLatencyThresholdMs = 900,
    [Parameter(Mandatory)][string]$VmAdminSshPublicKey,
    [string]$PostgresLocation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Caldova.Lifecycle.psm1') -Force

Assert-CaldovaLearnerInput -LearnerNumber $LearnerNumber -DeploymentToken $DeploymentToken
Assert-CaldovaCommand -Name 'az'

if (-not (Test-CaldovaContainerImage -Image $PortalImage)) {
    throw "PortalImage must reference a real Caldova container image. Placeholder or quickstart images are rejected. Build/publish the portal artifact and pass its registry/repository:tag."
}
if (-not (Test-CaldovaContainerImage -Image $ApiImage)) {
    throw "ApiImage must reference the prebuilt healthy Caldova API image. Placeholder or quickstart images are rejected."
}
if (-not (Test-CaldovaContainerImage -Image $ApiLatencyImage)) {
    throw "ApiLatencyImage must reference the prebuilt Caldova quiz-latency API image. Build and publish src/api/Dockerfile.latency before the workshop; attendee runtime builds are not supported."
}
if ($ApiImage -eq $ApiLatencyImage) {
    throw "ApiImage and ApiLatencyImage must be different immutable image references so reset can prove which revision is active."
}
if ($VmAdminSshPublicKey -notmatch '^ssh-(rsa|ed25519|ecdsa)\s+\S+') {
    throw "VmAdminSshPublicKey is not a supported OpenSSH public key. Pass the complete public key, for example 'ssh-ed25519 AAAA... lab@skillable'."
}

$postgresPassword = $env:CALDOVA_POSTGRES_ADMIN_PASSWORD
if ([string]::IsNullOrWhiteSpace($postgresPassword) -or $postgresPassword.Length -lt 16) {
    throw "CALDOVA_POSTGRES_ADMIN_PASSWORD must contain the deployment-time PostgreSQL password and be at least 16 characters. Skillable must inject it as a protected environment variable."
}

$repositoryRoot = Get-CaldovaRepositoryRoot
$templatePath = Join-Path $repositoryRoot 'infra/main.bicep'
Assert-CaldovaFile -Path $templatePath -Purpose 'Caldova Bicep entry point'

Invoke-CaldovaAz -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
Invoke-CaldovaAz -Arguments @('bicep', 'build', '--file', $templatePath, '--stdout') | Out-Null

$deploymentName = "caldova-user$LearnerNumber-$($DeploymentToken.ToLowerInvariant() -replace '[^a-z0-9]', '')"
if ($deploymentName.Length -gt 64) {
    $deploymentName = $deploymentName.Substring(0, 64)
}

$deploymentParameters = @{
    location = $Location
    learnerNumber = $LearnerNumber
    deploymentToken = $DeploymentToken
    portalImage = $PortalImage
    apiImage = $ApiImage
    apiLatencyImage = $ApiLatencyImage
    quizLatencyThresholdMs = $QuizLatencyThresholdMs
    postgresAdminPassword = $postgresPassword
    vmAdminSshPublicKey = $VmAdminSshPublicKey
}
if (-not [string]::IsNullOrWhiteSpace($PostgresLocation)) {
    $deploymentParameters.postgresLocation = $PostgresLocation
}

$parameterFile = $null
try {
    $parameterFile = New-CaldovaProtectedParameterFile `
        -Parameters $deploymentParameters `
        -SensitiveParameterNames @('postgresAdminPassword', 'vmAdminSshPublicKey', 'deploymentToken')
    $arguments = @(
        'deployment', 'sub', 'create',
        '--name', $deploymentName,
        '--location', $Location,
        '--template-file', $templatePath,
        '--parameters', "@$parameterFile",
        '--query', 'properties.outputs',
        '--output', 'json'
    )
    $outputs = Invoke-CaldovaAz `
        -Arguments $arguments `
        -SensitiveValues @($postgresPassword, $VmAdminSshPublicKey, $DeploymentToken) `
        -ReturnJson
} finally {
    if ($null -ne $parameterFile) {
        Remove-CaldovaProtectedParameterFile -Path $parameterFile
    }
}
if ($null -eq $outputs -or $null -eq $outputs.resourceGroupName.value) {
    throw "Azure deployment completed without the expected resourceGroupName output. Inspect deployment '$deploymentName' before retrying."
}

$state = @{
    schemaVersion = 2
    subscriptionId = $SubscriptionId
    location = $Location
    learnerNumber = $LearnerNumber
    deploymentToken = $DeploymentToken
    deploymentName = $deploymentName
    resourceGroupName = $outputs.resourceGroupName.value
    resourceGroupId = $outputs.resourceGroupId.value
    publicEndpoint = $outputs.publicEndpoint.value
    portalFqdn = $outputs.portalFqdn.value
    apiFqdn = $outputs.apiFqdn.value
    apiHealthyImage = $outputs.apiHealthyImage.value
    apiLatencyImage = $outputs.apiLatencyImage.value
    quizLatencyThresholdMs = $QuizLatencyThresholdMs
    logAnalyticsWorkspaceName = $outputs.logAnalyticsWorkspaceName.value
    applicationInsightsName = $outputs.applicationInsightsName.value
    postgresServerName = $outputs.postgresServerName.value
    reportingWorkerName = $outputs.reportingWorkerName.value
    preconfiguredAgentName = $outputs.preconfiguredAgentName.value
    configuredAgentName = $outputs.configuredAgentName.value
    preconfiguredAgentPortalUrl = $outputs.preconfiguredAgentPortalUrl.value
    configuredAgentPortalUrl = $outputs.configuredAgentPortalUrl.value
}
$statePath = Save-CaldovaState -LearnerNumber $LearnerNumber -State $state

Write-Host "Provision complete for user$LearnerNumber."
Write-Host "Resource group: $($state.resourceGroupName)"
Write-Host "Public endpoint: $($state.publicEndpoint)"
Write-Host "State: $statePath"
