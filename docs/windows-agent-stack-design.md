# Native Windows Agent Stack

## Status

**Proposal revision:** `windows-agent-stack-design-v4`
**Lane:** Systemic
**Evidence packet:** [`windows-agent-stack-evidence-v1`](windows-agent-stack-evidence.md)
**Decision record:** [`windows-agent-stack-decisions-v1`](windows-agent-stack-decisions.json)
**Independent challenge:** [`windows-agent-stack-constraint-challenge.md`](windows-agent-stack-constraint-challenge.md)

This work order adds a native Windows path to the existing Agent Stack product.
It does not replace or redesign the macOS path.

## Objective

Make the existing `agent-stack`, `copilot-agent`, `claude-agent`, and
`codex-agent` commands launch and resume isolated named provider sessions
natively on Windows, while preserving the working Windows Copilot identity and
mailbox contract.

## Non-goals

- Do not add a Windows terminal multiplexer, process supervisor, resident
  daemon, process registry, named-pipe protocol, or live-TUI reattachment.
  Closing the terminal ends the provider process; the next launch resumes the
  durable provider conversation.
- Do not require WSL, tmux, Cygwin, MSYS, Git Bash, or another Unix
  compatibility layer at runtime.
- Do not change `bin/agent`, `install.sh`, `uninstall.sh`, tmux behavior,
  Tailscale, Screen Sharing, Dreaming, or agent-help on macOS.
- Do not force Claude or Codex into Copilot's deterministic UUID or session
  directory layout.
- Do not define a shared cross-provider session schema or parse more provider
  state than is needed to choose fresh versus resume.
- Do not install provider CLIs as part of the Agent Stack product installer.
  Machine setup may install them separately through supported Windows channels.
- Do not inspect, copy, store, or automate account passwords, browser login,
  SSO, MFA, device codes, or other protected authentication.
- Do not add Claude or Codex mailbox initialization or immediate terminal
  injection on Windows. Portable manual mailbox commands remain available when
  the skills are installed, but automatic identity and wakeup require separate
  provider evidence.

## User result

From PowerShell or `cmd.exe`, the user can run:

```text
agent-stack copilot alpha
agent-stack claude alpha
agent-stack codex alpha
copilot-agent alpha
claude-agent alpha
codex-agent alpha
```

The canonical command and Agent Stack-owned aliases open the selected provider
in that provider's `agent-alpha` workspace. Repeating the command after the
process exits resumes the correct durable conversation when provider history
exists. The same agent name can be used for all three providers without
crossing workspaces or provider state.

On this machine, `copilot-agent alpha` remains the separately owned mailbox
compatibility command the user already relies on. It preserves deterministic
Copilot identity but keeps its existing caller working directory, default
allow-all, mailbox prompt, and extended argument behavior. It is not claimed
as an Agent Stack-owned equivalent alias.

The Windows port does not promise that the original process survives terminal
closure. The independent scope challenge found no direct user requirement for
that mechanism, and provider-owned durable resume satisfies the supported
caller without adding a second session manager.

## Caller and authority

The trusted caller is deterministic Agent Stack PowerShell code invoked by the
local computer owner. It validates the provider, agent name, configuration, and
launcher-owned arguments before starting an installed provider CLI.

The provider CLI and model are not trusted to change Agent Stack's provider,
agent name, workspace, mailbox address, or Copilot session ID. They may act
inside the permissions the owner deliberately grants. No external policy in the
current evidence forbids the owner from selecting provider bypass flags.

Protected authentication remains outside model and launcher authority. The
user performs login and any protected account interaction directly with the
provider.

## Constraint provenance

