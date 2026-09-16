#!/usr/bin/env bash
# [实验] Real execution test of bin/tmux capture-pane subset (PR #6).
# Verifies the capture-pane implementation per upstream review requirements:
#   - supports -t <pane> -p (print to stdout) and -S/-E (full history)
#   - rejects -b (alternate buffer) and any unknown flag with non-zero exit
#   - requires -p (no buffer concept) -> non-zero
#   - invalid/unknown pane -> non-zero
#   - maps onto `zellij action dump-screen [--full] --pane-id <zid>`
#
# We run the REAL bin/tmux with a mock `zellij` that records invocations and
# returns canned screen content, plus a mock state dir holding a .zellij_id.
set -u

PASS=0; FAIL=0
assert() { if eval "$2"; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }

TMP=$(mktemp -d)
STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

MOCKBIN="$TMP/bin"
mkdir -p "$MOCKBIN"
ZELLIJ_LOG="$TMP/zellij.log"
export ZELLIJ_LOG
# mock zellij: capture `action dump-screen ... --pane-id <zid>` and echo content.
cat > "$MOCKBIN/zellij" <<'EOF'
#!/usr/bin/env bash
echo "zellij $*" >> "$ZELLIJ_LOG"
# extract pane-id
pid=""
full=0
for ((i=1;i<=$#;i++)); do
  a="${!i}"
  case "$a" in
    --pane-id) j=$((i+1)); eval p="\${$j}"; pid="$p" ;;
    --full) full=1 ;;
  esac
done
if [ "$full" = 1 ]; then
  echo "DUMP-FULL for $pid"
else
  echo "DUMP-VIEWPORT for $pid"
fi
exit 0
EOF
chmod +x "$MOCKBIN/zellij"

SHIM="$PWD/bin/tmux"
run_shim() {
    PATH="$MOCKBIN:$PATH" \
    ZELLIJ_TMUX_SHIM_STATE="$STATE_DIR" \
    ZELLIJ_TMUX_SHIM_DIR="$STATE_DIR" \
    timeout 10 "$SHIM" "$@"
}

# valid pane state file
PANE_KEY="3"
echo "zid-abc123" > "$STATE_DIR/${PANE_KEY}.zellij_id"

# --- Test A: basic capture -t %3 -p -> dump-screen --pane-id zid-abc123 ------
out=$(run_shim capture-pane -t "%3" -p); rc=$?
assert "capture-pane -t %3 -p exits 0" "[ $rc -eq 0 ]"
assert "capture-pane -p prints pane content" "echo '$out' | grep -q 'DUMP-VIEWPORT for zid-abc123'"
assert "capture-pane maps to 'zellij action dump-screen --pane-id zid-abc123'" "grep -q 'zellij action dump-screen --pane-id zid-abc123' '$ZELLIJ_LOG'"

# --- Test B: -S/-E (history range) -> --full ---------------------------------
rm -f "$ZELLIJ_LOG"
out=$(run_shim capture-pane -t "%3" -p -S -10 -E -1); rc=$?
assert "capture-pane -S/-E exits 0" "[ $rc -eq 0 ]"
assert "capture-pane -S/-E uses --full" "grep -q 'zellij action dump-screen --full --pane-id zid-abc123' '$ZELLIJ_LOG'"

# --- Test C: -b (alternate buffer) rejected with non-zero --------------------
rm -f "$ZELLIJ_LOG"
run_shim capture-pane -t "%3" -p -b >/dev/null 2>&1; rc=$?
assert "capture-pane -b (alternate buffer) exits non-zero" "[ $rc -ne 0 ]"
assert "capture-pane -b does NOT call zellij" "[ ! -s '$ZELLIJ_LOG' ]"

# --- Test D: missing -p rejected with non-zero -------------------------------
rm -f "$ZELLIJ_LOG"
run_shim capture-pane -t "%3" >/dev/null 2>&1; rc=$?
assert "capture-pane without -p exits non-zero" "[ $rc -ne 0 ]"

# --- Test E: unknown flag rejected with non-zero -----------------------------
rm -f "$ZELLIJ_LOG"
run_shim capture-pane -t "%3" -p --bogus >/dev/null 2>&1; rc=$?
assert "capture-pane with unknown flag exits non-zero" "[ $rc -ne 0 ]"

# --- Test F: invalid pane key rejected with non-zero -------------------------
rm -f "$ZELLIJ_LOG"
run_shim capture-pane -t "%not-a-pane" -p >/dev/null 2>&1; rc=$?
assert "capture-pane with invalid pane key exits non-zero" "[ $rc -ne 0 ]"

# --- Test G: missing zellij_id -> non-zero -----------------------------------
rm -f "$ZELLIJ_LOG"
PANE_KEY="4"
run_shim capture-pane -t "%4" -p >/dev/null 2>&1; rc=$?
assert "capture-pane for pane with no zellij_id exits non-zero" "[ $rc -ne 0 ]"

rm -rf "$TMP"
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
