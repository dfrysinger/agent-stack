$ErrorActionPreference = "Stop"

function Stop-AgentStack {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$ExitCode = 2
    )

    [Console]::Error.WriteLine($Message)
    exit $ExitCode
}

function Get-HomePath {
    $homePath = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::UserProfile
    )
    if ([string]::IsNullOrWhiteSpace($homePath)) {
        Stop-AgentStack "Unable to resolve the current Windows user profile." 1
    }
    return [IO.Path]::GetFullPath($homePath)
}

function Show-GlobalUsage {
    param([Parameter(Mandatory = $true)][string]$Invocation)

    @"
Usage: $Invocation <copilot|claude|codex> <name>
  Launch or resume a named agent session.

Examples:
  $Invocation copilot alpha
  $Invocation claude alpha
  $Invocation codex alpha

Options:
  -h, --help   Show this help and exit.
"@
}

function Show-BackendUsage {
    param(
        [Parameter(Mandatory = $true)][string]$Invocation,
        [Parameter(Mandatory = $true)][string]$Backend
    )

    $command = if ($Invocation -in @("agent-stack", "agent")) {
        "$Invocation $Backend"
    } else {
        $Invocation
    }

    @"
Usage: $command <name>
  Launch or resume a named $Backend agent session.

Options:
  -h, --help   Show this help and exit.
"@
}

function Get-Invocation {
    $invocation = $env:AGENT_STACK_INVOCATION
    if ([string]::IsNullOrWhiteSpace($invocation)) {
        return "agent-stack"
    }
    return [IO.Path]::GetFileNameWithoutExtension($invocation).ToLowerInvariant()
}

function Read-WindowsConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    $knownKeys = @(
        "COPILOT_WORKSPACE_BASE",
        "CLAUDE_WORKSPACE_BASE",
        "CODEX_WORKSPACE_BASE",
        "COPILOT_BIN",
        "CLAUDE_BIN",
        "CODEX_BIN",
        "AGENT_DIR_PREFIX",
        "ALLOW_ALL",
        "MAILBOX_INTEGRATION",
        "MAILBOX_SCRIPTS_DIR",
        "COPILOT_AGENT_MACHINE"
    )

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $values
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-AgentStack "Windows Agent Stack config must be a file: $Path"
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $config = $raw | ConvertFrom-Json
    } catch {
        Stop-AgentStack "Cannot parse Windows Agent Stack config '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $config) {
        return $values
    }
    foreach ($property in $config.PSObject.Properties) {
        if ($property.Name -notin $knownKeys) {
            Stop-AgentStack "Unknown Windows Agent Stack config property '$($property.Name)' in $Path."
        }
        $values[$property.Name] = $property.Value
    }
    return $values
}

function Get-Setting {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue = $null
    )

    $environmentValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($null -ne $environmentValue) {
        return $environmentValue
    }
    if ($Config.ContainsKey($Name)) {
        return $Config[$Name]
    }
    return $DefaultValue
}

function ConvertTo-BooleanSetting {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -is [bool]) {
        return [bool]$Value
    }
    if ($Value -is [string]) {
        if ($Value -ceq "true") {
            return $true
        }
        if ($Value -ceq "false") {
            return $false
        }
    }
    Stop-AgentStack "$Name must be true or false."
}

function Resolve-AbsoluteDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SettingName,
        [switch]$MustExist
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not [IO.Path]::IsPathFullyQualified($Path)) {
        Stop-AgentStack "$SettingName must be an absolute path."
    }

    $resolved = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        Stop-AgentStack "$SettingName must be a directory path."
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        Stop-AgentStack "$SettingName is not available: $resolved" 1
    }
    return $resolved
}

function Resolve-AgentExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$SettingName,
        [Parameter(Mandatory = $true)][string]$Backend
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Stop-AgentStack "$SettingName cannot be empty."
    }

    $hasSeparator = $Value.IndexOf([IO.Path]::DirectorySeparatorChar) -ge 0 -or
        $Value.IndexOf([IO.Path]::AltDirectorySeparatorChar) -ge 0
    if ($hasSeparator -or [IO.Path]::IsPathFullyQualified($Value)) {
        if (-not [IO.Path]::IsPathFullyQualified($Value)) {
            Stop-AgentStack "$SettingName must be a command name or absolute path."
        }
        $path = [IO.Path]::GetFullPath($Value)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Stop-AgentStack "$Backend CLI ('$path') not found." 1
        }
        return $path
    }

    $command = Get-Command $Value -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        Stop-AgentStack "$Backend CLI ('$Value') not found in PATH." 1
    }
    return $command.Source
}

