# Windows Agent Stack Constraint Challenge

## Pass 1: minimum design before proposal

**Evidence revision:** `windows-agent-stack-evidence-v1`
**Decision revision:** `windows-agent-stack-decisions-v1`
**Challenger:** fresh read-only `windows-scope-challenger`

### User job

Run the existing Agent Stack command family on this Windows machine with
GitHub Copilot CLI, Claude Code, and Codex CLI. Preserve named-agent identity
and resume the intended durable conversation after a provider exits.

The supported caller is the local Windows user invoking
`agent-stack <provider> <name>` or a provider-specific alias from PowerShell or
`cmd.exe`. No supported background-service, remote-control, or multi-writer
caller is established.

### Observable result

- The correct installed provider TUI starts in that provider's isolated
  workspace.
- Relaunch selects the same intended provider conversation through the
  provider's supported resume behavior.
- Copilot preserves its deterministic session UUID and mailbox identity.
- Provider names and state do not cross namespaces.
- Invalid input, missing executables or workspaces, identity-flag injection,
  unsafe installation, and startup failure are explicit errors.
- Authentication remains an interactive user action.

### Minimum design

1. Preserve the existing Windows Copilot launcher contract.
2. Add native `.cmd` and PowerShell entry points for the existing Agent Stack
   commands.
3. Give each provider a separate workspace root keyed by agent name.
4. Launch Claude and Codex as ordinary attached native Windows processes using
   their official state and resume mechanisms.
5. Keep conversation identity in provider-owned storage rather than process
   survival or a shared registry.
6. Install provider executables through supported Windows channels and refuse
   to overwrite foreign commands.
7. Prove argument ownership, workspace isolation, fresh-versus-resume
   selection, and actual provider startup with focused fixtures and native
   smoke checks.

No Windows process supervisor, registry, daemon, WSL installation, Unix
compatibility layer, or tmux equivalent is part of the minimum.

### Keep

| Item | Independent authority | Failure prevented |
| --- | --- | --- |
| Existing commands and provider separation | Existing public product contract | Windows diverges or one provider selects another provider's state |
| Existing Copilot identity and mailbox behavior | Working Windows compatibility boundary | Existing named Copilot agents resume under another UUID or address |
| Provider-native durable resume | User job and provider-state boundary | Relaunch starts a new or wrong conversation |
| Native Windows implementation | Direct user decision | The port depends on an unavailable compatibility environment |
| User-controlled authentication | Explicit credential boundary | Untrusted behavior gains access to protected credentials |
| Safe install and confirmed startup | Reachable failure model | Foreign commands are overwritten or startup is falsely reported |

No shared coordination is retained. The evidence identifies fewer than two
conflicting writers or callers, so concurrency, locking, registry, and daemon
machinery are unjustified.

### Remove

- Live TUI persistence after the launching terminal closes.
- A shared Windows process supervisor, process registry, or resident daemon.
- Cross-provider session metadata or a common session-ID format.
- WSL, tmux, or a Unix compatibility layer.
- Fixed Claude or Codex state paths or arguments before official evidence.
- Credential inspection, copying, storage, or automated protected login.

The macOS tmux mechanism proves the current macOS implementation. It does not
establish an independent Windows requirement to keep the same process alive.

### Unresolved

1. Claude's official native Windows install, workspace-state, continuation, and
   resume contract.
2. Codex's official native Windows install, workspace-history, and unambiguous
   resume contract.
3. A direct product requirement for live process persistence. Until such a
   requirement exists, it remains outside this port.

### Highest-leverage assumptions

1. "Fully on Windows" requires durable named-conversation resume, not survival
   of the original TUI process. Provider-native durable state is the simpler
   capability.
2. Provider-isolated workspaces and provider-owned state can resolve named
   agents without a shared registry. This must be revisited if a provider
   cannot resume the intended conversation from its assigned workspace.
3. Native executables can satisfy launch and resume without WSL or tmux. Exact
   provider details remain open until official evidence closes them.

