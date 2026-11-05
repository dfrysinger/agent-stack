param(
    [Parameter(Mandatory = $true)]
    [string]$PipeName
)

$ErrorActionPreference = "Stop"
$pipe = [IO.Pipes.NamedPipeClientStream]::new(
    ".",
    $PipeName,
    [IO.Pipes.PipeDirection]::In
)
try {
    $pipe.Connect(5000)
    $reader = [IO.StreamReader]::new($pipe, [Text.UTF8Encoding]::new($false))
    try {
        $request = $reader.ReadLine() | ConvertFrom-Json
    } finally {
        $reader.Dispose()
    }
} finally {
    $pipe.Dispose()
}

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.UseShellExecute = $false
$providerArguments = @($request.arguments)
if ([IO.Path]::GetExtension([string]$request.filePath) -ieq ".ps1") {
    $startInfo.FileName = Join-Path $PSHOME "pwsh.exe"
    [void]$startInfo.ArgumentList.Add("-NoProfile")
    [void]$startInfo.ArgumentList.Add("-ExecutionPolicy")
    [void]$startInfo.ArgumentList.Add("Bypass")
    [void]$startInfo.ArgumentList.Add("-File")
    [void]$startInfo.ArgumentList.Add([string]$request.filePath)
} else {
    $startInfo.FileName = $request.filePath
}
$startInfo.WorkingDirectory = $request.workingDirectory
$startInfo.CreateNoWindow = [bool]$request.background
if ($request.background) {
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
}
foreach ($argument in $providerArguments) {
    [void]$startInfo.ArgumentList.Add([string]$argument)
}
foreach ($entry in $request.environment.PSObject.Properties) {
    $startInfo.Environment[$entry.Name] = [string]$entry.Value
}

$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw "Failed to start managed process: $($request.filePath)"
}
if ($request.background) {
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
}
$process.WaitForExit()
if ($request.background) {
    [Console]::Out.Write($stdout.GetAwaiter().GetResult())
    [Console]::Error.Write($stderr.GetAwaiter().GetResult())
}
exit $process.ExitCode