function Resolve-MailboxScript {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$HomePath,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $configuredRoot = [string](Get-Setting $Config "MAILBOX_SCRIPTS_DIR" $null)
    $roots = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($configuredRoot)) {
        if (-not [IO.Path]::IsPathFullyQualified($configuredRoot)) {
            Stop-AgentStack "MAILBOX_SCRIPTS_DIR must be an absolute path."
        }
        [void]$roots.Add([IO.Path]::GetFullPath($configuredRoot))
    }
    foreach ($root in @(
        (Join-Path $HomePath ".copilot\installed-plugins\_direct\dfrysinger--skills\skills\mailbox\scripts"),
        (Join-Path $HomePath "code\skills\skills\mailbox\scripts")
    )) {
        [void]$roots.Add($root)
    }

    foreach ($root in $roots) {
        $candidate = Join-Path $root $FileName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    Stop-AgentStack (
        "Mailbox integration requires '$FileName'. Upgrade or reinstall the " +
        "dfrysinger/skills plugin, or set MAILBOX_SCRIPTS_DIR to its scripts directory."
    ) 1
}

    function Initialize-JobObjectNativeMethods {
        if ($null -ne ("AgentStack.JobNativeMethods" -as [type])) {
            return
        }
        [void](Add-Type -TypeDefinition @'
    using System;
    using System.Diagnostics;
    using System.Runtime.InteropServices;
    using System.Text;

    namespace AgentStack {
        [StructLayout(LayoutKind.Sequential)]
        public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct IO_COUNTERS {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        public static class JobNativeMethods {
            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            public static extern IntPtr CreateJobObject(IntPtr attributes, string name);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool SetInformationJobObject(
                IntPtr job,
                int infoClass,
                IntPtr info,
                uint length
            );

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool AssignProcessToJobObject(
                IntPtr job,
                IntPtr process
            );

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool TerminateJobObject(
                IntPtr job,
                uint exitCode
            );

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool CloseHandle(IntPtr handle);
        }

        public sealed class ProcessOutputCollector {
            private readonly StringBuilder stderr = new StringBuilder();

            public void Attach(Process process) {
                process.OutputDataReceived += (_, __) => { };
                process.ErrorDataReceived += (_, args) => {
                    if (args.Data == null) return;
                    lock (stderr) {
                        stderr.AppendLine(args.Data);
                    }
                };
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }

            public string ErrorText() {
                lock (stderr) {
                    return stderr.ToString();
                }
            }
        }
    }
'@)
    }

    function New-KillOnCloseJob {
        Initialize-JobObjectNativeMethods
        $job = [AgentStack.JobNativeMethods]::CreateJobObject([IntPtr]::Zero, $null)
        if ($job -eq [IntPtr]::Zero) {
            throw "Cannot create Codex process Job Object: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
        $basic = New-Object AgentStack.JOBOBJECT_BASIC_LIMIT_INFORMATION
        $basic.LimitFlags = 0x00002000
        $information = New-Object AgentStack.JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        $information.BasicLimitInformation = $basic
        $size = [Runtime.InteropServices.Marshal]::SizeOf($information)
        $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($size)
        try {
            [Runtime.InteropServices.Marshal]::StructureToPtr(
                $information,
                $pointer,
                $false
            )
            if (-not [AgentStack.JobNativeMethods]::SetInformationJobObject(
                $job,
                9,
                $pointer,
                $size
            )) {
                throw "Cannot configure Codex process Job Object: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            }
        } catch {
            [void][AgentStack.JobNativeMethods]::CloseHandle($job)
            throw
        } finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($pointer)
        }
        return $job
    }

    function Close-JobObject {
        param([IntPtr]$Job)

        if ($Job -ne [IntPtr]::Zero) {
            [void][AgentStack.JobNativeMethods]::TerminateJobObject($Job, 1)
            return [AgentStack.JobNativeMethods]::CloseHandle($Job)
        }
        return $true
    }

    function Start-JobProcess {
        param(
            [Parameter(Mandatory = $true)][IntPtr]$Job,
            [Parameter(Mandatory = $true)][string]$FilePath,
            [Parameter(Mandatory = $true)][string[]]$Arguments,
            [Parameter(Mandatory = $true)][string]$WorkingDirectory,
            [hashtable]$Environment = @{},
            [switch]$Background
        )

        $bootstrapPath = Join-Path $PSScriptRoot "job-child.ps1"
        if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
            throw "Agent Stack job bootstrap is missing: $bootstrapPath"
        }
        $powershellExecutable = (Get-Process -Id $PID).Path
        $pipeName = "agent-stack-job-child-$PID-$([Guid]::NewGuid().ToString('N'))"
        $pipe = [IO.Pipes.NamedPipeServerStream]::new(
            $pipeName,
            [IO.Pipes.PipeDirection]::Out,
            1,
            [IO.Pipes.PipeTransmissionMode]::Byte,
            [IO.Pipes.PipeOptions]::CurrentUserOnly
        )
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.UseShellExecute = $false
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.CreateNoWindow = [bool]$Background
        $startInfo.FileName = $powershellExecutable
        [void]$startInfo.ArgumentList.Add("-NoProfile")
        [void]$startInfo.ArgumentList.Add("-ExecutionPolicy")
        [void]$startInfo.ArgumentList.Add("Bypass")
        [void]$startInfo.ArgumentList.Add("-File")
        [void]$startInfo.ArgumentList.Add($bootstrapPath)
        [void]$startInfo.ArgumentList.Add("-PipeName")
        [void]$startInfo.ArgumentList.Add($pipeName)
        if ($Background) {
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
        }

        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) {
                throw "Failed to start managed process bootstrap."
            }
            if (-not [AgentStack.JobNativeMethods]::AssignProcessToJobObject(
                $Job,
                $process.Handle
            )) {
                try {
                    $process.Kill($true)
                } catch {}
                throw "Cannot assign managed process bootstrap to Codex Job Object: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            }
            if ($Background) {
                $collector = New-Object AgentStack.ProcessOutputCollector
                $collector.Attach($process)
                $process | Add-Member -NotePropertyName AgentStackOutput -NotePropertyValue $collector
            }

            $wait = $pipe.WaitForConnectionAsync()
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            while (-not $wait.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
                if ($process.HasExited) {
                    throw "Managed process bootstrap exited before accepting launch data."
                }
                Start-Sleep -Milliseconds 25
            }
            if (-not $wait.IsCompleted) {
                throw "Timed out waiting for the managed process bootstrap."
            }
            $wait.GetAwaiter().GetResult()

            $launchEnvironment = @{}
            foreach ($entry in $Environment.GetEnumerator()) {
                $launchEnvironment[$entry.Key] = [string]$entry.Value
            }
            $request = @{
                filePath = $FilePath
                arguments = @($Arguments)
                workingDirectory = $WorkingDirectory
                environment = $launchEnvironment
                background = [bool]$Background
            } | ConvertTo-Json -Compress -Depth 4
            $writer = [IO.StreamWriter]::new(
                $pipe,
                [Text.UTF8Encoding]::new($false),
                1024,
                $true
            )
            try {
                $writer.WriteLine($request)
                $writer.Flush()
            } finally {
                $writer.Dispose()
            }
        } catch {
            if (-not $process.HasExited) {
                try {
                    $process.Kill($true)
                } catch {}
            }
            throw
        } finally {
            $pipe.Dispose()
        }
        return $process
    }

    function Get-AvailableLoopbackPort {
        $listener = [Net.Sockets.TcpListener]::new(
            [Net.IPAddress]::Loopback,
            0
        )
        try {
            $listener.Start()
            return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
        } finally {
            $listener.Stop()
        }
    }

    function Get-ManagedProcessError {
        param([Parameter(Mandatory = $true)][Diagnostics.Process]$Process)

        $detail = [string]$Process.AgentStackOutput.ErrorText()
        $detail = $detail.Trim()
        if ($detail.Length -gt 500) {
            return $detail.Substring($detail.Length - 500)
        }
        return $detail
    }

    function Test-ProcessDescendsFrom {
        param(
            [Parameter(Mandatory = $true)][int]$ProcessId,
            [Parameter(Mandatory = $true)][int]$AncestorId
        )

        $seen = New-Object Collections.Generic.HashSet[int]
        $current = $ProcessId
        while ($current -gt 0 -and $seen.Add($current)) {
            if ($current -eq $AncestorId) {
                return $true
            }
            $record = Get-CimInstance Win32_Process -Filter "ProcessId=$current" `
                -ErrorAction SilentlyContinue
            if ($null -eq $record) {
                return $false
            }
            $current = [int]$record.ParentProcessId
        }
        return $false
    }

    function Wait-ManagedLoopbackEndpoint {
        param(
            [Parameter(Mandatory = $true)][int]$Port,
            [Parameter(Mandatory = $true)][Diagnostics.Process]$Process
        )

        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($Process.HasExited) {
                $detail = Get-ManagedProcessError $Process
                throw (
                    "Codex app-server exited before accepting connections; " +
                    "upgrade Codex if this version lacks authenticated remote support." +
                    $(if ($detail) { " $detail" } else { "" })
                )
            }
            $listeners = @(
                Get-NetTCPConnection -State Listen -LocalPort $Port `
                    -ErrorAction SilentlyContinue
            )
            if ($listeners.Count -gt 0) {
                if ($listeners.Count -ne 1 -or -not (
                    Test-ProcessDescendsFrom ([int]$listeners[0].OwningProcess) $Process.Id
                )) {
                    throw "The selected Codex app-server port is owned by another process."
                }
                if ($Process.HasExited) {
                    throw "Codex app-server exited after binding its loopback endpoint."
                }
                return
            }
            Start-Sleep -Milliseconds 100
        }
        throw "Timed out waiting for the Codex app-server."
    }

    function Confirm-ManagedWatcherStarted {
        param([Parameter(Mandatory = $true)][Diagnostics.Process]$Process)

        $deadline = [DateTime]::UtcNow.AddMilliseconds(750)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($Process.HasExited) {
                $detail = Get-ManagedProcessError $Process
                throw (
                    "Codex mailbox watcher exited during startup." +
                    $(if ($detail) { " $detail" } else { "" })
                )
            }
            Start-Sleep -Milliseconds 50
        }
    }

    function New-CapabilityToken {
        $bytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        return [Convert]::ToHexString($bytes).ToLowerInvariant()
    }

    function Get-Sha256Hex {
        param([Parameter(Mandatory = $true)][string]$Value)

        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            return [Convert]::ToHexString(
                $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
            ).ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
    }