### Authority and security

Deliberate owner grants are allowed. The owner may install and execute provider
CLIs and grant bounded filesystem, network, and authentication access. No
external policy fixing a broader permission ceiling is evidenced.

Protected authentication remains user-controlled. The protected assets are
account credentials and authenticated sessions. Provider or model behavior
must not inspect, copy, or automate those credentials. This control prevents
authority expansion by an untrusted actor; it does not restrict the owner's
approved interactive login.

### Pass-1 verdict

**Decision:** `NARROW`
**Gate status:** `PASS_WITH_SCOPE_RESTRICTIONS`

**Permitted scope:** native command surfaces, existing Copilot compatibility,
provider-isolated workspaces, official provider-native durable resume, safe
installation, explicit failures, and startup proof.

**Blocked scope:** process supervision, shared process registry or daemon,
live-TUI reattachment, WSL or tmux dependencies, shared provider session
schema, unverified provider details, and protected-credential automation.

**Smallest next step:** incorporate the official Claude Code and Codex native
Windows contracts, then write the design around attached native launch and
provider-owned durable resume.

## Pass 2: proposal review

**Reviewed proposal:** `windows-agent-stack-design-v1`

The original synchronous pass-1 agent could not accept a follow-up turn, so a
fresh read-only challenger consumed the persisted pass-1 record before seeing
the proposal.

**Decision:** `REFRAME`
**Gate status:** `PARTIAL`

The challenger kept native attached processes, separate workspaces, exact
Copilot identity, ownership-safe command installation, interactive
authentication, and the live-process non-goal. It blocked:

- parsing Codex JSONL metadata;
- an unproved Claude Windows project encoder;
- required Claude and Codex mailbox launch prompts;
- treating the preserved external `copilot-agent.cmd` as fully equivalent to
  the Agent Stack alias;
- reading and rewriting the macOS-generated configuration file;
- workspace or provider-state purge.

The required corrections were:

1. classify the existing Copilot command as external compatibility;
2. give Windows a separately owned data-only config;
3. persist the machine identity source;
4. establish Claude's encoder with native or official evidence;
5. replace Codex metadata parsing with provider-supported behavior;
6. remove unproved Claude and Codex mailbox automation;
7. define PATH and installer-state rollback;
8. replace schema fixtures with direct provider behavior checks.

## Focused reconciliation: proposal revision v2

**Gate status:** `CLEAR`

Revision v2 resolves every named blocker:

- the existing Copilot command is external compatibility, not claimed parity;
- Windows owns `config.windows.json` and the persisted machine label;
- Claude uses the official Boolean project encoder without transcript parsing;
- Codex owns create-or-resume through `resume --last --cd`;
- Claude and Codex mailbox automation is removed;
- install state records the exact PATH addition and rollback;
- purge is limited to Windows-owned config and install-state files.

**Permitted scope:** implement revision v2's launcher, shims, separate Windows
configuration, isolated workspaces, Copilot identity, Claude continuation hint,
Codex provider-owned create-or-resume, ownership-safe install and uninstall,
and focused checks.

**Blocked scope:** shared session registries, daemons, process supervision,
live-TUI reattachment, provider-state parsing, Claude or Codex automatic
mailbox identity or wakeup, protected-auth automation, overwriting unknown
commands, and deleting workspaces or provider state.

**Remaining required design edit:** none.

**Smallest next step:** run bounded dual design review against revision v2,
then begin implementation only if no verified blocker remains.

## Revision v3 coordination reconciliation

Round-1 dual review established two same-name Windows terminals as conflicting
writers and found Claude project-key collisions for valid punctuation names.
Revision v3 added a process-lifetime named mutex and an injective Claude
workspace leaf.

The first focused reconciliation returned `PARTIAL` and required:

- key the Copilot mutex by deterministic session UUID, not workspace;
- key Claude and Codex by normalized workspace;
- scope the mutex to Agent Stack-owned commands and make no claim for the
  preserved external Copilot launcher;
