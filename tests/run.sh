#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="${TMPDIR:-/tmp}/zellij-tmux-shim-tests.$$"
FAKE_BIN="${TEST_TMP}/bin"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"

cat > "${FAKE_BIN}/zellij" <<'FAKE_ZELLIJ'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${FAKE_ZELLIJ_LOG:?FAKE_ZELLIJ_LOG not set}"
printf '%s\n' "$*" >> "$LOG_FILE"

if [ "${1:-}" = "action" ] && [ "${2:-}" = "new-pane" ]; then
    pane_id=""
    for arg in "$@"; do
        case "$arg" in
            %*[0-9])
                pane_id="$arg"
                ;;
        esac
    done
    if [ -n "$pane_id" ]; then
        pane_key="${pane_id#%}"
        echo "$$" > "${ZELLIJ_TMUX_SHIM_STATE}/${pane_key}.pid"
        echo "terminal_${pane_key}" > "${ZELLIJ_TMUX_SHIM_STATE}/${pane_key}.zellij_id"
        touch "${ZELLIJ_TMUX_SHIM_STATE}/${pane_key}.ready"
    fi
    echo "terminal_25"
fi
FAKE_ZELLIJ
chmod +x "${FAKE_BIN}/zellij"

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: ${message}" >&2
        echo "  expected: ${expected}" >&2
        echo "  actual:   ${actual}" >&2
        return 1
    fi
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local message="$3"
    case "$haystack" in
        *"$needle"*) ;;
        *)
            echo "FAIL: ${message}" >&2
            echo "  expected to find: ${needle}" >&2
            echo "  in: ${haystack}" >&2
            return 1
            ;;
    esac
}

assert_not_contains() {
    local needle="$1"
    local haystack="$2"
    local message="$3"
    case "$haystack" in
        *"$needle"*)
            echo "FAIL: ${message}" >&2
            echo "  did not expect: ${needle}" >&2
            echo "  in: ${haystack}" >&2
            return 1
            ;;
        *) ;;
    esac
}

run_test() {
    local name="$1"
    shift
    if "$@"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "ok - ${name}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "not ok - ${name}" >&2
    fi
}

test_activate_path_is_idempotent() (
    local output first count shim_bin
    output="$(ROOT_DIR="$ROOT_DIR" TEST_TMP="$TEST_TMP" bash -c '
        set -euo pipefail
        unset ZELLIJ_TMUX_SHIM_ACTIVE ZELLIJ_TMUX_SHIM_DIR ZELLIJ_TMUX_SHIM_ROOT ZELLIJ_TMUX_SHIM_STATE
        tmp="${TEST_TMP}/path-idempotent"
        data="${tmp}/data"
        run="${tmp}/run"
        shim_bin="${data}/zellij-tmux-shim/bin"
        mkdir -p "$shim_bin" "$run"
        export HOME="$tmp/home"
        export XDG_DATA_HOME="$data"
        export XDG_RUNTIME_DIR="$run"
        export ZELLIJ=1
        export ZELLIJ_SESSION_NAME="main"
        export PATH="/usr/bin:/bin"
        . "${ROOT_DIR}/activate.sh" >/dev/null 2>&1
        . "${ROOT_DIR}/activate.sh" >/dev/null 2>&1
        . "${ROOT_DIR}/activate.sh" >/dev/null 2>&1
        count=0
        old_ifs="$IFS"
        IFS=:
        for part in $PATH; do
            if [ "$part" = "$shim_bin" ]; then
                count=$((count + 1))
            fi
        done
        IFS="$old_ifs"
        printf "%s\n%s\n%s\n" "${PATH%%:*}" "$count" "$shim_bin"
    ')"
    first="$(printf '%s\n' "$output" | sed -n '1p')"
    count="$(printf '%s\n' "$output" | sed -n '2p')"
    shim_bin="$(printf '%s\n' "$output" | sed -n '3p')"
    assert_eq "$shim_bin" "$first" "shim bin stays first in PATH" || return 1
    assert_eq "1" "$count" "shim bin appears only once in PATH" || return 1
)

