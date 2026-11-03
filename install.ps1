param(
    [string]$BinDir,
    [string]$CopilotWorkspaceBase,
    [string]$ClaudeWorkspaceBase,
    [string]$CodexWorkspaceBase,
    [string]$Machine,
    [ValidateSet("true", "false")][string]$AllowAll,
    [ValidateSet("true", "false")][string]$MailboxIntegration,
    [switch]$AddToPath
)

$ErrorActionPreference = "Stop"

function Stop-Install {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine($Message)
    exit 1
}

function Get-ExistingProperty {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue
    )

    if ($null -ne $Object -and
        $null -ne $Object.PSObject.Properties[$Name]) {
        return $Object.$Name
    }
    return $DefaultValue
}

function Resolve-InstallDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not [IO.Path]::IsPathFullyQualified($Path)) {
        Stop-Install "$Label must be an absolute path."
    }
    $resolved = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        Stop-Install "$Label must be a directory path."
    }
    return $resolved
}

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

function Resolve-ProviderBinary {
    param(
        [Parameter(Mandatory = $true)][string]$ConfiguredValue,
        [Parameter(Mandatory = $true)][string]$DefaultCommand,
        [Parameter(Mandatory = $true)][string]$PackageDirectoryPattern,
        [Parameter(Mandatory = $true)][string]$ExecutableName
    )

    if ($ConfiguredValue -cne $DefaultCommand -or
        $null -ne (Get-Command $DefaultCommand -ErrorAction SilentlyContinue)) {
        return $ConfiguredValue
    }

    $packageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        return $ConfiguredValue
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $packageRoot -Directory |
            Where-Object { $_.Name -like $PackageDirectoryPattern } |
            ForEach-Object {
                Join-Path $_.FullName $ExecutableName
            } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Sort-Object
    )
    if ($candidates.Count -eq 0) {
        return $ConfiguredValue
    }
    return [IO.Path]::GetFullPath($candidates[-1])
}

if ($env:OS -ne "Windows_NT") {
    Stop-Install "install.ps1 supports Windows only."
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Stop-Install "install.ps1 requires PowerShell 7 (pwsh)."
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
    Stop-Install "REMOTE_AGENT_STACK_WINDOWS_CONFIG_DIR must be an absolute path."
}
$configDir = [IO.Path]::GetFullPath($configDir)
$configPath = Join-Path $configDir "config.windows.json"
$statePath = Join-Path $configDir "install-state.windows.json"

$existingState = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $existingState = Get-Content -LiteralPath $statePath -Raw |
            ConvertFrom-Json
    } catch {
        Stop-Install "Cannot parse existing Windows install state '$statePath': $($_.Exception.Message)"
    }
}

$existingConfig = $null
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    try {
        $existingConfig = Get-Content -LiteralPath $configPath -Raw |
            ConvertFrom-Json
    } catch {
        Stop-Install "Cannot parse existing Windows config '$configPath': $($_.Exception.Message)"
    }
}

if ([string]::IsNullOrWhiteSpace($BinDir)) {
    $BinDir = Get-ExistingProperty $existingState "binDir" (
        Join-Path $homePath "bin"
    )
}
$BinDir = Resolve-InstallDirectory $BinDir "BinDir"
if ($null -ne $existingState -and
    [bool](Get-ExistingProperty $existingState "installed" $false)) {
    $previousBinDir = Resolve-InstallDirectory (
        [string](Get-ExistingProperty $existingState "binDir" "")
    ) "Existing install-state binDir"
    if ($previousBinDir -ine $BinDir) {
        Stop-Install "Uninstall the existing Windows commands before changing BinDir."
    }
}

if ([string]::IsNullOrWhiteSpace($CopilotWorkspaceBase)) {
    $CopilotWorkspaceBase = Get-ExistingProperty $existingConfig (
        "COPILOT_WORKSPACE_BASE"
    ) (Join-Path $homePath "agent-workspaces\copilot")
}
if ([string]::IsNullOrWhiteSpace($ClaudeWorkspaceBase)) {
    $ClaudeWorkspaceBase = Get-ExistingProperty $existingConfig (
        "CLAUDE_WORKSPACE_BASE"
    ) (Join-Path $homePath "agent-workspaces\claude")
}
if ([string]::IsNullOrWhiteSpace($CodexWorkspaceBase)) {
    $CodexWorkspaceBase = Get-ExistingProperty $existingConfig (
        "CODEX_WORKSPACE_BASE"
    ) (Join-Path $homePath "agent-workspaces\codex")
}
$CopilotWorkspaceBase = Resolve-InstallDirectory $CopilotWorkspaceBase (
    "CopilotWorkspaceBase"
)
$ClaudeWorkspaceBase = Resolve-InstallDirectory $ClaudeWorkspaceBase (
    "ClaudeWorkspaceBase"
)
$CodexWorkspaceBase = Resolve-InstallDirectory $CodexWorkspaceBase (
    "CodexWorkspaceBase"
)

