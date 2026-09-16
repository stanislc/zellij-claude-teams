#!/usr/bin/env bash
# [实验] Real execution test of bin/tmux send-keys C-c branch.
# Verifies the C-c fix from PR #6 works at the shell level:
#   1. The previously-invalid `$***` variable name is gone (no parse error).
#   2. A C-c request for a known live pane PID enters the SIGINT branch and
#      invokes `kill -INT -- -<pid>` (process-group SIGINT). We observe this
#      via the shim's own debug log ("sent SIGINT to PID"), which is emitted
#      exactly when the branch runs, so we do not need to mock `kill`.
#   3. C-c with no live PID must NOT fall through to the FIFO / write-chars
#      path (no text written to the pane); it exits non-zero instead.
#
# NOTE on the sandbox: child processes here cannot actually be killed by
# signals (container signal isolation — even `kill -9` to a real `sleep` is
# ignored). So we assert on the shim's *control flow* (correct branch entry
# and kill invocation form) rather than on a real process dying. The actual
# signal delivery is verified by inspection of the kill form + the upstream
# review; a live Zellij run is recommended before merge (documented as such).
set -u

PASS=0; FAIL=0
assert() { if eval "$2"; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }

TMP=$(mktemp -d)
STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"
export STATE_DIR

# Mock `zellij` only (kill is a bash builtin we must NOT override, so we rely
# on the shim's debug log to observe branch entry).
MOCKBIN="$TMP/bin"
mkdir -p "$MOCKBIN"
ZELLIJ_LOG="$TMP/zellij.log"
cat > "$MOCKBIN/zellij" <<'EOF'
#!/usr/bin/env bash
echo "zellij $*" >> "$ZELLIJ_LOG"
exit 0
EOF
chmod +x "$MOCKBIN/zellij"

SHIM="$PWD/bin/tmux"

run_shim() {
    PATH="$MOCKBIN:$PATH" \
    ZELLIJ_TMUX_SHIM_STATE="$STATE_DIR" \
    ZELLIJ_TMUX_SHIM_DIR="$STATE_DIR" \
    ZELLIJ_TMUX_SHIM_DEBUG=1 \
    timeout 10 "$SHIM" "$@"
}

# --- Test 1: C-c with a KNOWN LIVE pid enters SIGINT branch ------------------
# Start a real (unsignalable in this sandbox, but present) process and use its
# real pid. `kill -0` will succeed because the process exists, so the branch
# runs and the shim logs the SIGINT attempt.
PANE_KEY="1"
sleep 100 &
REAL_PID=$!
echo "$REAL_PID" > "$STATE_DIR/${PANE_KEY}.pid"

run_shim send-keys -t "%1" "C-c"
rc=$?
# Branch ran iff the shim logged "sent SIGINT to PID"
if grep -q "sent SIGINT to PID" "$STATE_DIR/shim.log"; then
    assert "C-c with live PID enters SIGINT branch (no parse crash, rc=$rc)" "true"
else
    assert "C-c with live PID enters SIGINT branch (no parse crash, rc=$rc)" "false"
    echo "   shim.log: $(tail -3 "$STATE_DIR/shim.log")"
fi
# And it must have used the process-group form in the log line.
if grep -q "sent SIGINT to PID $REAL_PID (process group attempted)" "$STATE_DIR/shim.log"; then
    assert "C-c uses process-group SIGINT form 'kill -INT -- -<pid>'" "true"
else
    assert "C-c uses process-group SIGINT form 'kill -INT -- -<pid>'" "false"
fi
kill -9 "$REAL_PID" 2>/dev/null || true

# --- Test 2: C-c with NO live PID must NOT fall through ---------------------
rm -f "$STATE_DIR/shim.log"
PANE_KEY="2"
# pid file references a non-existent pid so kill -0 fails -> branch must refuse
echo "999999" > "$STATE_DIR/${PANE_KEY}.pid"
run_shim send-keys -t "%2" "C-c"
rc=$?
assert "C-c with no live PID exits non-zero (refuses fall-through)" "[ $rc -ne 0 ]"
if grep -q "write-chars" "$ZELLIJ_LOG"; then
    assert "C-c never falls through to write-chars" "false"
else
    assert "C-c never falls through to write-chars" "true"
fi

# --- Test 3: no parse error from the old invalid '$***' variable name --------
if grep -n '\*\*\*' "$SHIM" | grep -v '#'; then
    assert "no live '\$***' variable usage in shim" "false"
else
    assert "no live '\$***' variable usage in shim" "true"
fi

rm -rf "$TMP"
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