function Get-DeterministicUuid {
    param(
        [Parameter(Mandatory = $true)][string]$Machine,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $separator = [char]0
    $payload = "dfrysinger-skills/windows-agent-session/v1${separator}${Machine}${separator}${Name}"
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))
    } finally {
        $sha256.Dispose()
    }

    $uuidBytes = [byte[]]$hash[0..15]
    $uuidBytes[6] = ($uuidBytes[6] -band 0x0f) -bor 0x50
    $uuidBytes[8] = ($uuidBytes[8] -band 0x3f) -bor 0x80
    $hex = ([BitConverter]::ToString($uuidBytes) -replace "-", "").ToLowerInvariant()
    return @(
        $hex.Substring(0, 8)
        $hex.Substring(8, 4)
        $hex.Substring(12, 4)
        $hex.Substring(16, 4)
        $hex.Substring(20, 12)
    ) -join "-"
}

function ConvertTo-ClaudeAgentName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $builder = New-Object Text.StringBuilder
    foreach ($character in $Name.ToCharArray()) {
        switch ($character) {
            "-" { [void]$builder.Append("-h") }
            "." { [void]$builder.Append("-d") }
            "_" { [void]$builder.Append("-u") }
            default { [void]$builder.Append($character) }
        }
    }
    return $builder.ToString()
}

