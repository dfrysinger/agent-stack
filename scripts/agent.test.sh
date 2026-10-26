#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="${WRAPPER:-$ROOT/bin/agent}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_DIR="$TMP/home"
BIN_DIR="$TMP/bin"
STATE_DIR="$TMP/tmux"
LOG="$TMP/tmux.log"
AUX_LOG="$TMP/aux.log"
mkdir -p "$HOME_DIR" "$BIN_DIR" "$STATE_DIR/sessions"

for name in agent-stack copilot-agent claude-agent codex-agent agent ca cc co remote-agent mystery-agent; do
  ln -s "$WRAPPER" "$BIN_DIR/$name"
done

for name in copilot claude codex; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
done

cat > "$BIN_DIR/security" <<'FAKE_SECURITY'
#!/usr/bin/env bash
printf 'security|%s\n' "$*" >> "$FAKE_AUX_LOG"
FAKE_SECURITY
chmod +x "$BIN_DIR/security"

cat > "$BIN_DIR/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
set -euo pipefail
command="$1"
shift
case "$command" in
  has-session)
    target="${*: -1}"
    target="${target#=}"
    [ -f "$FAKE_TMUX_STATE/sessions/$target" ]
    ;;
  display-message)
    target=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    case "$target" in
      =*:) target="${target#=}"; target="${target%:}" ;;
      *) echo "display-message requires an exact session-form target" >&2; exit 1 ;;
    esac
    cat "$FAKE_TMUX_STATE/sessions/$target"
    ;;
  new-session)
    session=""
    directory=""
    args="$*"
    while [ $# -gt 0 ]; do
      case "$1" in
        -s) session="$2"; shift 2 ;;
        -c) directory="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s\n' "$directory" > "$FAKE_TMUX_STATE/sessions/$session"
    printf 'new-session|%s|%s|%s\n' "$session" "$directory" "$args" >> "$FAKE_TMUX_LOG"
    ;;
  switch-client|attach)
    printf '%s|%s\n' "$command" "$*" >> "$FAKE_TMUX_LOG"
    ;;
  list-panes)
    ;;
  capture-pane)
    printf '\n'
    ;;
  send-keys)
    printf 'send-keys|%s\n' "$*" >> "$FAKE_TMUX_LOG"
    ;;
  *)
    echo "unexpected fake tmux command: $command" >&2
    exit 1
    ;;
esac
FAKE_TMUX
chmod +x "$BIN_DIR/tmux"

COPILOT_BASE="$TMP/copilot-workspace"
CLAUDE_BASE="$TMP/claude-workspace"
CODEX_BASE="$TMP/codex-workspace"
mkdir -p "$COPILOT_BASE" "$CLAUDE_BASE" "$CODEX_BASE"

run_agent() {
  env -u TMUX \
    HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$TMP/config" \
    XDG_CACHE_HOME="$TMP/cache" \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    TMUX="fake" \
    FAKE_TMUX_STATE="$STATE_DIR" \
    FAKE_TMUX_LOG="$LOG" \
    FAKE_AUX_LOG="$AUX_LOG" \
    COPILOT_WORKSPACE_BASE="$COPILOT_BASE" \
    CLAUDE_WORKSPACE_BASE="$CLAUDE_BASE" \
    CODEX_WORKSPACE_BASE="$CODEX_BASE" \
    SESSION_WARN_MB=0 \
    "$@"
}

run_agent_without_tmux() {
  env -u TMUX \
    HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$TMP/config" \
    XDG_CACHE_HOME="$TMP/cache" \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    FAKE_TMUX_STATE="$STATE_DIR" \
    FAKE_TMUX_LOG="$LOG" \
    FAKE_AUX_LOG="$AUX_LOG" \
    COPILOT_WORKSPACE_BASE="$COPILOT_BASE" \
    CLAUDE_WORKSPACE_BASE="$CLAUDE_BASE" \
    CODEX_WORKSPACE_BASE="$CODEX_BASE" \
    SESSION_WARN_MB=0 \
    "$@"
}

reset_tmux() {
  rm -rf "$STATE_DIR/sessions"
  mkdir -p "$STATE_DIR/sessions"
  : > "$LOG"
  : > "$AUX_LOG"
}

assert_not_contains() {
  if grep -Fq -- "$2" "$1"; then
    echo "did not expect '$2' in $1" >&2
    cat "$1" >&2
    exit 1
  fi
}

assert_contains() {
  grep -Fq -- "$2" "$1" || {
    echo "expected '$2' in $1" >&2
    cat "$1" >&2
    exit 1
  }
}