- replace generic `-hh` encoding with the bounded current-grammar mapping
  `-` to `-h`, `.` to `-d`, and `_` to `-u`;
- cover maximum-length Claude names, cross-root same-UUID Copilot launches,
  and the external command's explicit mutex exclusion.

The exact design now contains those corrections.

**Focused recheck gate:** `CLEAR`
**Decision:** `CONTINUE`

The recheck verified the provider-specific mutex identities, Agent Stack-owned
scope, explicit external compatibility exclusion, bounded injective Claude
mapping, 206-character maximum leaf, and all three required fixtures. No
unresolved item or further design edit remains.

**Smallest next step:** run round-2 dual design review limited to the three
round-1 findings and the revision-v3 correction delta.

## Revision v4 edge reconciliation

Round-2 dual review closed the three original findings and identified two
direct edge cases:

- a configured `AGENT_DIR_PREFIX` could make the actual workspace leaf exceed
  255 characters;
- a `Local\` mutex would not coordinate a desktop terminal with an OpenSSH
  terminal in another Windows session.

Revision v4 validates the actual provider-specific leaf before side effects and
uses a per-user `Global\` mutex keyed by user SID plus the provider's
conflicting resource.

**Focused gate:** `CLEAR`
**Decision:** `CONTINUE`

The checks are the smallest direct fixes. The SID is namespacing rather than an
authorization boundary. No ACL service, privilege manager, registry, lock
file, cleanup process, or broader security claim is added. The external
Copilot command remains outside the mutex guarantee.

**Smallest next step:** run resolution-only dual review limited to the two
round-2 findings and revision-v4 delta.

## Final proof-boundary reconciliation

The implementation and bounded dual review are complete. Two proposed release
checks remained dependent on protected credentials or elevated host policy:

- an authenticated Claude and Codex conversation followed by a real resume;
- a desktop-versus-OpenSSH launch using the same Windows account.

**Decision:** `NARROW`
**Focused gate:** `CLEAR`

The user's job is a native Windows port of the existing Agent Stack tools. The
supported caller is the local owner running the installed commands. The
observable result is correct native dispatch into isolated named workspaces,
with provider-owned login and durable resume available after the owner
authenticates.

### Keep

- Keep the one-live-launch mutex. Two ordinary Agent Stack-owned terminals are
  evidenced conflicting writers to one provider conversation. A real Codex
  child held the production mutex and a second installed launch was refused
  without starting another child.
- Keep the per-user `Global\` namespace. Microsoft documents that `Global\`
  named mutexes are visible across Windows client sessions and are the
  supported mechanism for one-instance behavior across sessions.
- Keep the provider-owned authentication and resume boundaries. The installed
  Claude and Codex commands reach stable real provider processes in the
  correct named launch path; official provider contracts and deterministic
  fixtures cover the exact continuation arguments and workspace selection.

### Remove

- Remove completed real-account login from the implementation Definition of
  Done. Password, browser login, SSO, MFA, and device authorization are
  deliberately user-controlled and do not change the reviewed launcher.
- Remove a credentialed desktop-versus-OpenSSH ceremony as the only admissible
  proof of the `Global\` namespace. It adds SSH credentials or elevation solely
  for verification, while the platform contract and live production mutex
  already establish the retained property.
- Remove an authenticated model conversation as the only admissible proof of
  Claude and Codex resume wiring. It measures account state and model access,
  not a different launcher code path.

### Unresolved

None for implementation or branch publication. The user may authenticate
Claude and Codex at any time to use those providers; that is normal product
operation, not deferred implementation scope.

Deliberate owner grants remain allowed. No evidenced external policy constrains
the owner from authenticating or selecting the reviewed permission flags.
The retained mutex governs conflicting owner-approved launches, not authority
expansion by an untrusted actor. No denied capability is recreated through an
indirect API or service.

**Smallest next step:** record the narrowed receipts, run final source-to-
installed-candidate checks, update the pushed branch, and close the unattended
run.
