Work from `docs/windows-agent-stack-design.md` in
`C:\Users\dfrysinger\code\agent-stack` on branch
`feature/windows-agent-stack`.

Read the charter at `docs/windows-agent-stack-autopilot.md` for standing rules
and the design's current implementation baton for state, evidence, and the next
safe action.

Outcome: the existing Agent Stack command family works natively on this Windows
machine for GitHub Copilot CLI, Claude Code, and Codex CLI. Each provider uses
an isolated named workspace and its supported durable resume behavior. Copilot
keeps the existing deterministic Windows identity. Installation and removal
preserve foreign commands and provider-owned state.

Follow the reviewed work order in order and keep its implementation baton
accurate. Use the charter's required process skills and push policy. Do not add
live-process supervision, WSL or tmux runtime dependencies, provider-state
parsing, Claude or Codex mailbox automation, protected-authentication
automation, macOS redesign, or unrelated Agent Stack features.

Finish only when every item in the "Definition of Done: Native Windows Agent
Stack" section is verifiably met. Do not substitute partial tests, code
inspection, or a plausible implementation for the exact-candidate deterministic
and live evidence named there.