| Constraint | Provenance | Protects | Revisit condition |
| --- | --- | --- | --- |
| The public commands and three provider names remain unchanged. | Existing Agent Stack command contract and direct user request for the existing tools. | Scripts and user habits do not split into a Windows-only product. | Revisit only through a separate command-contract change. |
| Windows uses native PowerShell and `.cmd` entry points. | Direct user request for full Windows support; no WSL distribution is installed. | The supported path works from normal PowerShell and `cmd.exe`. | Revisit if the user explicitly selects WSL as a separate supported platform. |
| Each provider has a separate workspace root. | Existing product behavior and resume semantics that select by current directory. | The same agent name cannot resume another provider's conversation. | Revisit only if all providers expose a stronger shared identity contract. |
| Copilot keeps the existing `(machine, name)` deterministic UUID algorithm. | Working Windows launcher and reviewed Windows Copilot identity design. | Existing named Copilot sessions and mailbox routing remain stable. | Revisit only through the Copilot identity design's migration gate. |
| Claude uses its current workspace as the project and `--continue` only when project history exists. | Official Claude CLI contract and documented project encoder: replace every non-alphanumeric path character with `-`. | Fresh workspaces do not fail by requesting a nonexistent session; existing workspaces resume locally. | Revisit if Claude changes project state location or encoder. |
| Codex always uses `resume --last --cd <workspace>`. | Official cwd filter plus current Codex TUI source, where a missing `--last` target selects `StartFresh`. | One provider-owned command resumes when history exists and starts fresh when it does not, without Agent Stack parsing session files. | Revisit if a supported Codex release removes this create-or-resume behavior. |
| Provider executables are resolved from `PATH` or explicit `*_BIN` config. | WinGet and native installers do not promise one common physical path. | Upgrades and alternate supported installers keep working. | Revisit only if a provider publishes a stable discovery API. |
| Existing macOS shell files are unchanged. | The user's requested scope is the Windows port, and macOS behavior already has tests and users. | Windows work cannot regress the existing host. | Revisit only if a shared source extraction is separately justified and reviewed. |
| Authentication is interactive and user-controlled. | Explicit user autonomy boundary and protected-input policy. | Credentials are not exposed to launcher or model-controlled automation. | Revisit only for synthetic isolated test accounts or a provider-supported non-secret test mode. |
| Live-process persistence is excluded. | Independent challenge found no direct requirement and no two conflicting writers or service callers. | The port avoids an unsupported supervisor and second state owner. | Revisit on an explicit same-process reattachment requirement or provider-native cross-provider facility. |
| Only one live Agent Stack-owned launcher may own one provider conversation at a time. | Existing macOS reattachment prevents duplicate processes; design review identified two ordinary Windows terminals as conflicting writers to the same provider conversation. | Prevents concurrent mutation of one conversation and duplicate Copilot mailbox watchers. | Revisit if every provider exposes safe authoritative multi-client attachment. |

No hard numeric capacity limit is introduced. Existing mailbox-safe name
limits remain: agent names are lowercase `[a-z0-9._-]`, start with an
alphanumeric character, and contain at most 100 characters; machine labels use
the same grammar with at most 128 characters.

## Reframe gate

Implementation stops and returns to this work order before adding another
component when any of these conditions becomes true:

- Claude or Codex cannot resume the intended conversation from an isolated
  working directory without a new Agent Stack-owned session registry.
- The Claude project-history hint selects another workspace's session or
  requires parsing transcript contents.
- Windows cannot launch the provider TUI as an attached child process from the
  required workspace.
- Preserving the existing Copilot UUID requires changing the versioned
  namespace or provider-owned session files.
- A correct install requires overwriting an unrecognized existing command.
- The user requires the same live TUI process to survive terminal closure.
- A named Windows mutex cannot reliably refuse a second launcher while
  releasing automatically after process death.

**Reframe status: `CLEAR`.** Official Claude documentation establishes the
Windows project encoder, and the launcher uses an injective physical workspace
leaf for Claude names. Current Codex TUI source proves `resume --last` selects
`StartFresh` when no cwd-matching session exists. A process-scoped named mutex
restores the existing one-live-launch invariant without a registry, daemon, or
live-process manager.