assert_fails_with() {
  expected="$1"
  shift
  set +e
  run_agent "$@" >"$TMP/stdout" 2>"$TMP/stderr"
  status=$?
  set -e
  [ "$status" -eq "$expected" ] || {
    echo "expected status $expected, got $status: $*" >&2
    cat "$TMP/stderr" >&2
    exit 1
  }
}

run_agent "$BIN_DIR/agent-stack" --help >/dev/null
for backend in copilot claude codex; do
  run_agent "$BIN_DIR/agent-stack" "$backend" --help >/dev/null
  run_agent "$BIN_DIR/$backend-agent" --help >/dev/null
done
assert_fails_with 2 "$BIN_DIR/agent-stack"
assert_fails_with 2 "$BIN_DIR/agent-stack" unknown alpha
assert_fails_with 2 "$BIN_DIR/agent-stack" copilot alpha extra
assert_fails_with 2 "$BIN_DIR/agent-stack" copilot "x/../../claude-workspace/agent-victim"
[ ! -e "$TMP/claude-workspace/agent-victim" ]
assert_fails_with 2 "$BIN_DIR/ca" alpha
assert_contains "$TMP/stderr" "'ca' is retired"
assert_fails_with 2 "$BIN_DIR/cc" alpha
assert_contains "$TMP/stderr" "'cc' is retired"
assert_fails_with 2 "$BIN_DIR/co" alpha
assert_contains "$TMP/stderr" "'co' is retired"
assert_fails_with 2 "$BIN_DIR/mystery-agent" alpha

for backend in copilot claude codex; do
  reset_tmux
  run_agent "$BIN_DIR/agent-stack" "$backend" alpha
  expected_session="$backend-alpha"
  [ "$backend" = "copilot" ] && expected_session="alpha"
  assert_contains "$LOG" "new-session|$expected_session|$TMP/$backend-workspace/agent-alpha"
  assert_contains "$LOG" "$backend"
  if [ "$backend" = "copilot" ]; then
    assert_not_contains "$LOG" "--remote"
    assert_contains "$LOG" "env COPILOT_TASK_WAIT_TIMEOUT_SECONDS='3600' copilot"
  else
    assert_contains "$LOG" "env -u COPILOT_TASK_WAIT_TIMEOUT_SECONDS $backend"
  fi
  if [ "$backend" = "codex" ]; then
    assert_not_contains "$LOG" "resume --last"
  fi

  canonical_log="$(cat "$LOG")"
  reset_tmux
  run_agent "$BIN_DIR/$backend-agent" alpha
  [ "$(cat "$LOG")" = "$canonical_log" ] || {
    echo "$backend alias differs from canonical command" >&2
    exit 1
  }
done

reset_tmux
mkdir -p "$COPILOT_BASE/agent-alpha"
printf '%s\n' "$COPILOT_BASE/agent-alpha" > "$STATE_DIR/sessions/alpha"
COPILOT_TASK_WAIT_TIMEOUT_SECONDS=invalid run_agent "$BIN_DIR/agent-stack" copilot alpha
assert_contains "$LOG" "switch-client|-t =alpha"

reset_tmux
mkdir -p "$COPILOT_BASE/agent-alpha"
printf '%s\n' "$COPILOT_BASE/agent-alpha" > "$STATE_DIR/sessions/copilot-alpha"
run_agent "$BIN_DIR/agent-stack" copilot alpha
assert_contains "$LOG" "switch-client|-t =copilot-alpha"

reset_tmux
mkdir -p "$TMP/other"
printf '%s\n' "$TMP/other" > "$STATE_DIR/sessions/alpha"
assert_fails_with 1 "$BIN_DIR/agent-stack" copilot alpha
[ ! -s "$LOG" ]
assert_contains "$TMP/stderr" "belongs to another workspace"

reset_tmux
mkdir -p "$CLAUDE_BASE/agent-alpha" "$TMP/other"
printf '%s\n' "$TMP/other" > "$STATE_DIR/sessions/claude-alpha"
assert_fails_with 1 "$BIN_DIR/agent-stack" claude alpha
[ ! -s "$LOG" ]
assert_contains "$TMP/stderr" "belongs to another workspace"

reset_tmux
mkdir -p "$CLAUDE_BASE/agent-alpha"
ln -s "$CLAUDE_BASE/agent-alpha" "$TMP/claude-agent-link"
printf '%s\n' "$TMP/claude-agent-link" > "$STATE_DIR/sessions/claude-alpha"
run_agent "$BIN_DIR/agent-stack" claude alpha
assert_contains "$LOG" "switch-client|-t =claude-alpha"

