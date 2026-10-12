Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CaldovaRepositoryRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Assert-CaldovaCommand {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install it in the Skillable template image and retry."
    }
}

function Assert-CaldovaLearnerInput {
    param(
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][string]$DeploymentToken
    )

    if ($DeploymentToken -notmatch '^[A-Za-z0-9_-]{4,32}$') {
        throw "DeploymentToken must be 4-32 letters, numbers, underscores, or hyphens. Example: lab38-a17."
    }
}

function Get-CaldovaStatePath {
    param([Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber)

    $stateDirectory = Join-Path (Get-CaldovaRepositoryRoot) '.caldova'
    return Join-Path $stateDirectory "state-user$LearnerNumber.json"
}

function Save-CaldovaState {
    param(
        [Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber,
        [Parameter(Mandatory)][hashtable]$State
    )

    $path = Get-CaldovaStatePath -LearnerNumber $LearnerNumber
    $directory = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    return $path
}

function Get-CaldovaState {
    param([Parameter(Mandatory)][ValidateRange(1, 999)][int]$LearnerNumber)

    $path = Get-CaldovaStatePath -LearnerNumber $LearnerNumber
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Deployment state was not found at '$path'. Run scripts/provision.ps1 for local authoring or scripts/initialize-skillable-state.ps1 after the Skillable ARM deployment for user$LearnerNumber."
    }

    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Invoke-CaldovaAz {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string[]]$SensitiveValues = @(),
        [switch]$ReturnJson
    )

    Assert-CaldovaCommand -Name 'az'
    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $safeArguments = Protect-CaldovaText -Text ($Arguments -join ' ') -SensitiveValues $SensitiveValues
        $detail = Protect-CaldovaText -Text (($output | Out-String).Trim()) -SensitiveValues $SensitiveValues
        throw "Azure CLI command failed: az $safeArguments`n$detail"
    }

    if ($ReturnJson) {
        $text = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }
        $jsonStart = [regex]::Match($text, '(?m)^[\[{]')
        if (-not $jsonStart.Success) {
            throw "Azure CLI returned no JSON payload. Output:`n$(Protect-CaldovaText -Text $text -SensitiveValues $SensitiveValues)"
        }
        return $text.Substring($jsonStart.Index) | ConvertFrom-Json
    }

    return $output
}

function Close-CaldovaRecoveredAlerts {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$AlertName
    )

    $listUrl = "/subscriptions/$($Context.State.subscriptionId)/providers/Microsoft.AlertsManagement/alerts"
    $resourceGroupSegment = "/resourceGroups/$($Context.State.resourceGroupName)/"
    $result = $null
    foreach ($attempt in 1..4) {
        try {
            $result = Invoke-CaldovaAz -Arguments @(
                'rest', '--method', 'get', '--url', $listUrl,
                '--url-parameters', 'api-version=2019-03-01',
                '--output', 'json'
            ) -ReturnJson
            break
        } catch {
            if ($attempt -eq 4 -or $_.Exception.Message -notmatch '(?i)(429|Too Many Requests|quota exceeded)') { throw }
            Start-Sleep -Seconds (15 * $attempt)
        }
    }
    $openAlerts = @($result.value | Where-Object {
        $essentials = $_.properties.essentials
        $null -ne $essentials -and
        $essentials.PSObject.Properties.Name -contains 'alertRule' -and
        $essentials.PSObject.Properties.Name -contains 'targetResource' -and
        $essentials.PSObject.Properties.Name -contains 'alertState' -and
        ($essentials.alertRule -split '/')[-1] -eq $AlertName -and
        $essentials.targetResource -like "*$resourceGroupSegment*" -and
        $essentials.alertState -ne 'Closed'
    })

    foreach ($alert in $openAlerts) {
        foreach ($attempt in 1..4) {
            try {
                Invoke-CaldovaAz -Arguments @(
                    'rest', '--method', 'post', '--url', "$($alert.id)/changeState",
                    '--url-parameters', 'api-version=2019-03-01', 'newState=Closed',
                    '--output', 'none'
                ) | Out-Null
                break
            } catch {
                if ($attempt -eq 4 -or $_.Exception.Message -notmatch '(?i)(429|Too Many Requests|quota exceeded)') { throw }
                Start-Sleep -Seconds (15 * $attempt)
            }
        }

        $verified = $null
        foreach ($attempt in 1..4) {
            try {
                $verified = Invoke-CaldovaAz -Arguments @(
                    'rest', '--method', 'get', '--url', $alert.id,
                    '--url-parameters', 'api-version=2019-03-01',
                    '--output', 'json'
                ) -ReturnJson
            } catch {
                if ($attempt -eq 4 -or $_.Exception.Message -notmatch '(?i)(429|Too Many Requests|quota exceeded)') { throw }
            }
            if ($null -ne $verified -and $verified.properties.essentials.alertState -eq 'Closed') { break }
            Start-Sleep -Seconds (3 * $attempt)
        }
        if ($null -eq $verified -or $verified.properties.essentials.alertState -ne 'Closed') {
            throw "Recovered alert '$($alert.id)' did not transition to Closed."
        }
    }

    return $openAlerts.Count
}

