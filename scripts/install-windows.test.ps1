param()

$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) {
        throw $Label
    }
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$installer = Join-Path $repoRoot "install.ps1"
$uninstaller = Join-Path $repoRoot "uninstall.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) "agent-stack-install-test-$PID"
$bin = Join-Path $root "bin"
$configDir = Join-Path $root "config"
$copilot = Join-Path $root "workspaces\copilot"
$claude = Join-Path $root "workspaces\claude"
$codex = Join-Path $root "workspaces\codex"
$originalConfigDir = $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG_DIR
$originalLocalAppData = $env:LOCALAPPDATA
$originalPath = $env:PATH

try {
    $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG_DIR = $configDir
    $env:LOCALAPPDATA = Join-Path $root "local-app-data"
    $env:PATH = $bin
    $claudeBinary = Join-Path $env:LOCALAPPDATA (
        "Microsoft\WinGet\Packages\Anthropic.ClaudeCode_test\claude.exe"
    )
    $codexBinary = Join-Path $env:LOCALAPPDATA (
        "Microsoft\WinGet\Packages\OpenAI.Codex_test\codex-x86_64-pc-windows-msvc.exe"
    )
    foreach ($path in @($claudeBinary, $codexBinary)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force |
            Out-Null
        Set-Content -LiteralPath $path -Value "test executable"
    }

    & $installer -BinDir $bin `
        -CopilotWorkspaceBase $copilot `
        -ClaudeWorkspaceBase $claude `
        -CodexWorkspaceBase $codex `
        -Machine "surface-pro" `
        -AllowAll "false" `
        -MailboxIntegration "true"
    Assert-True ($LASTEXITCODE -eq 0) "installer failed"

    foreach ($path in @($copilot, $claude, $codex)) {
        Assert-True (Test-Path -LiteralPath $path -PathType Container) (
            "missing workspace root $path"
        )
    }
    foreach ($name in @(
        "agent-stack.cmd",
        "copilot-agent.cmd",
        "claude-agent.cmd",
        "codex-agent.cmd"
    )) {
        Assert-True (Test-Path -LiteralPath (Join-Path $bin $name) -PathType Leaf) (
            "missing installed command $name"
        )
    }

    $configPath = Join-Path $configDir "config.windows.json"
    $statePath = Join-Path $configDir "install-state.windows.json"
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-True ($config.COPILOT_AGENT_MACHINE -ceq "surface-pro") (
        "machine was not persisted"
    )
    Assert-True ([bool]$config.MAILBOX_INTEGRATION) (
        "mailbox setting was not persisted"
    )
    Assert-True ($config.CLAUDE_BIN -ceq $claudeBinary) (
        "Claude WinGet fallback was not persisted"
    )
    Assert-True ($config.CODEX_BIN -ceq $codexBinary) (
        "Codex WinGet fallback was not persisted"
    )
    Assert-True ([bool]$state.installed) "install state not live"
    Assert-True (-not [bool]$state.pathAdded) "test unexpectedly changed PATH"

    $config.AGENT_DIR_PREFIX = "custom-"
    $config | Add-Member -NotePropertyName MAILBOX_SCRIPTS_DIR `
        -NotePropertyValue (Join-Path $root "custom-mailbox-scripts")
    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
    $state.pathAdded = $true
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8

    & $installer -Machine "surface-pro"
    Assert-True ($LASTEXITCODE -eq 0) "idempotent installer failed"
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-True ($config.AGENT_DIR_PREFIX -ceq "custom-") (
        "idempotent install reset the workspace prefix"
    )
    Assert-True (
        $config.MAILBOX_SCRIPTS_DIR -ceq (Join-Path $root "custom-mailbox-scripts")
    ) "idempotent install lost the mailbox scripts directory"
    Assert-True ($state.binDir -ceq $bin) (
        "idempotent install changed the command directory"
    )
    Assert-True ([bool]$state.pathAdded) (
        "idempotent install lost the PATH ownership receipt"
    )

    $sentinel = Join-Path $copilot "sentinel.txt"
    Set-Content -LiteralPath $sentinel -Value "preserve"
    & $uninstaller -BinDir $bin
    Assert-True ($LASTEXITCODE -eq 0) "uninstaller failed"
    Assert-True (Test-Path -LiteralPath $sentinel -PathType Leaf) (
        "uninstaller removed provider workspace data"
    )
    Assert-True (Test-Path -LiteralPath $configPath -PathType Leaf) (
        "uninstaller removed config without purge"
    )
    foreach ($name in @(
        "agent-stack.cmd",
        "copilot-agent.cmd",
        "claude-agent.cmd",
        "codex-agent.cmd"
    )) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $bin $name))) (
            "uninstaller preserved owned command $name"
        )
    }

    & $uninstaller -BinDir $bin -PurgeWindowsConfig
    Assert-True ($LASTEXITCODE -eq 0) "purge uninstall failed"
    Assert-True (-not (Test-Path -LiteralPath $configPath)) (
        "purge preserved Windows config"
    )
    Assert-True (-not (Test-Path -LiteralPath $statePath)) (
        "purge preserved Windows install state"
    )
    Assert-True (Test-Path -LiteralPath $sentinel -PathType Leaf) (
        "purge removed provider workspace data"
    )

    "install-windows tests passed"
} finally {
    $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG_DIR = $originalConfigDir
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
