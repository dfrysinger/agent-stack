# Windows Agent Stack Evidence Packet

**Revision:** `windows-agent-stack-evidence-v1`

This packet records the user outcome, current product behavior, platform facts,
and boundaries before a Windows design is proposed. It intentionally contains
no proposed implementation.

## User outcome and authority

The durable decision record is
[`windows-agent-stack-decisions.json`](windows-agent-stack-decisions.json).
Its current top-level user statements are:

- "hi can you get my agent-stack working with codex and claude code on this
  machine?"
- "yes I want it working on windows fully, we already have copilot-agent
  scripts working on here right?"
- "get a design doc written and use development loop and unattended run to
  execute on the windows port of the agent-stack tools"

The end user wants the existing Agent Stack commands to run GitHub Copilot CLI,
Claude Code, and Codex CLI on this Windows computer. The work must continue
through implementation and observable proof, not stop after a proposal.

## Existing product contract

The current macOS product exposes:

```text
agent-stack copilot <name>
agent-stack claude <name>
agent-stack codex <name>
copilot-agent <name>
claude-agent <name>
codex-agent <name>
```

`bin/agent` keeps separate workspace roots for the three providers. It uses
Copilot's stable session identifier, Claude's project continuation, and Codex's
workspace history plus `resume --last`. The macOS wrapper also uses tmux to
keep a live TUI process attachable.

The command, installer, and deterministic test contracts are recorded in
[`agent-stack-command-design.md`](agent-stack-command-design.md).

## Existing Windows capability

The machine already has a working `copilot-agent.cmd` entry point. It delegates
to a PowerShell launcher supplied by the mailbox skill. That launcher:

- requires a lowercase mailbox-safe agent name and explicit machine label;
- maps `(machine, agent name)` to one deterministic Copilot session UUID;
- checks Copilot's local `workspace.yaml` to distinguish new from resume;
- prevents caller arguments from replacing launcher-owned identity;
- launches Copilot with the exact session ID;
- adds an initial `name@machine` mailbox prompt for the default open mode.

The detailed identity contract is recorded in
`C:\Users\dfrysinger\code\skills\design\windows-agent-session-naming.md`.

## Current machine facts

- Operating system: Windows.
- Stable mailbox machine route: `surface-pro`.
- GitHub Copilot CLI is installed and callable as `copilot`.
- Claude Code 2.1.302 and Codex CLI 0.166.0 are installed through WinGet.
- WinGet currently exposes `Anthropic.ClaudeCode` and `OpenAI.Codex`.
- PowerShell 7 is installed.
- The reviewed candidate is installed under `%USERPROFILE%\bin`; the existing
  compatible `copilot-agent.cmd` remains byte-for-byte unchanged.
- Claude and Codex are not authenticated. Their installed launch paths reach
  the real provider binaries, but authenticated conversation/resume proof
  requires user-controlled protected login in an interactive terminal.
- No WSL distribution or native tmux service was found during the initial
  investigation.
- The machine uses an enterprise-managed npm registry, so a public global npm
  install is not a reliable installation path.

## Boundaries

- Preserve the existing command names and provider separation.
- Preserve the current Windows Copilot session identity and mailbox address
  behavior.
- Use each provider's supported session storage and resume behavior; do not
  force Claude or Codex into Copilot's UUID layout.
- Do not require WSL, a Unix compatibility layer, or macOS-only terminal
  behavior.
- Do not inspect, copy, or automate protected account credentials. The user
  performs browser login, SSO, MFA, password entry, or other protected
  authentication.
- Do not change the existing macOS behavior while adding Windows support.
- Do not add unrelated Tailscale, Screen Sharing, Dreaming, or agent-help work.

## Known failure modes to cover

- Unsupported backend, invalid name, missing name, and extra arguments.
- Missing provider executable or missing workspace root.
- A provider launch receiving identity flags owned by the wrapper.
- The same agent name crossing provider workspace or session namespaces.
- Fresh launch being mistaken for resume, or resume selecting another
  workspace's conversation.
- Installation overwriting a foreign command.
- A launch reporting success before the provider TUI actually starts.
- Mailbox initialization using a name or machine route different from the
  launcher identity.

## Claude Code native Windows contract

Official Anthropic documentation and the current WinGet manifest establish:

- `winget install Anthropic.ClaudeCode` is supported and installs the `claude`
  command. Anthropic's native PowerShell installer is also supported.
- `claude --continue` resumes the most recent session in the current directory.
- When no eligible session exists, `claude --continue` prints
  `No conversation found to continue` and exits; it does not create a fresh
  session. The launcher therefore needs the bounded Boolean project-history
  hint defined by the design.
- `claude --resume <session-id-or-name>` selects an explicit session, but the
  child process working directory still determines the active project context.
- There is no documented top-level working-directory flag. The launcher must
  start the process with its working directory set to the named workspace.