test_activate_sanitizes_session_name() (
    local output expected_root state actual_root
    output="$(ROOT_DIR="$ROOT_DIR" TEST_TMP="$TEST_TMP" bash -c '
        set -euo pipefail
        unset ZELLIJ_TMUX_SHIM_ACTIVE ZELLIJ_TMUX_SHIM_DIR ZELLIJ_TMUX_SHIM_ROOT ZELLIJ_TMUX_SHIM_STATE
        tmp="${TEST_TMP}/session-sanitize"
        data="${tmp}/data"
        run="${tmp}/run"
        expected_root="${run}/zellij-tmux-shim-$(id -u)"
        mkdir -p "${data}/zellij-tmux-shim/bin" "$run"
        export HOME="$tmp/home"
        export XDG_DATA_HOME="$data"
        export XDG_RUNTIME_DIR="$run"
        export ZELLIJ=1
        export ZELLIJ_SESSION_NAME="../../escaped"
        export PATH="/usr/bin:/bin"
        . "${ROOT_DIR}/activate.sh" >/dev/null 2>&1
        printf "%s\n%s\n%s\n" "$expected_root" "${ZELLIJ_TMUX_SHIM_ROOT:-}" "$ZELLIJ_TMUX_SHIM_STATE"
    ')"
    expected_root="$(printf '%s\n' "$output" | sed -n '1p')"
    actual_root="$(printf '%s\n' "$output" | sed -n '2p')"
    state="$(printf '%s\n' "$output" | sed -n '3p')"
    assert_eq "$expected_root" "$actual_root" "activation exports shim root" || return 1
    case "$state" in
        "$expected_root"/*) ;;
        *)
            echo "FAIL: state dir must stay under shim root" >&2
            echo "  root:  $expected_root" >&2
            echo "  state: $state" >&2
            return 1
            ;;
    esac
    assert_not_contains ".." "${state##*/}" "state basename is sanitized" || return 1
    assert_not_contains "/" "${state##*/}" "state basename has no slash" || return 1
)

test_deactivate_refuses_unsafe_state_path() (
    local tmp="${TEST_TMP}/deactivate-safety"
    local root="${tmp}/root"
    local escaped="${tmp}/escaped"
    mkdir -p "$root" "$escaped"
    touch "${escaped}/sentinel"

    export ZELLIJ_TMUX_SHIM_ACTIVE=1
    export ZELLIJ_TMUX_SHIM_ROOT="$root"
    export ZELLIJ_TMUX_SHIM_STATE="$escaped"
    export PATH="/usr/bin:/bin"

    set +e
    . "${ROOT_DIR}/deactivate.sh" >/dev/null 2>&1
    local code=$?
    set -e

    if [ "$code" -eq 0 ]; then
        echo "FAIL: deactivate should fail for state outside shim root" >&2
        return 1
    fi
    if [ ! -f "${escaped}/sentinel" ]; then
        echo "FAIL: deactivate removed an unsafe state directory" >&2
        return 1
    fi
)

test_split_window_prints_only_tmux_pane_id() (
    local tmp="${TEST_TMP}/split-window"
    local state="${tmp}/state"
    mkdir -p "$state"
    echo "1" > "${state}/next_id"
    touch "${state}/sessions"

    export FAKE_ZELLIJ_LOG="${tmp}/zellij.log"
    export ZELLIJ_TMUX_SHIM_STATE="$state"
    export ZELLIJ_TMUX_SHIM_DIR="$ROOT_DIR"
    export PATH="${FAKE_BIN}:/usr/bin:/bin"

    local output
    output="$("${ROOT_DIR}/bin/tmux" split-window -P -F '#{pane_id}')"
    assert_eq "%1" "$output" "split-window -P output is not polluted by zellij stdout" || return 1
)

test_display_message_honors_target_pane() (
    local tmp="${TEST_TMP}/display-message"
    local state="${tmp}/state"
    mkdir -p "$state"

    export ZELLIJ_TMUX_SHIM_STATE="$state"
    export ZELLIJ_TMUX_SHIM_DIR="$ROOT_DIR"
    export TMUX_PANE="%0"

    local output
    output="$("${ROOT_DIR}/bin/tmux" display-message -t %42 -p '#{pane_id}')"
    assert_eq "%42" "$output" "display-message returns requested target pane id" || return 1
)

test_send_keys_focuses_target_before_late_write() (
    local tmp="${TEST_TMP}/late-send-keys"
    local state="${tmp}/state"
    mkdir -p "$state"
    echo "terminal_7" > "${state}/7.zellij_id"
    echo "$$" > "${state}/7.pid"

    export FAKE_ZELLIJ_LOG="${tmp}/zellij.log"
    export ZELLIJ_TMUX_SHIM_STATE="$state"
    export ZELLIJ_TMUX_SHIM_DIR="$ROOT_DIR"
    export PATH="${FAKE_BIN}:/usr/bin:/bin"

    "${ROOT_DIR}/bin/tmux" send-keys -t %7 "echo hello" Enter

    local log
    log="$(cat "${tmp}/zellij.log")"
    assert_contains "action focus-pane-id terminal_7" "$log" "late send-keys focuses target pane" || return 1
    assert_contains "action write-chars echo hello" "$log" "late send-keys writes after focus" || return 1
)

run_test "activate PATH re-source is idempotent" test_activate_path_is_idempotent
run_test "activate sanitizes session-derived state path" test_activate_sanitizes_session_name
run_test "deactivate refuses unsafe state path" test_deactivate_refuses_unsafe_state_path
run_test "split-window -P prints only tmux pane id" test_split_window_prints_only_tmux_pane_id
run_test "display-message honors target pane" test_display_message_honors_target_pane
run_test "late send-keys focuses target pane before writing" test_send_keys_focuses_target_before_late_write

echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[ "$FAIL_COUNT" -eq 0 ]
