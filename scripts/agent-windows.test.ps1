param()

$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not $Condition) {
        throw $Label
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Actual,
        [Parameter(Mandatory = $true)][AllowNull()]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $actualJson = $Actual | ConvertTo-Json -Compress -Depth 8
    $expectedJson = $Expected | ConvertTo-Json -Compress -Depth 8
    if ($actualJson -cne $expectedJson) {
        $stderr = ""
        if ($null -ne $script:stderrPath -and
            (Test-Path -LiteralPath $script:stderrPath -PathType Leaf)) {
            $stderr = "`nStderr:   $(Get-Content -LiteralPath $script:stderrPath -Raw)"
        }
        throw "$Label`nExpected: $expectedJson`nActual:   $actualJson$stderr"
    }
}

function Write-TestConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CopilotRoot,
        [Parameter(Mandatory = $true)][string]$ClaudeRoot,
        [Parameter(Mandatory = $true)][string]$CodexRoot,
        [Parameter(Mandatory = $true)][string]$FakeCommand,
        [string]$Prefix = "agent-",
        [bool]$AllowAll = $false,
        [bool]$MailboxIntegration = $false,
        [string]$MailboxScriptsDir = $script:mailboxScripts
    )

    [ordered]@{
        COPILOT_WORKSPACE_BASE = $CopilotRoot
        CLAUDE_WORKSPACE_BASE = $ClaudeRoot
        CODEX_WORKSPACE_BASE = $CodexRoot
        COPILOT_BIN = $FakeCommand
        CLAUDE_BIN = $FakeCommand
        CODEX_BIN = $FakeCommand
        AGENT_DIR_PREFIX = $Prefix
        ALLOW_ALL = $AllowAll
        MAILBOX_INTEGRATION = $MailboxIntegration
        MAILBOX_SCRIPTS_DIR = $MailboxScriptsDir
        COPILOT_AGENT_MACHINE = "surface-pro"
    } | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-Launcher {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$Invocation = "agent-stack",
        [string]$Config = $script:configPath,
        [string]$Capture = $script:capturePath,
        [string]$Stdout = $script:stdoutPath,
        [string]$Stderr = $script:stderrPath,
        [int]$FakeExit = 0,
        [int]$CodexServerExit = 0,
        [int]$CodexWatcherExit = 0,
        [int]$CodexServerLifetimeMs = 0,
        [string]$FakeRelease = ""
    )

    Remove-Item -LiteralPath (
        $Capture,
        $Stdout,
        $Stderr,
        $script:childPidsPath,
        $script:serverCapturePath,
        $script:watcherCapturePath
    ) -Force -ErrorAction SilentlyContinue
    $env:AGENT_STACK_INVOCATION = $Invocation
    $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG = $Config
    $env:FAKE_AGENT_CAPTURE = $Capture
    $env:FAKE_AGENT_EXIT = [string]$FakeExit
    $env:FAKE_AGENT_READY = ""
    $env:FAKE_AGENT_RELEASE = $FakeRelease
    $env:FAKE_AGENT_CHILD_PIDS = $script:childPidsPath
    $env:FAKE_CODEX_SERVER_CAPTURE = $script:serverCapturePath
    $env:FAKE_CODEX_WATCHER_CAPTURE = $script:watcherCapturePath
    $env:FAKE_CODEX_SERVER_EXIT = [string]$CodexServerExit
    $env:FAKE_CODEX_SERVER_LIFETIME_MS = [string]$CodexServerLifetimeMs
    $env:FAKE_CODEX_WATCHER_EXIT = [string]$CodexWatcherExit

    & $script:pwsh -NoProfile -ExecutionPolicy Bypass -File $script:launcher @Arguments `
        1>$Stdout 2>$Stderr
    return $LASTEXITCODE
}

function Read-Capture {
    param([string]$Path = $script:capturePath)

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$root = Join-Path ([IO.Path]::GetTempPath()) "agent-stack-windows-test-$PID"
$launcher = Join-Path $PSScriptRoot "..\bin\windows\agent-stack.ps1"
$launcher = [IO.Path]::GetFullPath($launcher)
$pwsh = Join-Path $PSHOME "pwsh.exe"
$configPath = Join-Path $root "config.windows.json"
$capturePath = Join-Path $root "capture.json"
$stdoutPath = Join-Path $root "stdout.txt"
$stderrPath = Join-Path $root "stderr.txt"
$fakeScript = Join-Path $root "fake-provider.mjs"
$fakeCommand = Join-Path $root "fake-provider.cmd"
$fakePowerShellCommand = Join-Path $root "fake-provider.ps1"
$copilotRoot = Join-Path $root "copilot"
$claudeRoot = Join-Path $root "claude"
$codexRoot = Join-Path $root "codex"
$copilotHome = Join-Path $root "copilot-home"
$claudeConfig = Join-Path $root "claude-config"
$mailboxScripts = Join-Path $root "mailbox-scripts"
$childPidsPath = Join-Path $root "child-pids.txt"
$serverCapturePath = Join-Path $root "codex-server.json"
$watcherCapturePath = Join-Path $root "codex-watcher.json"

$savedEnvironment = @{
    AGENT_STACK_INVOCATION = $env:AGENT_STACK_INVOCATION
    REMOTE_AGENT_STACK_WINDOWS_CONFIG = $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG
    FAKE_AGENT_CAPTURE = $env:FAKE_AGENT_CAPTURE
    FAKE_AGENT_EXIT = $env:FAKE_AGENT_EXIT
    FAKE_AGENT_READY = $env:FAKE_AGENT_READY
    FAKE_AGENT_RELEASE = $env:FAKE_AGENT_RELEASE
    FAKE_AGENT_CHILD_PIDS = $env:FAKE_AGENT_CHILD_PIDS
    FAKE_CODEX_SERVER_CAPTURE = $env:FAKE_CODEX_SERVER_CAPTURE
    FAKE_CODEX_WATCHER_CAPTURE = $env:FAKE_CODEX_WATCHER_CAPTURE
    FAKE_CODEX_SERVER_EXIT = $env:FAKE_CODEX_SERVER_EXIT
    FAKE_CODEX_SERVER_LIFETIME_MS = $env:FAKE_CODEX_SERVER_LIFETIME_MS
    FAKE_CODEX_WATCHER_EXIT = $env:FAKE_CODEX_WATCHER_EXIT
    COPILOT_HOME = $env:COPILOT_HOME
    CLAUDE_CONFIG_DIR = $env:CLAUDE_CONFIG_DIR
    MAILBOX_SCRIPTS_DIR = $env:MAILBOX_SCRIPTS_DIR
}
$env:MAILBOX_SCRIPTS_DIR = $null

try {
    New-Item -ItemType Directory -Path (
        $root,
        $copilotRoot,
        $claudeRoot,
        $codexRoot,
        $copilotHome,
        $claudeConfig,
        $mailboxScripts
    ) -Force | Out-Null
    Set-Content -LiteralPath (
        Join-Path $mailboxScripts "claude-mailbox-hook.mjs"
    ) -Value "// test hook"
    Set-Content -LiteralPath (
        Join-Path $mailboxScripts "mailbox.mjs"
    ) -Value "// test mailbox CLI"
    Set-Content -LiteralPath (
        Join-Path $mailboxScripts "codex-mailbox-watcher.mjs"
    ) -Encoding utf8 -Value @'
import { appendFileSync, writeFileSync } from "node:fs";
appendFileSync(process.env.FAKE_AGENT_CHILD_PIDS, `${process.pid}\n`);
if (Number(process.env.FAKE_CODEX_WATCHER_EXIT ?? "0")) {
  console.error("synthetic watcher startup failure");
  process.exit(Number(process.env.FAKE_CODEX_WATCHER_EXIT));
}
writeFileSync(process.env.FAKE_CODEX_WATCHER_CAPTURE, JSON.stringify({
  endpoint: process.env.CODEX_APP_SERVER_ENDPOINT ?? null,
  tokenPresent: Boolean(process.env.CODEX_APP_SERVER_TOKEN),
  workspace: process.env.CODEX_WORKSPACE ?? null,
  launcherPid: process.env.CODEX_LAUNCHER_PID ?? null,
  allowAll: process.env.CODEX_ALLOW_ALL ?? null,
}));
setInterval(() => {}, 1_000);
'@

    Set-Content -LiteralPath $fakeScript -Encoding utf8 -Value @'
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import net from "node:net";
const args = process.argv.slice(2);
if (args[0] === "app-server") {
  appendFileSync(process.env.FAKE_AGENT_CHILD_PIDS, `${process.pid}\n`);
  if (Number(process.env.FAKE_CODEX_SERVER_EXIT ?? "0")) {
    console.error("synthetic app-server startup failure");
    process.exit(Number(process.env.FAKE_CODEX_SERVER_EXIT));
  }
  const endpoint = new URL(args[args.indexOf("--listen") + 1]);
  writeFileSync(process.env.FAKE_CODEX_SERVER_CAPTURE, JSON.stringify({
    argv: args,
    tokenPresent: Boolean(process.env.CODEX_APP_SERVER_TOKEN),
  }));
  net.createServer((socket) => socket.destroy()).listen(
    Number(endpoint.port),
    endpoint.hostname,
  );
  const lifetime = Number(process.env.FAKE_CODEX_SERVER_LIFETIME_MS ?? "0");
  if (lifetime > 0) setTimeout(() => process.exit(12), lifetime);
  setInterval(() => {}, 1_000);
} else {
const settingsIndex = args.indexOf("--settings");
const capture = {
  argv: args,
  cwd: process.cwd(),
  launcherName: process.env.COPILOT_AGENT_NAME ?? null,
  launcherSessionId: process.env.COPILOT_AGENT_SESSION_ID ?? null,
  machine: process.env.COPILOT_AGENT_MACHINE ?? null,
  mailboxSelfAddress: process.env.MAILBOX_SELF_ADDRESS ?? null,
  mailboxScriptsDir: process.env.MAILBOX_SCRIPTS_DIR ?? null,
  claudeMailboxHook: process.env.CLAUDE_MAILBOX_HOOK ?? null,
  claudeSettings: settingsIndex >= 0
    ? JSON.parse(readFileSync(args[settingsIndex + 1], "utf8"))
    : null,
  codexRemoteTokenPresent: Boolean(process.env.CODEX_AGENT_STACK_REMOTE_TOKEN),
};
if (capture.codexRemoteTokenPresent) {
  appendFileSync(process.env.FAKE_AGENT_CHILD_PIDS, `${process.pid}\n`);
}
writeFileSync(process.env.FAKE_AGENT_CAPTURE, JSON.stringify(capture));
console.log("fake-provider-stdout");
if (process.env.FAKE_AGENT_READY) {
  writeFileSync(process.env.FAKE_AGENT_READY, "ready");
}
while (process.env.FAKE_AGENT_RELEASE && !existsSync(process.env.FAKE_AGENT_RELEASE)) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
}
process.exit(Number(process.env.FAKE_AGENT_EXIT ?? "0"));
}
'@
    Set-Content -LiteralPath $fakeCommand -Encoding ascii -Value @'
@echo off
node "%~dp0fake-provider.mjs" %*
'@
    Set-Content -LiteralPath $fakePowerShellCommand -Encoding utf8 -Value @'
& node (Join-Path $PSScriptRoot "fake-provider.mjs") @args
exit $LASTEXITCODE
'@

    $env:COPILOT_HOME = $copilotHome
    $env:CLAUDE_CONFIG_DIR = $claudeConfig
    Write-TestConfig $configPath $copilotRoot $claudeRoot $codexRoot $fakeCommand

    $exitCode = Invoke-Launcher @("--help")
    Assert-Equal $exitCode 0 "global help exit"
    Assert-True ((Get-Content $stdoutPath -Raw).Contains(
        "agent-stack <copilot|claude|codex> <name>"
    )) "global help content"

    $exitCode = Invoke-Launcher @("copilot")
    Assert-Equal $exitCode 2 "missing name exit"
    Assert-True (-not (Test-Path $capturePath)) "missing name launched child"

    $exitCode = Invoke-Launcher @("unknown", "alpha")
    Assert-Equal $exitCode 2 "unknown backend exit"

    $exitCode = Invoke-Launcher @("copilot", "Alpha")
    Assert-Equal $exitCode 2 "invalid name exit"

    $exitCode = Invoke-Launcher @("copilot", "hotel")
    Assert-Equal $exitCode 0 "Copilot fresh exit"
    $capture = Read-Capture
    $hotelId = "ab7c0c56-f5b8-5e16-9d9e-49808182c874"
    Assert-Equal @($capture.argv) @(
        "--session-id=$hotelId",
        "--name=hotel"
    ) "Copilot fresh arguments"
    Assert-Equal $capture.cwd (Join-Path $copilotRoot "agent-hotel") (
        "Copilot workspace"
    )
    Assert-Equal $capture.launcherName "hotel" "Copilot launcher name"
    Assert-Equal $capture.launcherSessionId $hotelId "Copilot session id"
    Assert-Equal $capture.machine "surface-pro" "Copilot machine"
    Assert-Equal $capture.mailboxSelfAddress "copilot:hotel" (
        "Copilot mailbox self address"
    )
    Assert-True ((Get-Content $stdoutPath -Raw).Contains(
        "fake-provider-stdout"
    )) "provider stdout was captured instead of reaching the caller"

    $metadata = Join-Path $copilotHome "session-state\$hotelId\workspace.yaml"
    New-Item -ItemType Directory -Path (Split-Path $metadata) -Force | Out-Null
    Set-Content -LiteralPath $metadata -Value "name: hotel"
    $exitCode = Invoke-Launcher @("copilot", "hotel")
    Assert-Equal $exitCode 0 "Copilot resume exit"
    Assert-Equal @((Read-Capture).argv) @("--session-id=$hotelId") (
        "Copilot resume arguments"
    )

    $aliasCapture = Join-Path $root "alias.json"
    $exitCode = Invoke-Launcher @("hotel") "copilot-agent" $configPath $aliasCapture
    Assert-Equal $exitCode 0 "owned Copilot alias exit"
    Assert-Equal @((Read-Capture $aliasCapture).argv) @("--session-id=$hotelId") (
        "owned Copilot alias arguments"
    )

    $exitCode = Invoke-Launcher @("claude", "a-b")
    Assert-Equal $exitCode 0 "Claude fresh exit"
    $capture = Read-Capture
    Assert-Equal @($capture.argv) @() "Claude fresh arguments"
    $claudeWorkspace = Join-Path $claudeRoot "agent-a-hb"
    Assert-Equal $capture.cwd $claudeWorkspace "Claude encoded workspace"
    Assert-Equal $capture.mailboxSelfAddress "claude:a-b" (
        "Claude mailbox self address"
    )

    foreach ($case in @(
        @{ Name = "a.b"; Leaf = "agent-a-db" },
        @{ Name = "a_b"; Leaf = "agent-a-ub" }
    )) {
        $exitCode = Invoke-Launcher @("claude", $case.Name)
        Assert-Equal $exitCode 0 "Claude punctuation launch"
        Assert-Equal (Read-Capture).cwd (Join-Path $claudeRoot $case.Leaf) (
            "Claude punctuation workspace $($case.Name)"
        )
    }

    $projectKey = [regex]::Replace($claudeWorkspace, "[^A-Za-z0-9]", "-")
    $projectDirectory = Join-Path $claudeConfig "projects\$projectKey"
    New-Item -ItemType Directory -Path $projectDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $projectDirectory "session.jsonl") -Value "{}"
    $exitCode = Invoke-Launcher @("claude", "a-b")
    Assert-Equal $exitCode 0 "Claude resume exit"
    Assert-Equal @((Read-Capture).argv) @("--continue") (
        "Claude resume arguments"
    )

    $exitCode = Invoke-Launcher @("codex", "alpha")
    Assert-Equal $exitCode 0 "Codex launch exit"
    $capture = Read-Capture
    $codexWorkspace = Join-Path $codexRoot "agent-alpha"
    Assert-Equal @($capture.argv) @(
        "resume",
        "--last",
        "--cd",
        $codexWorkspace
    ) "Codex arguments"
    Assert-Equal $capture.cwd $codexWorkspace "Codex workspace"
    Assert-Equal $capture.mailboxSelfAddress "codex:alpha" (
        "Codex mailbox self address"
    )
    Assert-True (-not (@($capture.argv) -contains "--all")) (
        "Codex used --all"
    )

    Write-TestConfig $configPath $copilotRoot $claudeRoot $codexRoot $fakeCommand `
        -AllowAll $true -MailboxIntegration $true
    $exitCode = Invoke-Launcher @("copilot", "mailbox")
    Assert-Equal $exitCode 0 "Copilot configured launch"
    $capture = Read-Capture
    Assert-True (@($capture.argv) -contains "--allow-all-tools") (
        "Copilot allow-all missing"
    )
    Assert-True (@($capture.argv) -contains "-i") "Copilot mailbox prompt missing"
    Assert-Equal $capture.mailboxScriptsDir $mailboxScripts (
        "Copilot mailbox scripts directory"
    )

    $exitCode = Invoke-Launcher @("claude", "allow")
    Assert-Equal $exitCode 0 "Claude allow launch"
    $capture = Read-Capture
    Assert-True (@($capture.argv) -contains "--dangerously-skip-permissions") (
        "Claude bypass missing"
    )
    Assert-Equal $capture.launcherName $null "Claude claimed mailbox identity"
    Assert-Equal $capture.claudeMailboxHook (
        Join-Path $mailboxScripts "claude-mailbox-hook.mjs"
    ) "Claude mailbox hook path"
    Assert-Equal $capture.mailboxScriptsDir $mailboxScripts (
        "Claude mailbox scripts directory"
    )
    $settingsIndex = [array]::IndexOf(@($capture.argv), "--settings")
    Assert-True ($settingsIndex -ge 0) "Claude mailbox settings missing"
    $settingsPath = $capture.argv[$settingsIndex + 1]
    Assert-Equal $capture.claudeSettings.hooks.SessionStart.Count 1 (
        "Claude SessionStart hook count"
    )
    Assert-True (
        $capture.claudeSettings.hooks.SessionStart[0].hooks[0].command.Contains(
            '$CLAUDE_MAILBOX_HOOK'
        )
    ) "Claude hook command does not use the inherited path"
    Assert-True (-not (Test-Path -LiteralPath $settingsPath)) (
        "Claude temporary mailbox settings were not removed"
    )

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $config.CODEX_BIN = $fakePowerShellCommand
    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8

    $exitCode = Invoke-Launcher @("codex", "allow")
    Assert-Equal $exitCode 0 "Codex allow launch"
    $capture = Read-Capture
    Assert-True (-not (@($capture.argv) -contains (
        "--dangerously-bypass-approvals-and-sandbox"
    ))) "Codex remote resume included an unsupported permission override"
    Assert-True ((Get-Content $stderrPath -Raw).Contains(
        "managed Codex applies ALLOW_ALL when the mailbox starts an idle turn"
    )) "Codex remote permission boundary warning missing"
    Assert-True (@($capture.argv) -contains "--remote") (
        "Codex remote endpoint missing"
    )
    Assert-True (@($capture.argv) -contains "--remote-auth-token-env") (
        "Codex remote token environment selector missing"
    )
    Assert-True $capture.codexRemoteTokenPresent (
        "Codex TUI did not receive the private token"
    )
    Assert-Equal $capture.mailboxScriptsDir $mailboxScripts (
        "Codex mailbox scripts directory"
    )
    $serverCapture = Get-Content -LiteralPath $serverCapturePath -Raw |
        ConvertFrom-Json
    Assert-True (-not [bool]$serverCapture.tokenPresent) (
        "Codex app-server received the raw token"
    )
    Assert-True (@($serverCapture.argv) -contains "--ws-token-sha256") (
        "Codex app-server token hash missing"
    )
    $watcherCapture = Get-Content -LiteralPath $watcherCapturePath -Raw |
        ConvertFrom-Json
    Assert-True ([bool]$watcherCapture.tokenPresent) (
        "Codex watcher did not receive the private token"
    )
    Assert-Equal $watcherCapture.workspace (
        Join-Path $codexRoot "agent-allow"
    ) (
        "Codex watcher workspace"
    )
    Assert-Equal $watcherCapture.allowAll "true" "Codex watcher allow-all policy"
    foreach ($childPid in Get-Content -LiteralPath $childPidsPath) {
        Assert-True ($null -eq (
            Get-Process -Id ([int]$childPid) -ErrorAction SilentlyContinue
        )) "Codex Job Object left child $childPid running"
    }

    $exitCode = Invoke-Launcher @("codex", "server-failure") `
        -FakeExit 0 -CodexServerExit 9
    Assert-Equal $exitCode 1 "Codex app-server startup failure exit"
    Assert-True ((Get-Content $stderrPath -Raw).Contains(
        "synthetic app-server startup failure"
    )) "Codex app-server diagnostic missing"

    $exitCode = Invoke-Launcher @("codex", "watcher-failure") `
        -FakeExit 0 -CodexWatcherExit 9
    Assert-Equal $exitCode 1 "Codex watcher startup failure exit"
    Assert-True ((Get-Content $stderrPath -Raw).Contains(
        "synthetic watcher startup failure"
    )) "Codex watcher diagnostic missing"

    $release = Join-Path $root "hold-tui"
    $exitCode = Invoke-Launcher @("codex", "runtime-server-failure") `
        -CodexServerLifetimeMs 1500 -FakeRelease $release
    Assert-Equal $exitCode 1 "Codex runtime app-server failure exit"
    Assert-True ((Get-Content $stderrPath -Raw).Contains(
        "Managed Codex app-server exited while the TUI was running"
    )) "Codex runtime app-server failure was not detected"
    foreach ($childPid in Get-Content -LiteralPath $childPidsPath) {
        Assert-True ($null -eq (
            Get-Process -Id ([int]$childPid) -ErrorAction SilentlyContinue
        )) "Codex runtime failure left child $childPid running"
    }

    $exitCode = Invoke-Launcher @("codex", "tui-failure") `
        -FakeExit 7
    Assert-Equal $exitCode 7 "managed Codex TUI exit propagation"

    $deathReady = Join-Path $root "codex-death-ready"
    $deathRelease = Join-Path $root "codex-death-release"
    $deathCapture = Join-Path $root "codex-death.json"
    Remove-Item $deathReady, $deathRelease, $deathCapture, $childPidsPath -Force `
        -ErrorAction SilentlyContinue
    $env:FAKE_AGENT_CAPTURE = $deathCapture
    $env:FAKE_AGENT_READY = $deathReady
    $env:FAKE_AGENT_RELEASE = $deathRelease
    $env:FAKE_AGENT_CHILD_PIDS = $childPidsPath
    $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG = $configPath
    $codexDeathLauncher = Start-Process -FilePath $pwsh -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $launcher,
        "codex", "job-death"
    ) -WindowStyle Hidden -PassThru
    try {
        for ($index = 0; $index -lt 200 -and -not (Test-Path $deathReady); $index++) {
            Start-Sleep -Milliseconds 50
        }
        Assert-True (Test-Path $deathReady) "Codex TUI did not start for parent-death test"
        for ($index = 0; $index -lt 100; $index++) {
            $deathChildren = @(
                Get-Content -LiteralPath $childPidsPath -ErrorAction SilentlyContinue |
                    Where-Object { $_ }
            )
            if ($deathChildren.Count -ge 3) { break }
            Start-Sleep -Milliseconds 50
        }
        Assert-True ($deathChildren.Count -ge 3) (
            "Codex managed children were not all observed"
        )
        Stop-Process -Id $codexDeathLauncher.Id -Force
        [void]$codexDeathLauncher.WaitForExit(5000)
        for ($index = 0; $index -lt 100; $index++) {
            $liveChildren = @(
                $deathChildren | Where-Object {
                    $null -ne (Get-Process -Id ([int]$_) -ErrorAction SilentlyContinue)
                }
            )
            if ($liveChildren.Count -eq 0) { break }
            Start-Sleep -Milliseconds 50
        }
        Assert-Equal @($liveChildren) @() (
            "Codex Job Object did not kill children after launcher death"
        )
    } finally {
        if (-not $codexDeathLauncher.HasExited) {
            Stop-Process -Id $codexDeathLauncher.Id -Force
        }
        foreach ($childPid in @($deathChildren | Where-Object { $_ })) {
            if (Get-Process -Id ([int]$childPid) -ErrorAction SilentlyContinue) {
                Stop-Process -Id ([int]$childPid) -Force
            }
        }
    }

    Write-TestConfig $configPath $copilotRoot $claudeRoot $codexRoot $fakeCommand `
        -Prefix "../escape"
    $exitCode = Invoke-Launcher @("claude", "alpha")
    Assert-Equal $exitCode 2 "unsafe prefix exit"
    Assert-True (-not (Test-Path $capturePath)) "unsafe prefix launched child"

    $overlongPrefix = "p" * 155
    Write-TestConfig $configPath $copilotRoot $claudeRoot $codexRoot $fakeCommand `
        -Prefix $overlongPrefix
    $exitCode = Invoke-Launcher @("claude", ("a-" * 50))
    Assert-Equal $exitCode 2 "overlong Claude leaf exit"
    Assert-True (-not (Test-Path $capturePath)) "overlong leaf launched child"

    Write-TestConfig $configPath $copilotRoot $claudeRoot $codexRoot $fakeCommand
    $exitCode = Invoke-Launcher @("codex", "alpha.")
    Assert-Equal $exitCode 2 "trailing-dot name exit"
    Assert-True (-not (Test-Path $capturePath)) "trailing-dot name launched child"

    Write-TestConfig $configPath $copilotRoot $claudeRoot $codexRoot $fakeCommand `
        -Prefix ""
    $exitCode = Invoke-Launcher @("codex", "con")
    Assert-Equal $exitCode 2 "reserved workspace name exit"
    Assert-True (-not (Test-Path $capturePath)) "reserved name launched child"

    Write-TestConfig $configPath $copilotRoot $claudeRoot $codexRoot $fakeCommand
    $env:FAKE_AGENT_EXIT = "7"
    $env:AGENT_STACK_INVOCATION = "agent-stack"
    $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG = $configPath
    $env:FAKE_AGENT_CAPTURE = $capturePath
    $env:FAKE_AGENT_READY = ""
    $env:FAKE_AGENT_RELEASE = ""
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File $launcher codex failure `
        1>$stdoutPath 2>$stderrPath
    Assert-Equal $LASTEXITCODE 7 "provider exit propagation"

    $ready = Join-Path $root "ready"
    $release = Join-Path $root "release"
    $firstCapture = Join-Path $root "first.json"
    $secondCapture = Join-Path $root "second.json"
    Remove-Item $ready, $release, $firstCapture, $secondCapture -Force `
        -ErrorAction SilentlyContinue
    $otherCopilotRoot = Join-Path $root "copilot-other"
    New-Item -ItemType Directory -Path $otherCopilotRoot -Force | Out-Null
    $otherConfig = Join-Path $root "config-other.json"
    Write-TestConfig $otherConfig $otherCopilotRoot $claudeRoot $codexRoot $fakeCommand

    $env:FAKE_AGENT_EXIT = "0"
    $env:FAKE_AGENT_CAPTURE = $firstCapture
    $env:FAKE_AGENT_READY = $ready
    $env:FAKE_AGENT_RELEASE = $release
    $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG = $configPath
    $first = Start-Process -FilePath $pwsh -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $launcher,
        "copilot", "lock"
    ) -WindowStyle Hidden -PassThru

    for ($index = 0; $index -lt 100 -and -not (Test-Path $ready); $index++) {
        Start-Sleep -Milliseconds 50
    }
    Assert-True (Test-Path $ready) "first launch did not acquire mutex"

    $env:FAKE_AGENT_CAPTURE = $secondCapture
    $env:FAKE_AGENT_READY = ""
    $env:FAKE_AGENT_RELEASE = ""
    $exitCode = Invoke-Launcher @("copilot", "lock") "agent-stack" $otherConfig `
        $secondCapture
    Assert-Equal $exitCode 1 "duplicate Copilot launch exit"
    Assert-True (-not (Test-Path $secondCapture)) (
        "duplicate Copilot launch started child"
    )
    Assert-True ((Get-Content $stderrPath -Raw).Contains(
        "already running in another terminal"
    )) "duplicate launch error"

    Set-Content -LiteralPath $release -Value "release"
    [void]$first.WaitForExit(5000)
    Assert-True $first.HasExited "first launch did not exit"

    "agent-windows tests passed"
} finally {
    foreach ($entry in $savedEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable(
            $entry.Key,
            $entry.Value,
            "Process"
        )
    }
    if (-not $env:AGENT_STACK_TEST_KEEP -and (Test-Path -LiteralPath $root)) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
