@echo off
setlocal
set "AGENT_STACK_INVOCATION=codex-agent"
set "AGENT_STACK_WINDOWS_LAUNCHER=%~dp0agent-stack.ps1"
where pwsh >nul 2>&1
if %ERRORLEVEL% neq 0 (
  echo Agent Stack requires PowerShell 7 ^(pwsh^). 1>&2
  exit /b 1
)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%AGENT_STACK_WINDOWS_LAUNCHER%" %*
exit /b %ERRORLEVEL%