function Protect-CaldovaText {
    param(
        [AllowEmptyString()][string]$Text,
        [string[]]$SensitiveValues = @()
    )

    $safe = $Text
    foreach ($value in @($SensitiveValues | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object Length -Descending -Unique)) {
        $safe = $safe.Replace($value, '[REDACTED]')
    }
    return $safe
}

function New-CaldovaProtectedParameterFile {
    param(
        [Parameter(Mandatory)][hashtable]$Parameters,
        [string[]]$SensitiveParameterNames = @()
    )

    $directory = Join-Path ([IO.Path]::GetTempPath()) "caldova-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path = Join-Path $directory 'deployment.parameters.json'
    try {
        $document = @{
            '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
            contentVersion = '1.0.0.0'
            parameters = @{}
        }
        foreach ($entry in $Parameters.GetEnumerator()) {
            $document.parameters[$entry.Key] = @{ value = $entry.Value }
        }
        $document | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8NoBOM

        if ($IsWindows) {
            $acl = Get-Acl -LiteralPath $path
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($rule in @($acl.Access)) {
                [void]$acl.RemoveAccessRuleAll($rule)
            }
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
            $rule = [Security.AccessControl.FileSystemAccessRule]::new(
                $identity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            )
            $acl.AddAccessRule($rule)
            Set-Acl -LiteralPath $path -AclObject $acl
        } else {
            [IO.File]::SetUnixFileMode($path, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite)
        }
        return $path
    } catch {
        Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        $names = ($SensitiveParameterNames | Sort-Object -Unique) -join ', '
        throw "Could not create the protected deployment parameter file. Sensitive parameters ($names) were not passed to Azure CLI. $($_.Exception.Message)"
    }
}

function Remove-CaldovaProtectedParameterFile {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $directory = Split-Path -Parent $Path
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and
        (Split-Path -Leaf $directory) -like 'caldova-*') {
        Remove-Item -LiteralPath $directory -Force -ErrorAction SilentlyContinue
    }
}

function Assert-CaldovaFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Purpose
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Purpose is missing at '$Path'. Add the required Caldova artifact and retry."
    }
}

function Test-CaldovaContainerImage {
    param([Parameter(Mandatory)][string]$Image)

    if ([string]::IsNullOrWhiteSpace($Image) -or
        $Image -match '(?i)(placeholder|quickstart|hello-world|replace-me)' -or
        $Image -notmatch '^[A-Za-z0-9.-]+(?::[0-9]+)?/[A-Za-z0-9._/-]+(?::[A-Za-z0-9._-]+|@sha256:[a-fA-F0-9]{64})$') {
        return $false
    }
    return $true
}

Export-ModuleMember -Function @(
    'Get-CaldovaRepositoryRoot',
    'Assert-CaldovaCommand',
    'Assert-CaldovaLearnerInput',
    'Get-CaldovaStatePath',
    'Save-CaldovaState',
    'Get-CaldovaState',
    'Invoke-CaldovaAz',
    'Close-CaldovaRecoveredAlerts',
    'Protect-CaldovaText',
    'New-CaldovaProtectedParameterFile',
    'Remove-CaldovaProtectedParameterFile',
    'Assert-CaldovaFile',
    'Test-CaldovaContainerImage'
)