function Get-ClaudeProjectKey {
    param([Parameter(Mandatory = $true)][string]$Workspace)

    return ([regex]::Replace($Workspace, "[^A-Za-z0-9]", "-"))
}

function Test-ClaudeHistory {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$HomePath
    )

    $claudeConfig = $env:CLAUDE_CONFIG_DIR
    if ([string]::IsNullOrWhiteSpace($claudeConfig)) {
        $claudeConfig = Join-Path $HomePath ".claude"
    } elseif (-not [IO.Path]::IsPathFullyQualified($claudeConfig)) {
        Stop-AgentStack "CLAUDE_CONFIG_DIR must be an absolute path."
    }
    $projectDirectory = Join-Path ([IO.Path]::GetFullPath($claudeConfig)) (
        "projects\" + (Get-ClaudeProjectKey $Workspace)
    )
    if (-not (Test-Path -LiteralPath $projectDirectory -PathType Container)) {
        return $false
    }
    return $null -ne (
        Get-ChildItem -LiteralPath $projectDirectory -Filter "*.jsonl" -File -ErrorAction Stop |
            Select-Object -First 1
    )
}

function Get-MutexName {
    param(
        [Parameter(Mandatory = $true)][string]$Backend,
        [Parameter(Mandatory = $true)][string]$Resource
    )

    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $separator = [char]0
    $payload = "${sid}${separator}${Backend}${separator}${Resource}"
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))
    } finally {
        $sha256.Dispose()
    }
    $hex = ([BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    return "Global\dfrysinger-agent-stack-v1-$hex"
}

function Test-WindowsWorkspaceLeaf {
    param([Parameter(Mandatory = $true)][string]$Leaf)

    if ($Leaf.EndsWith(".", [StringComparison]::Ordinal) -or
        $Leaf.EndsWith(" ", [StringComparison]::Ordinal)) {
        return $false
    }
    $deviceStem = $Leaf.Split(".", 2)[0]
    return $deviceStem -notmatch "\A(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])\z"
}

$invocation = Get-Invocation
$backend = $null
$remainingArguments = [string[]]$args

switch ($invocation) {
    { $_ -in @("agent-stack", "agent") } {
        if ($remainingArguments.Count -eq 1 -and
            $remainingArguments[0] -in @("-h", "--help")) {
            Show-GlobalUsage $invocation
            exit 0
        }
        if ($remainingArguments.Count -lt 1 -or
            $remainingArguments[0] -notin @("copilot", "claude", "codex")) {
            [Console]::Error.WriteLine((Show-GlobalUsage $invocation))
            exit 2
        }
        $backend = $remainingArguments[0]
        $remainingArguments = [string[]]@($remainingArguments | Select-Object -Skip 1)
    }
    "copilot-agent" { $backend = "copilot" }
    "claude-agent" { $backend = "claude" }
    "codex-agent" { $backend = "codex" }
    default {
        Stop-AgentStack "Unsupported invocation name: $invocation"
    }
}

if ($remainingArguments.Count -eq 1 -and
    $remainingArguments[0] -in @("-h", "--help")) {
    Show-BackendUsage $invocation $backend
    exit 0
}
if ($remainingArguments.Count -ne 1) {
    [Console]::Error.WriteLine((Show-BackendUsage $invocation $backend))
    exit 2
}

$name = $remainingArguments[0]
if ($name -cnotmatch "\A[a-z0-9][a-z0-9._-]{0,99}\z") {
    Stop-AgentStack "Agent name must be a lowercase mailbox-safe name of 1-100 characters."
}

$homePath = Get-HomePath
$configPath = $env:REMOTE_AGENT_STACK_WINDOWS_CONFIG
if ([string]::IsNullOrWhiteSpace($configPath)) {
    $configPath = Join-Path $homePath ".config\remote-agent-stack\config.windows.json"
} elseif (-not [IO.Path]::IsPathFullyQualified($configPath)) {
    Stop-AgentStack "REMOTE_AGENT_STACK_WINDOWS_CONFIG must be an absolute path."
}
$config = Read-WindowsConfig ([IO.Path]::GetFullPath($configPath))

$prefix = [string](Get-Setting $config "AGENT_DIR_PREFIX" "agent-")
if ($prefix -cnotmatch "\A[A-Za-z0-9._-]*\z") {
    Stop-AgentStack "AGENT_DIR_PREFIX may contain only ASCII letters, digits, dot, underscore, and hyphen."
}

$allowAll = ConvertTo-BooleanSetting (Get-Setting $config "ALLOW_ALL" $false) "ALLOW_ALL"
$mailboxIntegration = ConvertTo-BooleanSetting (
    Get-Setting $config "MAILBOX_INTEGRATION" $false
) "MAILBOX_INTEGRATION"

$workspaceSetting = switch ($backend) {
    "copilot" { "COPILOT_WORKSPACE_BASE" }
    "claude" { "CLAUDE_WORKSPACE_BASE" }
    "codex" { "CODEX_WORKSPACE_BASE" }
}
$defaultWorkspace = Join-Path $homePath "agent-workspaces\$backend"
$workspaceBase = Resolve-AbsoluteDirectory (
    [string](Get-Setting $config $workspaceSetting $defaultWorkspace)
) $workspaceSetting -MustExist

$physicalName = if ($backend -eq "claude") {
    ConvertTo-ClaudeAgentName $name
} else {
    $name
}
$workspaceLeaf = "$prefix$physicalName"
if ($workspaceLeaf.Length -gt 255) {
    Stop-AgentStack "The configured agent workspace name exceeds Windows' 255-character component limit."
}
if (-not (Test-WindowsWorkspaceLeaf $workspaceLeaf)) {
    Stop-AgentStack "The configured agent workspace name is reserved or ambiguous on Windows."
}
$workspace = [IO.Path]::GetFullPath((Join-Path $workspaceBase $workspaceLeaf))

$binarySetting = switch ($backend) {
    "copilot" { "COPILOT_BIN" }
    "claude" { "CLAUDE_BIN" }
    "codex" { "CODEX_BIN" }
}
$defaultBinary = switch ($backend) {
    "copilot" { "copilot" }
    "claude" { "claude" }
    "codex" { "codex" }
}
$executable = Resolve-AgentExecutable (
    [string](Get-Setting $config $binarySetting $defaultBinary)
) $binarySetting $backend

$childArguments = New-Object System.Collections.Generic.List[string]
$mutexResource = $workspace.ToLowerInvariant()
$env:MAILBOX_SELF_ADDRESS = "${backend}:$name"
$temporaryFiles = New-Object System.Collections.Generic.List[string]

if ($backend -eq "copilot") {
    $machine = [string](Get-Setting $config "COPILOT_AGENT_MACHINE" $null)
    if ([string]::IsNullOrWhiteSpace($machine) -or
        $machine -cnotmatch "\A[a-z0-9][a-z0-9._-]{0,127}\z") {
        Stop-AgentStack "COPILOT_AGENT_MACHINE must be a lowercase mailbox-safe name of 1-128 characters."
    }

    $sessionId = Get-DeterministicUuid $machine $name
    $mutexResource = $sessionId
    $copilotHome = $env:COPILOT_HOME
    if ([string]::IsNullOrWhiteSpace($copilotHome)) {
        $copilotHome = Join-Path $homePath ".copilot"
    }
    $copilotHome = Resolve-AbsoluteDirectory $copilotHome "COPILOT_HOME"
    $workspaceMetadata = Join-Path $copilotHome "session-state\$sessionId\workspace.yaml"

    $env:COPILOT_AGENT_MACHINE = $machine
    $env:COPILOT_AGENT_NAME = $name
    $env:COPILOT_AGENT_SESSION_ID = $sessionId

    [void]$childArguments.Add("--session-id=$sessionId")
    if (-not (Test-Path -LiteralPath $workspaceMetadata -PathType Leaf)) {
        [void]$childArguments.Add("--name=$name")
    }
    if ($allowAll) {
        [void]$childArguments.Add("--allow-all-tools")
    }
    if ($mailboxIntegration) {
        $readyMarker = "READY_$($name.ToUpperInvariant())"
        [void]$childArguments.Add("-i")
        [void]$childArguments.Add(
            "Initialize as $name@$machine, then remain available for mailbox messages. Reply with exactly $readyMarker."
        )
    }
} elseif ($backend -eq "claude") {
    if ($mailboxIntegration) {
        $hookPath = Resolve-MailboxScript $config $homePath "claude-mailbox-hook.mjs"
        $nodeExecutable = Resolve-AgentExecutable "node" "Node.js" "Node.js"
        $env:CLAUDE_MAILBOX_HOOK = $hookPath
        $settingsPath = Join-Path ([IO.Path]::GetTempPath()) (
            "agent-stack-claude-settings-$PID-$([guid]::NewGuid().ToString('N')).json"
        )
        [ordered]@{
            hooks = [ordered]@{
                SessionStart = @(
                    [ordered]@{
                        hooks = @(
                            [ordered]@{
                                type = "command"
                                command = '"{0}" "$CLAUDE_MAILBOX_HOOK"' -f $nodeExecutable
                            }
                        )
                    }
                )
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath -Encoding utf8
        [void]$temporaryFiles.Add($settingsPath)
        [void]$childArguments.Add("--settings")
        [void]$childArguments.Add($settingsPath)
    }
    if (Test-ClaudeHistory $workspace $homePath) {
        [void]$childArguments.Add("--continue")
    }
    if ($allowAll) {
        [void]$childArguments.Add("--dangerously-skip-permissions")
    }
} else {
    [void]$childArguments.Add("resume")
    [void]$childArguments.Add("--last")
    [void]$childArguments.Add("--cd")
    [void]$childArguments.Add($workspace)
    if ($allowAll) {
        [void]$childArguments.Add("--dangerously-bypass-approvals-and-sandbox")
    }
}

$mutexName = Get-MutexName $backend $mutexResource
$mutex = $null
$ownsMutex = $false
[IntPtr]$codexJob = [IntPtr]::Zero
$exitCode = 1
try {
    try {
        $mutex = New-Object Threading.Mutex($false, $mutexName)
        try {
            $ownsMutex = $mutex.WaitOne(0)
        } catch [Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
    } catch {
        Stop-AgentStack "Cannot create the Windows launch guard '$mutexName': $($_.Exception.Message)" 1
    }

    if (-not $ownsMutex) {
        Stop-AgentStack "The $backend agent '$name' is already running in another terminal." 1
    }

    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    Push-Location -LiteralPath $workspace
    try {
        if ($backend -eq "codex" -and $mailboxIntegration) {
            $watcherPath = Resolve-MailboxScript $config $homePath "codex-mailbox-watcher.mjs"
            $nodeExecutable = Resolve-AgentExecutable "node" "Node.js" "Node.js"
            $codexJob = New-KillOnCloseJob
            $port = Get-AvailableLoopbackPort
            $endpoint = "ws://127.0.0.1:$port"
            $token = New-CapabilityToken
            $tokenHash = Get-Sha256Hex $token

            $server = Start-JobProcess $codexJob $executable @(
                "app-server",
                "--listen", $endpoint,
                "--ws-auth", "capability-token",
                "--ws-token-sha256", $tokenHash
            ) $workspace @{} -Background
            Wait-ManagedLoopbackEndpoint $port $server

            $managedEnvironment = @{
                CODEX_APP_SERVER_ENDPOINT = $endpoint
                CODEX_APP_SERVER_TOKEN = $token
                CODEX_WORKSPACE = $workspace
                CODEX_LAUNCHER_PID = [string]$PID
            }
            $watcher = Start-JobProcess $codexJob $nodeExecutable @(
                $watcherPath
            ) $workspace $managedEnvironment -Background
            Confirm-ManagedWatcherStarted $watcher

            $tuiEnvironment = @{
                CODEX_AGENT_STACK_REMOTE_TOKEN = $token
            }
            $tuiArguments = New-Object System.Collections.Generic.List[string]
            $remoteAdded = $false
            foreach ($argument in $childArguments) {
                if (
                    -not $remoteAdded -and
                    $argument -eq "--dangerously-bypass-approvals-and-sandbox"
                ) {
                    [void]$tuiArguments.Add("--remote")
                    [void]$tuiArguments.Add($endpoint)
                    [void]$tuiArguments.Add("--remote-auth-token-env")
                    [void]$tuiArguments.Add("CODEX_AGENT_STACK_REMOTE_TOKEN")
                    $remoteAdded = $true
                }
                [void]$tuiArguments.Add($argument)
            }
            if (-not $remoteAdded) {
                [void]$tuiArguments.Add("--remote")
                [void]$tuiArguments.Add($endpoint)
                [void]$tuiArguments.Add("--remote-auth-token-env")
                [void]$tuiArguments.Add("CODEX_AGENT_STACK_REMOTE_TOKEN")
            }
            $tui = Start-JobProcess $codexJob $executable (
                $tuiArguments.ToArray()
            ) $workspace $tuiEnvironment
            $tui.WaitForExit()
            $exitCode = $tui.ExitCode
        } else {
            & $executable @($childArguments.ToArray())
            $exitCode = $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }
} finally {
    if ($ownsMutex -and $null -ne $mutex) {
        $mutex.ReleaseMutex()
    }
    if ($null -ne $mutex) {
        $mutex.Dispose()
    }
    foreach ($path in $temporaryFiles) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    if (-not (Close-JobObject $codexJob)) {
        [Console]::Error.WriteLine(
            "Warning: could not close the Codex process Job Object."
        )
    }
}
exit $exitCode
