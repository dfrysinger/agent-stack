param()

$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) {
        throw $Label
    }
}

function Invoke-Manager {
    param([string]$Mode)

    & $script:manager -Mode $Mode -Launcher $script:launcher -BinDir $script:bin |
        Out-Host
    return $LASTEXITCODE
}

function Get-LegacyShimContent {
    param(
        [Parameter(Mandatory = $true)][string]$Invocation,
        [Parameter(Mandatory = $true)][string]$LauncherPath
    )

    return @(
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
    ) -join "`r`n"
}

$root = Join-Path ([IO.Path]::GetTempPath()) "agent-stack-links-test-$PID"
$manager = Join-Path $PSScriptRoot "manage-windows-command-links.ps1"
$launcher = Join-Path $root "agent-stack.ps1"
$bin = Join-Path $root "bin"
$compatibilityBase64 = "QGVjaG8gb2ZmDQpzZXRsb2NhbA0KaWYgbm90IGRlZmluZWQgQ09QSUxPVF9BR0VOVF9MQVVOQ0hFUiBzZXQgIkNPUElMT1RfQUdFTlRfTEFVTkNIRVI9JVVTRVJQUk9GSUxFJVwuY29waWxvdFxpbnN0YWxsZWQtcGx1Z2luc1xfZGlyZWN0XGRmcnlzaW5nZXItLXNraWxsc1xza2lsbHNcbWFpbGJveFxzY3JpcHRzXGNvcGlsb3QtYWdlbnQucHMxIg0KaWYgbm90IGV4aXN0ICIlQ09QSUxPVF9BR0VOVF9MQVVOQ0hFUiUiICgNCiAgZWNobyBNaXNzaW5nIGRldGVybWluaXN0aWMgV2luZG93cyBhZ2VudCBsYXVuY2hlcjogJUNPUElMT1RfQUdFTlRfTEFVTkNIRVIlIDE+JjINCiAgZXhpdCAvYiAyDQopDQoiJVN5c3RlbVJvb3QlXFN5c3RlbTMyXHdoZXJlLmV4ZSIgcHdzaCA+bnVsIDI+JjENCmlmICVFUlJPUkxFVkVMJSBlcXUgMCAoDQogIHB3c2ggLU5vUHJvZmlsZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSAiJUNPUElMT1RfQUdFTlRfTEFVTkNIRVIlIiAlKg0KKSBlbHNlICgNCiAgaWYgbm90IGV4aXN0ICIlU3lzdGVtUm9vdCVcU3lzdGVtMzJcV2luZG93c1Bvd2VyU2hlbGxcdjEuMFxwb3dlcnNoZWxsLmV4ZSIgKA0KICAgIGVjaG8gTWlzc2luZyBQb3dlclNoZWxsIGhvc3QgcmVxdWlyZWQgYnkgZGV0ZXJtaW5pc3RpYyBXaW5kb3dzIGFnZW50IGxhdW5jaGVyLiAxPiYyDQogICAgZXhpdCAvYiAyDQogICkNCiAgIiVTeXN0ZW1Sb290JVxTeXN0ZW0zMlxXaW5kb3dzUG93ZXJTaGVsbFx2MS4wXHBvd2Vyc2hlbGwuZXhlIiAtTm9Qcm9maWxlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlICIlQ09QSUxPVF9BR0VOVF9MQVVOQ0hFUiUiICUqDQopDQpleGl0IC9iICVFUlJPUkxFVkVMJQ0K"

try {
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    Set-Content -LiteralPath $launcher -Value "# launcher"

    foreach ($sourceShim in Get-ChildItem (
        Join-Path $PSScriptRoot "..\bin\windows\*.cmd"
    )) {
        $sourceContent = Get-Content -LiteralPath $sourceShim.FullName -Raw
        Assert-True (-not $sourceContent.Contains("powershell.exe")) (
            "source shim retained the unsupported Windows PowerShell fallback"
        )
        Assert-True ($sourceContent.Contains(
            "Agent Stack requires PowerShell 7"
        )) "source shim omitted the PowerShell 7 requirement"
    }

    Assert-True ((Invoke-Manager "check") -eq 0) "initial preflight failed"
    Assert-True ((Invoke-Manager "install") -eq 0) "initial install failed"
    foreach ($name in @(
        "agent-stack.cmd",
        "copilot-agent.cmd",
        "claude-agent.cmd",
        "codex-agent.cmd"
    )) {
        Assert-True (Test-Path -LiteralPath (Join-Path $bin $name) -PathType Leaf) (
            "missing installed $name"
        )
    }

    Assert-True ((Invoke-Manager "install") -eq 0) "idempotent install failed"
    Assert-True ((Invoke-Manager "uninstall") -eq 0) "uninstall failed"
    Assert-True ((Get-ChildItem -LiteralPath $bin -File).Count -eq 0) (
        "owned shims remained"
    )

    $legacyPath = Join-Path $bin "agent-stack.cmd"
    [IO.File]::WriteAllText(
        $legacyPath,
        (Get-LegacyShimContent "agent-stack" $launcher),
        (New-Object Text.UTF8Encoding($false))
    )
    Assert-True ((Invoke-Manager "uninstall") -eq 0) (
        "legacy owned shim uninstall failed"
    )
    Assert-True (-not (Test-Path -LiteralPath $legacyPath)) (
        "legacy owned shim remained"
    )

    $compatibilityPath = Join-Path $bin "copilot-agent.cmd"
    [IO.File]::WriteAllBytes(
        $compatibilityPath,
        [Convert]::FromBase64String($compatibilityBase64)
    )
    Assert-True ((Invoke-Manager "check") -eq 0) (
        "compatible Copilot preflight failed"
    )
    Assert-True ((Invoke-Manager "install") -eq 0) (
        "compatible Copilot install failed"
    )
    $compatibleHash = (Get-FileHash $compatibilityPath -Algorithm SHA256).Hash
    Assert-True (
        $compatibleHash -eq "CF356D665FCB79F91F53FF40B9A502C205182AC3FDF548551E30289534FCE322"
    ) "compatible Copilot wrapper changed"
    Assert-True ((Invoke-Manager "uninstall") -eq 0) (
        "compatible Copilot uninstall failed"
    )
    Assert-True (Test-Path -LiteralPath $compatibilityPath) (
        "compatible Copilot wrapper was removed"
    )

    Set-Content -LiteralPath (Join-Path $bin "agent-stack.cmd") -Value "foreign"
    Assert-True ((Invoke-Manager "check") -eq 1) (
        "foreign canonical command passed preflight"
    )
    Assert-True (
        (Get-Content -LiteralPath (Join-Path $bin "agent-stack.cmd") -Raw).Contains(
            "foreign"
        )
    ) "foreign canonical command changed"

    "manage-windows-command-links tests passed"
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
