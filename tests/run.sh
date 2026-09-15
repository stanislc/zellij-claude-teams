#!/usr/bin/env bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "${SHIM_TEST_REEXECED:-}" != "1" ]; then
    SHIM_TEST_BASH="${SHIM_TEST_BASH:-$(command -v bash)}"
    case "$SHIM_TEST_BASH" in
        /*) ;;
        *) echo "tests/run.sh: SHIM_TEST_BASH must be an absolute path" >&2; exit 2 ;;
    esac
    if [ ! -x "$SHIM_TEST_BASH" ]; then
        echo "tests/run.sh: SHIM_TEST_BASH is not executable: $SHIM_TEST_BASH" >&2
        exit 2
    fi
    export SHIM_TEST_BASH SHIM_TEST_REEXECED=1
    exec "$SHIM_TEST_BASH" "$0" "$@"
fi

suite=core
case_id=""
extra_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --suite)
            [ "$#" -ge 2 ] || { echo "tests/run.sh: --suite requires a value" >&2; exit 2; }
            suite="$2"
            shift 2
            ;;
        --case)
            [ "$#" -ge 2 ] || { echo "tests/run.sh: --case requires a value" >&2; exit 2; }
            case_id="$2"
            shift 2
            ;;
        *)
            extra_args+=("$1")
            shift
            ;;
    esac
done

case "$suite" in
    core)
        [ ${#extra_args[@]} -eq 0 ] || { echo "tests/run.sh: unexpected core arguments" >&2; exit 2; }
        args=(--suite core)
        [ -n "$case_id" ] && args+=(--case "$case_id")
        exec python3 "$TEST_DIR/test_compat.py" "${args[@]}"
        ;;
    fish)
        [ ${#extra_args[@]} -eq 0 ] || { echo "tests/run.sh: unexpected fish arguments" >&2; exit 2; }
        args=(--suite fish)
        [ -n "$case_id" ] && args+=(--case "$case_id")
        exec python3 "$TEST_DIR/test_fish.py" "${args[@]}"
        ;;
    live)
        [ -z "$case_id" ] || { echo "tests/run.sh: --case is only valid for the core or fish suite" >&2; exit 2; }
        [ -f "$TEST_DIR/live.py" ] || { echo "tests/run.sh: live suite is not installed" >&2; exit 2; }
        if [ ${#extra_args[@]} -gt 0 ]; then
            exec python3 "$TEST_DIR/live.py" "${extra_args[@]}"
        fi
        exec python3 "$TEST_DIR/live.py"
        ;;
    *)
        echo "tests/run.sh: unknown suite: $suite" >&2
        exit 2
        ;;
esac
