param(
    [string]$BinDir,
    [switch]$PurgeWindowsConfig
)

$ErrorActionPreference = "Stop"

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $temporaryPath = "$Path.agent-stack-$PID.tmp"
    try {
        $json = $Value | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText(
            $temporaryPath,
            "$json`r`n",
            (New-Object Text.UTF8Encoding($false))
        )
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Get-NormalizedPathEntry {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return [IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($Path)
        ).TrimEnd("\")
    } catch {
        Write-Warning "Preserving an unrecognized user PATH entry: $Path"
        return $null
    }
}

$repoRoot = $PSScriptRoot
$launcher = Join-Path $repoRoot "bin\windows\agent-stack.ps1"
$manager = Join-Path $repoRoot "scripts\manage-windows-command-links.ps1"
$homePath = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::UserProfile
)
$configDir = $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG_DIR
if ([string]::IsNullOrWhiteSpace($configDir)) {
    $configDir = Join-Path $homePath ".config\remote-agent-stack"
} elseif (-not [IO.Path]::IsPathFullyQualified($configDir)) {
    [Console]::Error.WriteLine(
        "REMOTE_AGENT_STACK_WINDOWS_CONFIG_DIR must be an absolute path."
    )
    exit 1
}
$configDir = [IO.Path]::GetFullPath($configDir)
$configPath = Join-Path $configDir "config.windows.json"
$statePath = Join-Path $configDir "install-state.windows.json"
$state = $null

if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    } catch {
        [Console]::Error.WriteLine(
            "Cannot parse Windows install state '$statePath': $($_.Exception.Message)"
        )
        exit 1
    }
}
if ([string]::IsNullOrWhiteSpace($BinDir)) {
    if ($null -ne $state -and
        $null -ne $state.PSObject.Properties["binDir"]) {
        $BinDir = [string]$state.binDir
    } else {
        $BinDir = Join-Path $homePath "bin"
    }
}
if (-not [IO.Path]::IsPathFullyQualified($BinDir)) {
    [Console]::Error.WriteLine("BinDir must be an absolute path.")
    exit 1
}
$BinDir = [IO.Path]::GetFullPath($BinDir)

& $manager -Mode uninstall -Launcher $launcher -BinDir $BinDir
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$pathAdded = $null -ne $state -and
    $null -ne $state.PSObject.Properties["pathAdded"] -and
    [bool]$state.pathAdded
if ($pathAdded) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $remaining = New-Object System.Collections.Generic.List[string]
    foreach ($entry in ($userPath -split ";")) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }
        $normalizedEntry = Get-NormalizedPathEntry $entry
        $same = $null -ne $normalizedEntry -and
            $normalizedEntry -ieq $BinDir.TrimEnd("\")
        if (-not $same) {
            [void]$remaining.Add($entry)
        }
    }
    [Environment]::SetEnvironmentVariable(
        "Path",
        ($remaining.ToArray() -join ";"),
        "User"
    )
}

if ($PurgeWindowsConfig) {
    foreach ($path in @($configPath, $statePath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
} else {
    if ($null -eq $state) {
        $state = [pscustomobject]@{
            schemaVersion = 1
            checkout = [IO.Path]::GetFullPath($repoRoot)
            launcher = [IO.Path]::GetFullPath($launcher)
            binDir = $BinDir
            configPath = $configPath
            pathAdded = $false
            installed = $false
        }
    } else {
        $state.pathAdded = $false
        $state.installed = $false
    }
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Write-JsonAtomic $statePath $state
}

Write-Host "Removed Agent Stack-owned Windows commands."
Write-Host "Provider workspaces, sessions, authentication, and macOS config were preserved."