## Reuse contract

The Windows port reuses these established owners:

- GitHub Copilot CLI remains the owner of Copilot session files and exact
  session resume.
- The reviewed Windows Copilot launcher algorithm remains the owner of the
  deterministic `(machine, name)` UUID mapping.
- Claude Code remains the owner of Claude project sessions and continuation.
- Codex CLI remains the owner of Codex session selection after Agent Stack
  establishes the correct working directory.
- The existing Agent Stack command names, configuration keys, provider
  workspace separation, permission setting, and fresh-versus-resume intent
  remain the product contract.
- The mailbox skill remains the owner of mailbox storage, addresses, transport,
  and Copilot watcher behavior.

Windows needs new code because the existing multi-call wrapper, installer, and
command-link manager require Bash, tmux, Unix symbolic links, and macOS paths.
Those are not available in a normal native Windows shell.

The new code is one Windows launcher and small command shims, not a second
session manager. Provider state remains provider-owned.

## Files and ownership

The implementation adds:

- `bin/windows/agent-stack.ps1` — shared Windows argument, configuration,
  workspace, identity, resume, mailbox-initialization, and child-launch logic.
- `bin/windows/agent-stack.cmd` — canonical backend-first command shim.
- `bin/windows/copilot-agent.cmd` — Copilot alias shim.
- `bin/windows/claude-agent.cmd` — Claude alias shim.
- `bin/windows/codex-agent.cmd` — Codex alias shim.
- `scripts/manage-windows-command-links.ps1` — ownership-safe install,
  preflight, and uninstall of command shims.
- `install.ps1` — Windows user-level installer and configuration writer.
- `uninstall.ps1` — Windows removal of only Agent Stack-owned command shims,
  with an explicit optional Windows configuration purge.
- `scripts/agent-windows.test.ps1` — deterministic launcher tests.
- `scripts/manage-windows-command-links.test.ps1` — installer ownership tests.
- `scripts/agent-windows-live.ps1` — real native process and provider smoke
  acceptance.

The existing macOS files remain the owners of macOS behavior.

## Command contract

The canonical form remains:

```text
agent-stack <copilot|claude|codex> <name>
```

Each alias selects its provider:

```text
copilot-agent <name>
claude-agent <name>
codex-agent <name>
```

`-h` and `--help` work in the same positions as the existing command. Unknown
providers, unknown invocation names, missing names, extra arguments, names
starting with `-`, and names outside the mailbox-safe grammar print usage and
exit 2 before creating a workspace or child process.

The public Agent Stack command accepts no arbitrary provider arguments. This
keeps provider identity, workspace, and resume flags launcher-owned.

The existing mailbox-skill `copilot-agent.cmd` on this computer is an external
compatibility command, not an Agent Stack-owned alias. It has an extended
`new|resume|open` contract, different workspace behavior, default allow-all,
and a default mailbox prompt. The Windows installer recognizes approved exact
fingerprints and preserves it instead of claiming behavioral parity or
ownership. The canonical `agent-stack copilot <name>` path shares only its
versioned deterministic UUID contract. A fresh Agent Stack installation
receives the standard single-name alias contract.

## Configuration contract

Windows uses a separate data-only configuration path:

```text
%USERPROFILE%\.config\remote-agent-stack\config.windows.json
```

PowerShell reads it with `ConvertFrom-Json`. The file is never executed as
PowerShell or shell code. Unknown properties fail so a typo cannot silently
select a default. The macOS-generated `config` file remains a separate owner
and is never read or changed by the Windows installer.

Supported properties are:

```text
COPILOT_WORKSPACE_BASE
CLAUDE_WORKSPACE_BASE
CODEX_WORKSPACE_BASE
COPILOT_BIN
CLAUDE_BIN
CODEX_BIN
AGENT_DIR_PREFIX
ALLOW_ALL
MAILBOX_INTEGRATION
COPILOT_AGENT_MACHINE
```