reset_tmux
printf '%s\n' "$CLAUDE_BASE/agent-alpha" > "$STATE_DIR/sessions/claude-alpha"
run_agent_without_tmux "$BIN_DIR/agent-stack" claude alpha >"$TMP/stdout" 2>"$TMP/stderr" || status=$?
[ "${status:-0}" -eq 1 ]
assert_contains "$TMP/stderr" "refusing to attach"
unset status

reset_tmux
mkdir -p "$HOME_DIR/.copilot/session-state/selected" "$COPILOT_BASE/agent-selected"
cat > "$HOME_DIR/.copilot/session-state/selected/workspace.yaml" <<EOF
id: 11111111-1111-1111-1111-111111111111
cwd: $COPILOT_BASE/agent-selected
updated_at: 2026-08-02T10:00:00Z
summary_count: 2
EOF
run_agent "$BIN_DIR/agent-stack" copilot selected >"$TMP/stdout" 2>"$TMP/stderr"
assert_contains "$LOG" "--session-id='11111111-1111-1111-1111-111111111111'"
assert_not_contains "$LOG" "--remote"
assert_contains "$TMP/stderr" "Scanning Copilot session metadata"
assert_contains "$TMP/stderr" "Session scan complete"
assert_not_contains "$TMP/stdout" "Scanning"

reset_tmux
run_agent "$BIN_DIR/agent-stack" copilot selected >"$TMP/stdout" 2>"$TMP/stderr"
assert_contains "$LOG" "--session-id='11111111-1111-1111-1111-111111111111'"
assert_contains "$TMP/stderr" "1 reused, 0 read"
[ -f "$TMP/cache/remote-agent-stack/copilot-sessions-v1.json" ]

write_copilot_session() {
  mkdir -p "$HOME_DIR/.copilot/session-state/$1"
  printf 'id: %s\ncwd: %s\nupdated_at: %s\nsummary_count: %s\n' \
    "$2" "$3" "$4" "$5" > "$HOME_DIR/.copilot/session-state/$1/workspace.yaml"
}

write_copilot_session real-new 22222222-2222-2222-2222-222222222222 \
  "$COPILOT_BASE/agent-selected" 2026-08-03T10:00:00Z 1
write_copilot_session retired 33333333-3333-3333-3333-333333333333 \
  "$COPILOT_BASE/agent-selected" 2026-08-04T10:00:00Z 3
write_copilot_session empty-new 44444444-4444-4444-4444-444444444444 \
  "$COPILOT_BASE/agent-selected" 2026-08-05T10:00:00Z 0
write_copilot_session other-workspace 55555555-5555-5555-5555-555555555555 \
  "$COPILOT_BASE/agent-other" 2026-08-06T10:00:00Z 9
printf '%s\n' 33333333-3333-3333-3333-333333333333 > "$COPILOT_BASE/agent-selected/.ca-retired-sessions"
mkdir -p "$HOME_DIR/.copilot/session-state/missing-metadata"
reset_tmux
run_agent "$BIN_DIR/agent-stack" copilot selected
assert_contains "$LOG" "--session-id='22222222-2222-2222-2222-222222222222'"

printf '%s\n' 22222222-2222-2222-2222-222222222222 >> "$COPILOT_BASE/agent-selected/.ca-retired-sessions"
reset_tmux
run_agent "$BIN_DIR/agent-stack" copilot selected
assert_contains "$LOG" "--session-id='11111111-1111-1111-1111-111111111111'"

printf '%s\n' 11111111-1111-1111-1111-111111111111 >> "$COPILOT_BASE/agent-selected/.ca-retired-sessions"
reset_tmux
run_agent "$BIN_DIR/agent-stack" copilot selected
assert_contains "$LOG" "--session-id='44444444-4444-4444-4444-444444444444'"

write_copilot_session tie-a 66666666-6666-6666-6666-666666666666 \
  "$COPILOT_BASE/agent-selected" 2026-08-07T10:00:00Z 1
write_copilot_session tie-z 77777777-7777-7777-7777-777777777777 \
  "$COPILOT_BASE/agent-selected" 2026-08-07T10:00:00Z 1
reset_tmux
run_agent "$BIN_DIR/agent-stack" copilot selected
assert_contains "$LOG" "--session-id='66666666-6666-6666-6666-666666666666'"

