param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("check", "install", "uninstall")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$Launcher,

    [Parameter(Mandatory = $true)]
    [string]$BinDir
)

$ErrorActionPreference = "Stop"

function Stop-Manager {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine($Message)
    exit 1
}

function Get-ShimContent {
    param(
        [Parameter(Mandatory = $true)][string]$Invocation,
        [Parameter(Mandatory = $true)][string]$LauncherPath
    )

    $lines = @(
        "@echo off",
        "rem agent-stack windows shim v1",
        "setlocal",
        "set `"AGENT_STACK_INVOCATION=$Invocation`"",
        "set `"AGENT_STACK_WINDOWS_LAUNCHER=$LauncherPath`"",
        "where pwsh >nul 2>&1",
        "if %ERRORLEVEL% neq 0 (",
        "  echo Agent Stack requires PowerShell 7 ^(pwsh^). 1>&2",
        "  exit /b 1",
        ")",
        "pwsh -NoProfile -ExecutionPolicy Bypass -File `"%AGENT_STACK_WINDOWS_LAUNCHER%`" %*",
        "exit /b %ERRORLEVEL%",
        ""
    )
    return ($lines -join "`r`n")
}

function Get-LegacyShimContent {
    param(
        [Parameter(Mandatory = $true)][string]$Invocation,
        [Parameter(Mandatory = $true)][string]$LauncherPath
    )

    $lines = @(
        "@echo off",
        "rem agent-stack windows shim v1",
        "setlocal",
        "set `"AGENT_STACK_INVOCATION=$Invocation`"",
        "set `"AGENT_STACK_WINDOWS_LAUNCHER=$LauncherPath`"",
        "where pwsh >nul 2>&1",
        "if %ERRORLEVEL% equ 0 (",
        "  pwsh -NoProfile -ExecutionPolicy Bypass -File `"%AGENT_STACK_WINDOWS_LAUNCHER%`" %*",
        ") else (",
        "  `"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -ExecutionPolicy Bypass -File `"%AGENT_STACK_WINDOWS_LAUNCHER%`" %*",
        ")",
        "exit /b %ERRORLEVEL%",
        ""
    )
    return ($lines -join "`r`n")
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-OwnedShim {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedContents
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    return $AllowedContents -ccontains [IO.File]::ReadAllText($Path)
}

function Test-CompatibleCopilotShim {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $approvedHashes = @(
        "CF356D665FCB79F91F53FF40B9A502C205182AC3FDF548551E30289534FCE322"
    )
    return (Get-FileSha256 $Path) -in $approvedHashes
}

function Write-AtomicText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $temporaryPath = "$Path.agent-stack-$PID.tmp"
    try {
        [IO.File]::WriteAllText(
            $temporaryPath,
            $Content,
            (New-Object Text.UTF8Encoding($false))
        )
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

if (-not [IO.Path]::IsPathFullyQualified($Launcher)) {
    Stop-Manager "Launcher must be an absolute path."
}
$launcherPath = [IO.Path]::GetFullPath($Launcher)
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    Stop-Manager "Launcher does not exist: $launcherPath"
}
if (-not [IO.Path]::IsPathFullyQualified($BinDir)) {
    Stop-Manager "BinDir must be an absolute path."
}
$binPath = [IO.Path]::GetFullPath($BinDir)
if (Test-Path -LiteralPath $binPath -PathType Leaf) {
    Stop-Manager "BinDir must be a directory path."
}

$commands = [ordered]@{
    "agent-stack.cmd" = "agent-stack"
    "copilot-agent.cmd" = "copilot-agent"
    "claude-agent.cmd" = "claude-agent"
    "codex-agent.cmd" = "codex-agent"
}
$plans = New-Object System.Collections.Generic.List[object]
$preflightFailed = $false

foreach ($entry in $commands.GetEnumerator()) {
    $path = Join-Path $binPath $entry.Key
    $expected = Get-ShimContent $entry.Value $launcherPath
    $legacy = Get-LegacyShimContent $entry.Value $launcherPath
    $kind = "install"
    if (Test-OwnedShim $path @($expected, $legacy)) {
        $kind = "owned"
    } elseif ($entry.Key -eq "copilot-agent.cmd" -and
        (Test-CompatibleCopilotShim $path)) {
        $kind = "compatible"
    } elseif (Test-Path -LiteralPath $path) {
        $kind = "foreign"
        $preflightFailed = $true
    }
    [void]$plans.Add([pscustomobject]@{
        Name = $entry.Key
        Invocation = $entry.Value
        Path = $path
        Expected = $expected
        AllowedContents = @($expected, $legacy)
        Kind = $kind
    })
}

if ($Mode -in @("check", "install") -and $preflightFailed) {
    foreach ($plan in $plans | Where-Object Kind -eq "foreign") {
        [Console]::Error.WriteLine(
            "refusing to overwrite foreign command: $($plan.Path)"
        )
    }
    exit 1
}

if ($Mode -eq "check") {
    foreach ($plan in $plans) {
        switch ($plan.Kind) {
            "owned" { "owned: $($plan.Path)" }
            "compatible" { "preserve compatible external command: $($plan.Path)" }
            default { "install: $($plan.Path)" }
        }
    }
    exit 0
}

if ($Mode -eq "install") {
    New-Item -ItemType Directory -Path $binPath -Force | Out-Null
    foreach ($plan in $plans) {
        if ($plan.Kind -eq "compatible") {
            "preserved compatible external command: $($plan.Path)"
            continue
        }
        Write-AtomicText $plan.Path $plan.Expected
        "installed $($plan.Path)"
    }
    exit 0
}

foreach ($plan in $plans) {
    if (Test-OwnedShim $plan.Path $plan.AllowedContents) {
        Remove-Item -LiteralPath $plan.Path -Force
        "removed $($plan.Path)"
    } elseif (Test-Path -LiteralPath $plan.Path) {
        "preserved external command: $($plan.Path)"
    }
}