Environment values override file values. The installer writes explicit
workspace roots and creates them. Its default roots are:

```text
%USERPROFILE%\agent-workspaces\copilot
%USERPROFILE%\agent-workspaces\claude
%USERPROFILE%\agent-workspaces\codex
```

`AGENT_DIR_PREFIX` defaults to `agent-`. `ALLOW_ALL` and
`MAILBOX_INTEGRATION` default to `false` for the shared Agent Stack launcher.
`COPILOT_AGENT_MACHINE` defaults from the process environment only when it is
present and valid; otherwise the installer requires and persists an explicit
machine label. The preserved external Copilot compatibility command keeps its
current open-mode defaults.

Every configured workspace root and explicit executable path must be absolute.
A workspace root that is a file, an invalid Boolean, a missing executable, or
a command name that cannot be resolved fails before child launch.

`AGENT_DIR_PREFIX` may contain only ASCII letters, digits, dot, underscore, and
hyphen, with no path separator. After provider-specific name encoding, the
launcher validates the actual workspace leaf is at most 255 characters before
creating a directory or acquiring a mutex. This applies to every configured
prefix, not only the default.

### Windows workspace names

Copilot and Codex use the existing physical leaf
`<AGENT_DIR_PREFIX><name>`.

Claude must avoid collisions in Claude's documented project encoder, which
replaces every non-alphanumeric path character with `-`. Its physical leaf
keeps ASCII letters and digits unchanged and uses a fixed two-character escape
for the complete current punctuation grammar:

```text
alpha   -> agent-alpha
a-b     -> agent-a-hb
a.b     -> agent-a-db
a_b     -> agent-a-ub
```

`-` maps to `-h`, `.` maps to `-d`, and `_` maps to `-u`. Encoding the hyphen
as well as dot and underscore keeps this mapping injective. A maximum-length
100-character name produces at most a 206-character leaf with the default
prefix, below Windows' 255-character component limit. Any configured prefix
that makes the actual leaf longer than 255 characters fails before side
effects. Expanding the public punctuation grammar reopens this design. The
logical agent and mailbox names remain unchanged.

## Single-live-launch contract

Before any provider child starts, every Agent Stack-owned command reads the
current Windows user SID and derives a versioned cross-session named mutex from
that SID and the provider's actual conflicting resource:

```text
Copilot: Global\dfrysinger-agent-stack-v1-<sha256(user-sid + NUL + "copilot" + NUL + session-uuid)>
Claude:  Global\dfrysinger-agent-stack-v1-<sha256(user-sid + NUL + "claude"  + NUL + normalized-workspace)>
Codex:   Global\dfrysinger-agent-stack-v1-<sha256(user-sid + NUL + "codex"   + NUL + normalized-workspace)>
```

It attempts a non-blocking acquisition. If another launcher holds the mutex,
the second command exits 1 and reports that the named provider is already
running in another terminal. It does not start or resume another child.

