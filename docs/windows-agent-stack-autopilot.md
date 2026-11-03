# Native Windows Agent Stack Unattended Charter

Keep building against the reviewed work order at
`docs/windows-agent-stack-design.md` in
`C:\Users\dfrysinger\code\agent-stack` on branch
`feature/windows-agent-stack`. Follow the required process skills below.

If a reminder arrives during a user-directed edit to the design, evidence,
decision, challenge, or charter files, finish and persist that coherent edit
before reconciling against disk. Never overwrite newer state with an older
persisted copy.

If stuck, give a rubber-duck agent one concrete blocker and ask for one
distinguishing check or simpler alternative. Do not repeat the same brainstorm
without new evidence. Record a real stall in the design's implementation baton:
goal, expected next action, observed non-progress, first divergence, source
receipt, and recovery or missing predicate. Mark second-hand incidents
unverified until their owner's result supports them.

At run start, compaction or resumption, candidate movement, every phase
boundary, failure, ownership handoff, material user direction, and each
four-hour charter check while the Definition of Done is open, run
`/dfrysinger-skills:development-loop`'s critical-path audit. Rebuild ready work
and dependencies, mark the critical path, assign each substantial independent
ready scope to an isolated owner when delegation is safe, and execute cheap
direct work. Name the real dependency or exclusive gate for each unowned scope.
Keep one writer per checkout and one proof owner for the frozen candidate.

For every delegated agent, keep its stable assignment ID, exact scope, owned
paths, workspace or branch, routable agent ID, owed evidence, blockers, and
integration boundary in the implementation baton. Read the agent's explicit
result before reporting status or assigning successor work. A clean, dirty, or
changing worktree is artifact state, not worker state. If no current result
exists, record `unknown`, request status once through the known route, and
advance other ready work. Consume completed handoffs before inspecting or
integrating their artifacts. File-writing delegates require isolated
worktrees. Do not wait for an agent to push to main; consume its reviewed frozen
commit from its owned branch or worktree when dependencies and the integration
boundary are ready.

Batch coherent fixes before expensive builds and proof. Reuse unaffected
evidence only through the design's candidate-impact rules. Preserve one live
proof owner and one exact running candidate. Keep first model outcomes
immutable; separately named repeats may answer a different question.

Push reviewed and validated work to the owned
`feature/windows-agent-stack` branch when useful. Do not merge to `main`,
create a release, deploy, or mutate shared production resources without a
separate user grant.

Decide reversible questions autonomously. Leave real-account password, browser
login, SSO, MFA, device code, and other protected authentication to the user.
Do not message humans. Project pull-request submission and review responses are
allowed if the work reaches that phase.

This is systemic work. Preserve the decision hierarchy in
`docs/windows-agent-stack-decisions.json`, constraint provenance and reframe
gate in `docs/windows-agent-stack-design.md`, and the independent challenge in
`docs/windows-agent-stack-constraint-challenge.md`. The current reframe status
is `CLEAR`. The current constraint gate is `CLEAR` for proposal revision v4.
Before advancing an action, require a `CLEAR` gate or a `PARTIAL` gate that
explicitly permits that action. Invoke
`/dfrysinger-skills:constraint-challenge` only when development-loop reports a
material scope, architecture, trust, authority, policy, or reframe trigger.
Time alone never triggers it.

The completed read-only implementation review assignments are:

| Assignment | Owner route | Scope | Owed evidence | Integration boundary |
| --- | --- | --- | --- | --- |
| `implementation-review-opus` | `0ecf9d11-c15d-4e62-b644-c09fe984cafa` | Three bounded rounds over the Windows implementation and fix deltas | Complete JSON; all prior findings resolved | Closed |
| `implementation-review-terra` | `352c46b1-442b-440e-9414-89032e24bafb` | Three bounded rounds over the Windows implementation and fix deltas | Complete JSON; all prior findings resolved | Closed |

Both reviewers were read-only and own no repository paths. The coordinator is
the only writer in this checkout. Implementation and review are complete. A
focused constraint reconciliation narrowed credential-dependent login and
OpenSSH ceremonies out of the release gate while preserving provider-owned
authentication, durable resume wiring, and the documented cross-session
`Global\` mutex boundary.

Stay on this course until every item in the
"Definition of Done: Native Windows Agent Stack" section of
`docs/windows-agent-stack-design.md` is verified.

## Required process skills

- **Governing:** `/dfrysinger-skills:development-loop` - owns implementation,
  live proof, review, final acceptance, landing, and completion. Invoke it at
  run start and after compaction when it is no longer active.
- **Execution:** `/dfrysinger-skills:dual-review` - owns the current design
  review and the later implementation review. Invoke it only at those review
  gates.
- **Context:** `/dfrysinger-skills:self-compact` - at development-loop
  compaction points, persist the complete baton and invoke this skill as the
  final action. Do not compact because a reminder fired or during live proof.

```yaml
schedule_registry:
  charter_check:
    kind: charter_check
    id: 1
    interval: 4h
    status: live
  progress:
    kind: progress
    id: 2
    interval: 1h
    status: live
```
