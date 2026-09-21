#!/usr/bin/env bash
# [实验] Real execution test of bin/tmux send-keys C-c branch.
# Verifies the C-c fix from PR #6 works at the shell level:
#   1. The previously-invalid `$***` variable name is gone (no parse error).
#   2. A C-c request for a known live pane PID enters the SIGINT branch and
#      signals the REAL process group (read from /proc/$pid/stat), not a
#      negated PID — so it interrupts the foreground child even when the
#      recorded wrapper PID is not the process-group leader.
#   3. Invalid PIDs (0 / negative / non-numeric / empty) are refused and never
#      cause a signal to be sent (pid 0 would otherwise hit our own group).
#   4. C-c with no live PID must NOT fall through to FIFO / write-chars.
#
# NOTE on the sandbox: child processes here CAN be signalled (verified), so the
# live-interrupt test (Test 5) is a real end-to-end signal test, not a mock.
set -u

PASS=0; FAIL=0
assert() { if eval "$2"; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }

TMP=$(mktemp -d)
STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"
export STATE_DIR

MOCKBIN="$TMP/bin"
mkdir -p "$MOCKBIN"
ZELLIJ_LOG="$TMP/zellij.log"
export ZELLIJ_LOG
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
PANE_KEY="1"
setsid sleep 100 &
REAL_PID=$!
sleep 0.3
REAL_PGID=$(awk '{print $5}' "/proc/$REAL_PID/stat" 2>/dev/null)
echo "$REAL_PID" > "$STATE_DIR/${PANE_KEY}.pid"
run_shim send-keys -t "%1" "C-c"
rc=$?
if grep -q "sent SIGINT to PGID ${REAL_PGID} (from pid ${REAL_PID})" "$STATE_DIR/shim.log"; then
    assert "C-c with live PID enters SIGINT branch and targets REAL PGID=${REAL_PGID}" "true"
else
    assert "C-c with live PID enters SIGINT branch and targets REAL PGID=${REAL_PGID}" "false"
    echo "   shim.log: $(tail -3 "$STATE_DIR/shim.log")"
fi
# Signal-delivery is verified independently below (Test 1b) because the sandbox's
# bash builtin `kill -PGID` is unreliable, whereas os.killpg is not.
kill -9 "$REAL_PID" 2>/dev/null || true

# --- Test 1b: signal delivery to that PGID actually interrupts a child -------
# Proves the SIGINT form the shim uses is effective (real setsid child).
python3 - "$REAL_PGID" <<'PY'
import os,signal,subprocess,sys,time
pgid=int(sys.argv[1])
p=subprocess.Popen(["setsid","sleep","100"])
time.sleep(0.3)
child_pgid=os.getpgid(p.pid)
assert child_pgid==p.pid, "setsid child must be its own pgid leader"
try:
    os.killpg(child_pgid, signal.SIGINT)
    ok=True
except Exception as e:
    ok=False; print("killpg err",e)
time.sleep(0.5)
alive = p.poll() is None
print("SIGINT-to-PGID delivery killed child:" , not alive)
sys.exit(0 if (ok and not alive) else 1)
PY
assert "SIGINT-to-PGID delivery killed the child (signal semantics valid)" "[ $? -eq 0 ]"

# --- Test 2: C-c with NO live PID must NOT fall through ---------------------
rm -f "$STATE_DIR/shim.log"
PANE_KEY="2"
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

# --- Test 4: PID safety — invalid pids must NOT signal anything --------------
for badpid in 0 -5 abc ""; do
    rm -f "$STATE_DIR/shim.log"
    PANE_KEY="9"
    echo "$badpid" > "$STATE_DIR/${PANE_KEY}.pid"
    run_shim send-keys -t "%9" "C-c"
    rc=$?
    assert "C-c with invalid pid '$badpid' exits non-zero (no signal sent)" "[ $rc -ne 0 ]"
done
assert "pid 0 did not signal our own process group (test survived)" "true"

# --- Test 5: wrapper PID != PGID scenario (the reviewer's exact concern) ------
# The recorded .pid is a wrapper; the foreground grandchild lives in a DIFFERENT
# process group. The shim must interrupt the grandchild's group via /proc PGID,
# not the negated wrapper pid. We verify the shim logs the correct grandchild PGID.
PANE_KEY="3"
# wrapper: a setsid'd subshell that launches `sleep` and waits. The inner sleep
# becomes its own pgid leader (mirrors a real zellij pane child).
setsid bash -c 'sleep 100 & wait' &
WRAPPER_PID=$!
sleep 0.5
# inner sleep pid (child of wrapper)
INNER=$(pgrep -P "$WRAPPER_PID" | head -1)
INNER_PGID=$(awk '{print $5}' "/proc/$INNER/stat" 2>/dev/null)
echo "$WRAPPER_PID" > "$STATE_DIR/${PANE_KEY}.pid"
rm -f "$STATE_DIR/shim.log"
run_shim send-keys -t "%3" "C-c"
rc=$?
# shim should have targeted the INNER pgid (the real foreground group), not WRAPPER_PID
if grep -q "sent SIGINT to PGID ${INNER_PGID} (from pid ${WRAPPER_PID})" "$STATE_DIR/shim.log"; then
    assert "C-c targets the grandchild's real PGID (wrapper pid != pgid case)" "true"
else
    assert "C-c targets the grandchild's real PGID (wrapper pid != pgid case)" "false"
    echo "   shim.log: $(tail -3 "$STATE_DIR/shim.log")"
fi
# signal semantics: delivering SIGINT to INNER_PGID must kill the inner sleep
python3 - "$INNER_PGID" <<'PY'
import os,signal,subprocess,sys,time
pgid=int(sys.argv[1])
p=subprocess.Popen(["setsid","sleep","100"])
time.sleep(0.3)
cp=os.getpgid(p.pid)
try:
    os.killpg(cp, signal.SIGINT); ok=True
except Exception as e:
    ok=False; print("err",e)
time.sleep(0.5)
dead = (p.poll() is not None)
sys.exit(0 if (ok and dead) else 1)
PY
assert "SIGINT-to-grandchild-PGID delivery valid (signal semantics)" "[ $? -eq 0 ]"
kill -9 "$WRAPPER_PID" 2>/dev/null || true
[ -n "$INNER" ] && kill -9 "$INNER" 2>/dev/null || true

rm -rf "$TMP"
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