The launcher holds the mutex for the full attached child lifetime and releases
it in `finally`. Windows releases the abandoned mutex when a launcher process
dies, so no registry, cleanup daemon, or stale lock file is required. The
`Global\` namespace covers desktop, OpenSSH, and other Windows sessions for the
same user. Including the user SID prevents unrelated local users from sharing
an Agent Stack mutex identity.

The preserved external `copilot-agent.cmd` does not participate in this mutex
contract. Documentation and installer output state that it must not be run
concurrently with `agent-stack copilot <same-name>`. Its compatibility check
makes no single-live-launch claim.

## Provider adapters

### Copilot

The adapter:

1. requires `COPILOT_AGENT_MACHINE`;
2. validates machine and agent names;
3. computes the versioned deterministic UUID from:

   ```text
   dfrysinger-skills/windows-agent-session/v1\0<machine>\0<agent-name>
   ```

4. exports `COPILOT_AGENT_NAME` and `COPILOT_AGENT_SESSION_ID`;
5. checks
   `%COPILOT_HOME%\session-state\<uuid>\workspace.yaml`, with
   `%USERPROFILE%\.copilot` as the default home;
6. uses `--session-id=<uuid> --name=<name>` for a fresh session and only
   `--session-id=<uuid>` for resume;
7. starts the child in the named Copilot workspace;
8. when `ALLOW_ALL=true`, adds `--allow-all-tools`;
9. when `MAILBOX_INTEGRATION=true`, supplies the standard
   `Initialize as <name>@<machine>...READY_<NAME>` interactive prompt unless
   the compatibility launcher already owns that prompt.

The launcher never writes Copilot session files.

### Claude

The adapter starts `claude` in the named Claude workspace. It uses Claude's
documented project transcript root only as a Boolean continuation hint; it
does not parse transcript contents. The encoder replaces every non-alphanumeric
character in the fully resolved, injectively encoded workspace path with `-`.

- If readable project transcript history exists, add `--continue`.
- Otherwise start a fresh interactive session.
- When `ALLOW_ALL=true`, add `--dangerously-skip-permissions`.
- Do not add a mailbox prompt or claim automatic Windows mailbox ownership.

The project-path encoder is isolated in one helper and covered by official
Windows examples plus path fixtures, including `a-b`, `a.b`, and `a_b`. If
observed state does not match that encoder, the reframe gate opens;
implementation must not invent a registry.

### Codex

The adapter starts `codex resume --last --cd <workspace>` with the named Codex
workspace as the process working directory.

- Codex filters `--last` by the supplied current directory.
- Current Codex TUI source selects `StartFresh` when no matching target exists.
- Do not add `--all`.
- When `ALLOW_ALL=true`, add
  `--dangerously-bypass-approvals-and-sandbox`.
- Do not add a mailbox prompt or parse Codex session files.

Codex remains the sole authority that chooses resume or fresh. The behavior is
covered by a pinned source-level contract check and real native smoke proof.

## Mailbox behavior

Copilot inherits `COPILOT_AGENT_NAME`, `COPILOT_AGENT_MACHINE`, and its
deterministic launcher session ID. It retains the existing extension watcher
and SDK wakeup behavior.

Claude and Codex do not receive automatic Windows mailbox identity or launch
prompts in this port. If the mailbox skills are installed, the user or agent
may run portable mailbox commands manually with an explicit `--name`. The
documentation does not report immediate wakeup or automatic identity as
verified.

## Installation and ownership

`install.ps1` is user-level and requires no administrator rights by default.
It:

1. checks Windows and PowerShell compatibility;
2. asks the command manager to preflight the destination, defaulting to
   `%USERPROFILE%\bin`;
3. creates or validates the three workspace roots;
4. writes the non-executable configuration file;
5. installs managed `.cmd` shims that point to this checkout's shared
   PowerShell launcher;
6. adds the destination to the user's `PATH` only when requested and absent,
   and records that exact addition in
   `%USERPROFILE%\.config\remote-agent-stack\install-state.windows.json`;
7. reports missing provider CLIs with install guidance but does not fail
   installation for providers the user has not installed;
8. prints protected authentication steps separately.

Each managed shim contains an Agent Stack marker and exact checkout target.
Install may replace only a shim with that marker and target. Any other file or
link is foreign.

The existing `copilot-agent.cmd` is preserved only when its SHA-256 matches an
approved compatibility fingerprint recorded in the command manager. Any other
foreign canonical or alias path fails preflight before another command changes.

`uninstall.ps1` removes only shims whose marker and exact target prove
ownership. It preserves compatible and foreign commands. It removes the exact
user `PATH` entry only when the install-state receipt says this checkout added
it and no preserved command depends on that directory. An explicit purge may
remove only `config.windows.json` and `install-state.windows.json`.
Workspaces, provider state, macOS configuration, and authentication state are
never removed.

## End-to-end journey

Assume the user runs:

```text
agent-stack codex alpha
```

The canonical shim calls the shared PowerShell launcher and identifies Codex
as the provider. The launcher reads the non-executable configuration, validates
`alpha`, resolves the Codex executable, and creates or opens
`%USERPROFILE%\agent-workspaces\codex\agent-alpha`.

It starts `codex resume --last --cd <workspace>` as an attached child process.
Codex applies its current-directory filter. On the first launch it starts
fresh because no target exists; after Codex stores history, the same command
resumes Alpha's newest conversation. The user authenticates directly if Codex
asks. Codex cannot select Claude's workspace or another Codex agent through
`--all`, because the launcher never supplies that flag.

If the configured executable is missing, the launcher exits before opening a
TUI and names the missing key and supported installation command.

## Failure model

| Failure | Required behavior |
| --- | --- |
| Unsupported invocation, backend, name, or argument count | Usage on stderr, exit 2, no workspace or child |
| Invalid or executable configuration line | Name file and line, exit 2, execute nothing |
| Workspace root missing | Installer creates it; direct launch reports the exact configuration key |
| Workspace root is a file or relative path | Fail before child launch |
| Prefix contains unsafe characters or actual workspace leaf exceeds 255 characters | Fail before directory creation or mutex acquisition |
| Missing provider command | Name provider, configured command, and supported install path |
| Existing foreign command path | Installer fails preflight before changing any command |
| Compatible existing Copilot alias | Preserve it and install the remaining owned commands |
| Same Agent Stack-owned provider conversation already running | Refuse the second owned launch with exit 1 and start no child |
| External Copilot compatibility command overlaps canonical Copilot | Unsupported; installer and documentation warn not to run both for the same name |
| Copilot deterministic workspace exists | Resume exact UUID without `--name` |
| Copilot deterministic workspace absent | Create exact UUID with native `--name` |
| Claude project history absent | Start fresh without `--continue` |
| Claude project history present | Use `--continue` from exact workspace |
| Codex matching history absent | `resume --last --cd` starts fresh through provider behavior |
| Codex matching history present | The same command resumes with exact workspace and never `--all` |
| Child process cannot start | Propagate a nonzero failure and actionable executable/workspace detail |
| Provider exits nonzero | Return its exit code; do not convert it to success |
| Protected login required | Leave the real provider prompt to the user |
| Claude/Codex Windows mailbox automation requested | Report it as unsupported in this port; do not claim identity or wakeup |

## Hard invariants

1. A provider never reads or writes another provider's workspace root.
2. A named Copilot session keeps the existing deterministic UUID.
3. The launcher owns provider, workspace, resume flags, and identity flags.
4. Codex resume never uses `--all`.
5. Claude's Boolean history hint and Codex's own create-or-resume command leave
   provider state ownership with the provider.
6. Installation never overwrites an unrecognized command.
7. Authentication secrets never pass through Agent Stack configuration or
   prompts.
8. macOS behavior and tests remain unchanged.
9. At most one Agent Stack-owned Windows launcher process owns one provider
   conversation at a time. Copilot keys this invariant by session UUID;
   Claude and Codex key it by normalized workspace.

## Acceptance criteria

1. All four canonical command surfaces print correct Windows help and reject
   invalid input before side effects.
2. Canonical and Agent Stack-owned alias forms produce the same standard launch
   for each provider. The preserved external Copilot compatibility command is
   tested against its narrower deterministic-identity contract instead.
3. The same name produces three different provider workspaces. Valid
   punctuation variants and the maximum 100-character punctuation-heavy name
   produce distinct, Windows-valid Claude project keys. Every configured
   prefix is checked against the actual 255-character component limit.
4. Copilot new and resume invocations use the expected deterministic UUID and
   exact current launcher environment.
5. Claude starts fresh without history and uses `--continue` with matching
   project history.
6. Codex always uses `resume --last --cd <workspace>`, starts fresh without
   history, resumes with history, and never uses `--all`.
7. Agent Stack-owned commands add permission bypass flags only when
   `ALLOW_ALL=true`. The preserved external Copilot compatibility command keeps
   its documented default.
8. Copilot mailbox identity follows the existing contract; Claude and Codex
   make no automatic mailbox claim.
9. Installer and uninstaller mutate only Agent Stack-owned command shims,
   Windows-owned config/state, and an exactly receipted PATH entry; they
   preserve the external compatible Copilot command.
10. Claude Code and Codex CLI are installed and resolve in a new Windows shell.
11. A real fresh and resumed canonical or Agent Stack-owned provider run
    reaches the expected TUI or protected authentication screen from the exact
    named workspace. The external Copilot compatibility command receives a
    separate deterministic-identity smoke check.
12. Existing macOS deterministic tests remain green in their supported
    environment; Windows changes do not alter their source files.
13. A second concurrent Agent Stack-owned launch of the same provider
    conversation is refused while a different provider or name can launch
    independently. The refusal spans desktop and OpenSSH Windows sessions.
    Copilot remains refused across different configured workspace roots when
    its deterministic session UUID is the same.

## Check contract

| Check | Setup and transition | Pass signal | What failure proves |
| --- | --- | --- | --- |
| PowerShell launcher unit test | Isolated home, config, workspaces, fake provider commands, fresh and seeded provider state | Captured executable, cwd, environment, arguments, and exit code match every acceptance row | Dispatch, identity, resume, or error behavior differs from the contract |
| Copilot compatibility vectors | Reuse the known `surface-pro/hotel` UUID and launcher environment fixtures | UUID and new/resume argument lists match the reviewed launcher tests | The port would fork existing Copilot identity |
| External Copilot compatibility check | Approved installed wrapper fingerprint and a fake Copilot capture | Existing command remains untouched and keeps its known deterministic identity/default behavior; no mutex behavior is asserted | Installer silently replaced or misrepresented the user's working command |
| Windows command ownership test | Temporary bin directory with absent, owned, compatible Copilot, and foreign paths | Planned mutations and preserved paths exactly match | Installer can overwrite or remove a command it does not own |
| Configuration parser test | Valid JSON plus unknown, relative, malformed, executable-looking, unsafe-prefix, and over-limit-prefix values | Only known data is accepted; no text executes; invalid leaves fail before side effects | Config can silently drift, execute code, or create invalid workspace paths |
| Claude project-state fixture | Official Windows encoder examples, `a-b`/`a.b`/`a_b`, a 100-character punctuation-heavy name, maximum accepted prefix, and one over-limit prefix | Only exact matching workspace adds `--continue`; every accepted leaf is distinct and at most 255 characters; over-limit fails before side effects | Claude can cross named workspace boundaries or create an invalid path |
| Codex source contract | Pin and inspect the shipped source path where a missing `resume --last` target selects `StartFresh` | Expected branch exists for the tested release | The design's create-or-resume premise no longer holds |
| Duplicate-launch test | First fake child holds the provider identity mutex while a second command runs; Copilot uses two workspace roots with one UUID; one live case acquires from desktop and OpenSSH sessions | Second owned launch exits 1 with no child across sessions; different name/provider succeeds; external compatibility path is excluded | Removing tmux introduced concurrent writers, the namespace is session-local, or the mutex keys the wrong resource |
| Real CLI discovery | New PowerShell process after installation | `Get-Command claude,codex` and version commands succeed | Package installation is not usable by the launcher |
| Real protected-auth handoff | Fresh isolated named workspace and real provider executable | TUI or login screen is visible and stable in the correct cwd | Process creation alone does not prove a usable provider |
| Real resume journey | User-authenticated fresh conversation exits, then same named command runs again | Provider shows the prior conversation in the same named workspace | Fixtures did not prove actual provider continuation |
| macOS source guard | Git diff and existing shell tests | No macOS runtime file changed; existing tests pass where supported | Windows work regressed the established product |

The deterministic tests are written before or with the implementation and must
fail on a deliberate wrong provider, workspace, UUID, `--all`, or foreign-path
mutation.

## Migration and rollback

No provider session or workspace data is migrated.

On this machine, the installer preserves the current external compatible
`copilot-agent.cmd` and adds the canonical command plus missing Claude and
Codex aliases. The shared canonical Copilot adapter maps to the same UUIDs but
does not claim full alias parity.

Rollback is:

1. run `uninstall.ps1` from the exact checkout that installed the shims;
2. verify Agent Stack-owned shims are absent and the compatible Copilot alias
   remains;
3. leave configuration, workspaces, and provider session state in place;
4. uninstall Claude Code or Codex separately with WinGet only if the user
   explicitly wants the provider removed.

Rollback does not remove authentication state or conversations.

## Current implementation baton

**Phase:** protected-auth live-proof handoff
**Workspace:** `C:\Users\dfrysinger\code\agent-stack`
**Branch:** `feature/windows-agent-stack`
**Constraint gate:** revision v4 focused reconciliation is `CLEAR`
**Reframe status:** `CLEAR`
**Open revisit conditions:** none
**Unserviced challenge triggers:** none
**External writing owners:** none
**Review owners:** implementation Opus and Terra reviewers completed three bounded rounds; no material finding remains
**Research owners:** Claude and Codex native-contract agents completed read-only evidence

**Next action:** the user completes Claude and Codex protected login in a real
interactive terminal. Then rerun each named command to record authenticated
resume proof and perform the desktop-versus-OpenSSH mutex check.

## Design review record

The bounded dual design review completed in three rounds:

- Round 1 found the external Copilot alias contract mismatch, Claude project-key
  collisions, and the missing duplicate-launch contract.
- Round 2 closed those findings and found configurable-prefix overflow plus a
  session-local mutex gap.
- Round 3 verified the actual leaf preflight and per-user cross-session
  `Global\` mutex. Both reviewer families returned complete results with the
  design scope lens applied and no remaining finding.

**Design review gate:** `PASSED`

## Implementation review record

The bounded dual implementation review completed in three rounds:

- Round 1 found provider stdout capture, Windows trailing-dot workspace aliasing,
  install-state receipt loss, custom-install drift, prefix reset, and an
  unsupported Windows PowerShell fallback.
- Round 2 verified those fixes and found one legacy-owned shim uninstall gap.
- Round 3 verified exact-byte removal for both current and legacy owned shims.

Both reviewer families returned complete results. No in-scope material finding
remains.

**Implementation review gate:** `PASSED`

## Definition of Done: Native Windows Agent Stack

- The reviewed design and check contract have a current independent challenge
  gate that permits implementation.
- `agent-stack`, Claude and Codex aliases, and either the Agent Stack-owned or
  preserved compatible Copilot command are available in the user's Windows
  command path without overwriting foreign commands.
- Copilot, Claude Code, and Codex CLI launch from separate named workspaces
  through native Windows processes.
- Repeating each named launch resumes the intended durable provider
  conversation when history exists.
- A concurrent duplicate launch of the same provider and name is refused
  without affecting different providers or names.
- Copilot keeps the existing deterministic session UUID and mailbox identity.
- Copilot retains its documented mailbox identity; Claude and Codex make no
  unsupported automatic mailbox or immediate-wakeup claim.
- Invalid input, unsafe configuration, missing executables, malformed provider
  state, and child-process failure are explicit and covered by tests.
- Claude Code and Codex CLI are installed; any required real-account
  authentication is completed by the user.
- Focused deterministic tests, ownership tests, exact-candidate live proof,
  and bounded implementation review pass with no in-scope must-fix finding.
- Existing macOS behavior is unchanged.
- The final reviewed candidate is committed and pushed to the owned feature
  branch with the exact evidence recorded in this work order.