if ([string]::IsNullOrWhiteSpace($Machine)) {
    $Machine = $env:COPILOT_AGENT_MACHINE
}
if ([string]::IsNullOrWhiteSpace($Machine)) {
    $Machine = [string](Get-ExistingProperty $existingConfig (
        "COPILOT_AGENT_MACHINE"
    ) "")
}
if ($Machine -cnotmatch "\A[a-z0-9][a-z0-9._-]{0,127}\z") {
    Stop-Install "Machine must be a lowercase mailbox-safe name of 1-128 characters."
}

if ([string]::IsNullOrWhiteSpace($AllowAll)) {
    $AllowAll = [string](Get-ExistingProperty $existingConfig "ALLOW_ALL" $false)
}
if ([string]::IsNullOrWhiteSpace($MailboxIntegration)) {
    $MailboxIntegration = [string](Get-ExistingProperty $existingConfig (
        "MAILBOX_INTEGRATION"
    ) $false)
}
$allowAllValue = [Convert]::ToBoolean($AllowAll)
$mailboxValue = [Convert]::ToBoolean($MailboxIntegration)
$agentDirPrefix = [string](Get-ExistingProperty $existingConfig (
    "AGENT_DIR_PREFIX"
) "agent-")
if ($agentDirPrefix -cnotmatch "\A[A-Za-z0-9._-]*\z") {
    Stop-Install "AGENT_DIR_PREFIX may contain only ASCII letters, digits, dot, underscore, and hyphen."
}
$copilotBin = [string](Get-ExistingProperty $existingConfig "COPILOT_BIN" "copilot")
$claudeBin = Resolve-ProviderBinary `
    -ConfiguredValue ([string](Get-ExistingProperty $existingConfig "CLAUDE_BIN" "claude")) `
    -DefaultCommand "claude" `
    -PackageDirectoryPattern "Anthropic.ClaudeCode_*" `
    -ExecutableName "claude.exe"
$codexBin = Resolve-ProviderBinary `
    -ConfiguredValue ([string](Get-ExistingProperty $existingConfig "CODEX_BIN" "codex")) `
    -DefaultCommand "codex" `
    -PackageDirectoryPattern "OpenAI.Codex_*" `
    -ExecutableName "codex-x86_64-pc-windows-msvc.exe"

& $manager -Mode check -Launcher $launcher -BinDir $BinDir
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

foreach ($path in @(
    $CopilotWorkspaceBase,
    $ClaudeWorkspaceBase,
    $CodexWorkspaceBase,
    $configDir
)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

$config = [ordered]@{
    COPILOT_WORKSPACE_BASE = $CopilotWorkspaceBase
    CLAUDE_WORKSPACE_BASE = $ClaudeWorkspaceBase
    CODEX_WORKSPACE_BASE = $CodexWorkspaceBase
    COPILOT_BIN = $copilotBin
    CLAUDE_BIN = $claudeBin
    CODEX_BIN = $codexBin
    AGENT_DIR_PREFIX = $agentDirPrefix
    ALLOW_ALL = $allowAllValue
    MAILBOX_INTEGRATION = $mailboxValue
    COPILOT_AGENT_MACHINE = $Machine
}
Write-JsonAtomic $configPath $config

& $manager -Mode install -Launcher $launcher -BinDir $BinDir
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @(
    $userPath -split ";" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
$binAlreadyOnPath = $false
foreach ($entry in $pathEntries) {
    $normalizedEntry = Get-NormalizedPathEntry $entry
    if ($null -ne $normalizedEntry -and
        $normalizedEntry -ieq $BinDir.TrimEnd("\")) {
        $binAlreadyOnPath = $true
        break
    }
}
$pathAdded = $false
if ($null -ne $existingState -and
    [bool](Get-ExistingProperty $existingState "pathAdded" $false)) {
    $previousBinDir = Resolve-InstallDirectory (
        [string](Get-ExistingProperty $existingState "binDir" "")
    ) "Existing install-state binDir"
    $pathAdded = $previousBinDir -ieq $BinDir
}
if ($AddToPath -and -not $binAlreadyOnPath) {
    $newUserPath = (@($pathEntries) + $BinDir) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    $env:PATH = "$env:PATH;$BinDir"
    $pathAdded = $true
}

$state = [ordered]@{
    schemaVersion = 1
    checkout = [IO.Path]::GetFullPath($repoRoot)
    launcher = [IO.Path]::GetFullPath($launcher)
    binDir = $BinDir
    configPath = $configPath
    pathAdded = $pathAdded
    installed = $true
}
Write-JsonAtomic $statePath $state

Write-Host "Windows Agent Stack installed."
Write-Host "  Commands: $BinDir"
Write-Host "  Config:   $configPath"
if (-not $binAlreadyOnPath -and -not $pathAdded) {
    Write-Warning "$BinDir is not on the user PATH. Re-run with -AddToPath or add it manually."
}
foreach ($provider in @(
    @{ Name = "copilot"; Command = $copilotBin },
    @{ Name = "claude"; Command = $claudeBin },
    @{ Name = "codex"; Command = $codexBin }
)) {
    if (Get-Command $provider.Command -ErrorAction SilentlyContinue) {
        Write-Host "  found: $($provider.Name) ($($provider.Command))"
    } else {
        Write-Warning "$($provider.Name) is not available at '$($provider.Command)'."
    }
}
Write-Host "Complete any real provider login directly in that provider's TUI."