- `--dangerously-skip-permissions` is the current bypass flag. Native Windows
  does not provide Claude Code's built-in sandbox, so the bypass remains an
  explicit owner choice rather than a default required by this port.
- User state and transcripts remain under `%USERPROFILE%\.claude` unless
  `CLAUDE_CONFIG_DIR` relocates them. Transcript JSONL is internal and
  version-unstable; the launcher may use file existence only as a conservative
  continuation hint, not parse transcript contents as a public schema.
- Claude documents its project-key encoder: replace every non-alphanumeric
  character in the fully resolved working-directory path with `-`. This gives
  the Windows launcher a bounded Boolean project-history check without reading
  transcript contents.
- The native executable must be resolved from `PATH`; WinGet does not promise a
  stable physical install path.
- Claude can create and resume an explicit UUID with `--session-id` and
  `--resume`, but that would pin the Windows agent to one conversation rather
  than the current workspace's latest conversation after user-driven rotation.
  `--name` is not unique. The port keeps the established Agent Stack
  workspace-continuation behavior instead of treating a display name as an
  ownership key.

Sources:

- <https://code.claude.com/docs/en/setup>
- <https://code.claude.com/docs/en/cli-reference>
- <https://code.claude.com/docs/en/sessions>
- <https://code.claude.com/docs/en/claude-directory>
- <https://github.com/microsoft/winget-pkgs/tree/master/manifests/a/Anthropic/ClaudeCode/2.1.302>

## Codex CLI native Windows contract

OpenAI documentation, current release artifacts, and the WinGet manifest
establish:

- OpenAI publishes a native PowerShell installer and native x64 and ARM64
  executables. The WinGet catalog exposes `OpenAI.Codex` and installs the
  `codex` command from official OpenAI release assets.
- `codex resume --last` selects the newest session associated with the current
  working directory. `--all` removes that directory filter.
- `--cd <directory>` or `-C <directory>` explicitly sets the working directory.
  The launcher can also start the child process in the named workspace. It
  must not add `--all`, because that would allow one named workspace to resume
  another workspace's session.
- `--dangerously-bypass-approvals-and-sandbox` is the current full-bypass flag.
  It remains an explicit owner setting.
- `CODEX_HOME` defaults to `%USERPROFILE%\.codex`; sessions remain under its
  `sessions` directory. The session file layout is not a stable integration
  API, so the launcher should ask Codex to resume rather than parse its files.
- Current Codex TUI source at commit
  `fbf5f0d3a716d08c254d3e4941d5b12eaff5afe7` handles
  `resume --last` with no matching target by selecting
  `SessionSelection::StartFresh`. One provider command therefore supplies
  create-or-resume behavior without an Agent Stack state scan.
- Native Windows support does not require WSL. Sandbox capabilities vary by
  Windows version and enterprise policy; this port must not claim that a
  successful CLI launch proves a particular sandbox mode is active.

WinGet is a Microsoft community-catalog distribution of official OpenAI
binaries, not a currently documented OpenAI installation procedure. It is an
acceptable machine setup path here because the package source and executable
are inspectable; the launcher itself resolves `codex` from `PATH` and is not
coupled to WinGet.

Sources:

- <https://learn.chatgpt.com/docs/codex/cli>
- <https://learn.chatgpt.com/docs/cli/reference#codex-resume>
- <https://learn.chatgpt.com/docs/config-file/config-reference>
- <https://learn.chatgpt.com/docs/windows/windows-sandbox>
- <https://github.com/openai/codex/releases/tag/rust-v0.166.0>
- <https://github.com/microsoft/winget-pkgs/blob/master/manifests/o/OpenAI/Codex/0.166.0/OpenAI.Codex.installer.yaml>
- <https://github.com/openai/codex/blob/fbf5f0d3a716d08c254d3e4941d5b12eaff5afe7/codex-rs/tui/src/lib.rs>

## Windows cross-session mutex contract

Microsoft documents that Windows has one named-kernel-object namespace per
client session plus a global namespace. A client process opts into the global
namespace by prepending the case-sensitive `Global\` prefix. Microsoft
explicitly identifies a mutex used to detect one application instance across
all sessions as a use case for this namespace.

The reviewed launcher creates `Global\dfrysinger-agent-stack-v1-<hash>`.
Deterministic tests cover exact conflicting-resource keys, and a real installed
Codex launch held that production mutex while a second installed launch was
refused without starting another child.

Source:

- <https://learn.microsoft.com/en-us/windows/win32/termserv/kernel-object-namespaces>

## Closed evidence questions

Both missing providers have native Windows executables and working-directory
scoped continuation commands. A shared session registry is not required.

The user did not answer whether Windows must keep a live TUI process running
after its terminal closes. The selected native-launcher direction treats
durable conversation resume as the current supported outcome and records live
process persistence as a separate unresolved product decision. The independent
challenge must test whether that boundary still satisfies the user's request
for a full Windows port.
