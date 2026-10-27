#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$SourceDirectory = (Join-Path $PSScriptRoot 'final/dotnet'),
    [string]$DestinationDirectory = 'C:\lab\caldova\modules\module-03-execute\final\dotnet'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SafeFilePath {
    param([string]$Root, [string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains(':') -or
        @($RelativePath -split '[\\/]' | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw "Manifest contains an unsafe relative path: '$RelativePath'."
    }
    $relative = $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    return [IO.Path]::GetFullPath((Join-Path $Root $relative))
}

function Assert-NoLink {
    param([string]$Root, [string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Linked files or directories are not supported: '$($item.FullName)'."
        }
        if ($item.FullName -eq $Root) { return }
        $item = if ($item -is [IO.DirectoryInfo]) { $item.Parent } else { $item.Directory }
    }
    throw "Path is outside the expected source or destination root: '$Path'."
}

$source = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($SourceDirectory))
$destination = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($DestinationDirectory))
$parent = [IO.Path]::GetDirectoryName($destination)
if ([string]::IsNullOrEmpty($parent) -or $destination -eq [IO.Path]::GetPathRoot($destination)) {
    throw 'The destination must be a dedicated final-state directory, not a filesystem root.'
}
if ($destination -eq $source -or
    $destination.StartsWith($source + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The destination must not be the source directory or a child of it.'
}

$manifestPath = Join-Path $source 'manifest.json'
Assert-NoLink -Root $source -Path $manifestPath
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
if ($manifest.files -isnot [System.Collections.IDictionary] -or $manifest.files.Count -eq 0) {
    throw 'The final-state manifest must contain a nonempty file/hash map.'
}
$files = foreach ($entry in ($manifest.files.GetEnumerator() | Sort-Object Key)) {
    if ([string]$entry.Value -notmatch '^[a-fA-F0-9]{64}$') {
        throw "Invalid SHA-256 value for '$($entry.Key)'."
    }
    $path = Get-SafeFilePath -Root $source -RelativePath $entry.Key
    Assert-NoLink -Root $source -Path $path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "Source verification failed for '$($entry.Key)'. Nothing was installed."
    }
    [pscustomobject]@{ RelativePath = $entry.Key; SourcePath = $path; Hash = $entry.Value }
}
$files = @($files)

if (Test-Path -LiteralPath $destination) {
    if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
        throw "Destination already exists and is not a directory: '$destination'."
    }
    $existingManifest = Join-Path $destination 'manifest.json'
    if (-not (Test-Path -LiteralPath $existingManifest -PathType Leaf)) {
        throw "Destination already exists without the expected manifest. No files were replaced: '$destination'."
    }
    Assert-NoLink -Root $destination -Path $existingManifest
    if ((Get-FileHash -LiteralPath $existingManifest -Algorithm SHA256).Hash -ne $manifestHash) {
        throw "Destination has a different manifest. Version or inspect it; no files were replaced: '$destination'."
    }
    foreach ($file in $files) {
        $path = Get-SafeFilePath -Root $destination -RelativePath $file.RelativePath
        Assert-NoLink -Root $destination -Path $path
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.Hash) {
            throw "Destination differs at '$($file.RelativePath)'. No files were replaced."
        }
    }
    [pscustomobject]@{
        Action = 'AlreadyPresent'; Destination = $destination
        Files = $files.Count + 1; SourceRevision = $manifest.sourceRevision
        ManifestSha256 = $manifestHash.ToLowerInvariant()
    }
    return
}

$null = [IO.Directory]::CreateDirectory($parent)
$staging = $null
try {
    $stagePath = Join-Path $parent ('.dotnet-final-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $stagePath
    $staging = $stagePath
    foreach ($file in $files) {
        $target = Get-SafeFilePath -Root $staging -RelativePath $file.RelativePath
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        [IO.File]::Copy($file.SourcePath, $target, $false)
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $file.Hash) {
            throw "Staged copy verification failed for '$($file.RelativePath)'."
        }
    }
    $stagedManifest = Join-Path $staging 'manifest.json'
    [IO.File]::Copy($manifestPath, $stagedManifest, $false)
    if ((Get-FileHash -LiteralPath $stagedManifest -Algorithm SHA256).Hash -ne $manifestHash) {
        throw 'The source manifest changed during installation.'
    }
    # Directory.Move refuses a concurrently created destination instead of merging into it.
    [IO.Directory]::Move($staging, $destination)
    $staging = $null
} finally {
    if ($null -ne $staging -and [IO.Directory]::Exists($staging)) {
        [IO.Directory]::Delete($staging, $true)
    }
}

[pscustomobject]@{
    Action = 'Installed'; Destination = $destination
    Files = $files.Count + 1; SourceRevision = $manifest.sourceRevision
    ManifestSha256 = $manifestHash.ToLowerInvariant()
}