reset_tmux
mkdir -p "$HOME_DIR/Library/Keychains"
touch "$HOME_DIR/Library/Keychains/login.keychain-db"
run_agent "$BIN_DIR/agent-stack" copilot keychain >"$TMP/stdout" 2>"$TMP/stderr"
assert_contains "$AUX_LOG" "security|unlock-keychain"
assert_contains "$TMP/stderr" "Unlocking the login keychain"

reset_tmux
MAILBOX_DIR="$HOME_DIR/.copilot/installed-plugins/_direct/dfrysinger--skills/skills/mailbox/scripts"
mkdir -p "$MAILBOX_DIR"
cat > "$MAILBOX_DIR/mailbox-poke.sh" <<'MAILBOX'
#!/usr/bin/env bash
printf 'mailbox|%s\n' "$*" >> "$FAKE_AUX_LOG"
MAILBOX
chmod +x "$MAILBOX_DIR/mailbox-poke.sh"
MAILBOX_INTEGRATION=true run_agent "$BIN_DIR/agent-stack" copilot mailbox
for _ in 1 2 3 4 5 6 7 8 9 10; do
  grep -Fq "mailbox|mailbox --wait" "$AUX_LOG" 2>/dev/null && break
  sleep 0.1
done
assert_contains "$AUX_LOG" "mailbox|mailbox --wait"

reset_tmux
mkdir -p "$HOME_DIR/.claude/projects/$(printf '%s' "$CLAUDE_BASE/agent-alpha" | sed 's|/|-|g')"
touch "$HOME_DIR/.claude/projects/$(printf '%s' "$CLAUDE_BASE/agent-alpha" | sed 's|/|-|g')/session.jsonl"
run_agent "$BIN_DIR/agent-stack" claude alpha
assert_contains "$LOG" "claude --continue"

reset_tmux
mkdir -p "$HOME_DIR/.codex/sessions/2026/08/02"
printf '{"type":"session_meta","payload":{"cwd":"%s"}}\n' \
  "$CODEX_BASE/agent-alpha" > "$HOME_DIR/.codex/sessions/2026/08/02/rollout.jsonl"
run_agent "$BIN_DIR/agent-stack" codex alpha
assert_contains "$LOG" "codex resume --last"

reset_tmux
mkdir -p "$TMP/config/remote-agent-stack"
cat > "$TMP/config/remote-agent-stack/config" <<'EOF'
COPILOT_TASK_WAIT_TIMEOUT_SECONDS="1200"
EOF
run_agent "$BIN_DIR/agent-stack" copilot timeout-config
assert_contains "$LOG" "env COPILOT_TASK_WAIT_TIMEOUT_SECONDS='1200' copilot"

reset_tmux
COPILOT_TASK_WAIT_TIMEOUT_SECONDS=1800 \
  run_agent "$BIN_DIR/agent-stack" copilot timeout-override
assert_contains "$LOG" "env COPILOT_TASK_WAIT_TIMEOUT_SECONDS='1800' copilot"

reset_tmux
COPILOT_TASK_WAIT_TIMEOUT_SECONDS= \
  assert_fails_with 2 "$BIN_DIR/agent-stack" copilot timeout-empty
assert_contains "$TMP/stderr" "COPILOT_TASK_WAIT_TIMEOUT_SECONDS must be a positive integer"
[ ! -s "$LOG" ]

reset_tmux
COPILOT_TASK_WAIT_TIMEOUT_SECONDS=invalid \
  assert_fails_with 2 "$BIN_DIR/agent-stack" copilot timeout-invalid
assert_contains "$TMP/stderr" "COPILOT_TASK_WAIT_TIMEOUT_SECONDS must be a positive integer"
[ ! -s "$LOG" ]

reset_tmux
COPILOT_TASK_WAIT_TIMEOUT_SECONDS=00 \
  assert_fails_with 2 "$BIN_DIR/agent-stack" copilot timeout-zero
assert_contains "$TMP/stderr" "COPILOT_TASK_WAIT_TIMEOUT_SECONDS must be a positive integer"
[ ! -s "$LOG" ]
rm -f "$TMP/config/remote-agent-stack/config"

for backend in copilot claude codex; do
  reset_tmux
  ALLOW_ALL=true run_agent "$BIN_DIR/agent-stack" "$backend" permissions
  case "$backend" in
    copilot) flag="--allow-all" ;;
    claude) flag="--dangerously-skip-permissions" ;;
    codex) flag="--dangerously-bypass-approvals-and-sandbox" ;;
  esac
  assert_contains "$LOG" "$flag"
done

echo "agent wrapper tests passed"
