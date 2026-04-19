#!/usr/bin/env bash
# shellcheck disable=SC2317
# Source this file to activate the zellij-tmux-shim.
# Usage: source activate.sh

# Guard: only activate inside zellij
if [ -z "${ZELLIJ:-}" ]; then
    echo "zellij-tmux-shim: not inside zellij, skipping activation" >&2
    return 1 2>/dev/null || exit 1
fi

# Guard: don't double-activate — but always re-ensure PATH priority.
# Child shells inherit ZELLIJ_TMUX_SHIM_ACTIVE but rebuild PATH from
# shell config, pushing the shim behind other entries (brew, cargo, etc.).
if [ -n "${ZELLIJ_TMUX_SHIM_ACTIVE:-}" ]; then
    _shim_bin="${ZELLIJ_TMUX_SHIM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim}/bin"
    _first_path_component="${PATH%%:*}"
    if [ "$_first_path_component" != "$_shim_bin" ]; then
        export PATH="${_shim_bin}:${PATH}"
    fi
    unset _shim_bin _first_path_component
    return 0 2>/dev/null || exit 0
fi

# XDG-compliant install directory
ZELLIJ_TMUX_SHIM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim"

# Runtime state goes in a ephemeral, per-user, per-session directory (PIDs, FIFOs, etc.)
# XDG_RUNTIME_DIR is /run/user/UID on systemd Linux; TMPDIR is per-user on macOS
# Scoped by ZELLIJ_SESSION_NAME so multiple zellij sessions don't collide.
_runtime_base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
_shim_root="${_runtime_base}/zellij-tmux-shim-$(id -u)"
ZELLIJ_TMUX_SHIM_ROOT="$_shim_root"
_session_raw="${ZELLIJ_SESSION_NAME:-default}"
_session_slug=$(printf '%s' "$_session_raw" | tr -c '[:alnum:]_-' '-' | sed 's/^-*//; s/-*$//; s/--*/-/g' | cut -c 1-48)
[ -n "$_session_slug" ] || _session_slug="default"
_session_hash=$(printf '%s' "$_session_raw" | cksum | awk '{print $1}')
ZELLIJ_TMUX_SHIM_STATE="${_shim_root}/${_session_slug}-${_session_hash}"
unset _session_raw _session_slug _session_hash
unset _runtime_base

# Save real tmux path before we shadow it
ZELLIJ_TMUX_SHIM_REAL_TMUX="$(command -v tmux 2>/dev/null || true)"
export ZELLIJ_TMUX_SHIM_REAL_TMUX

# Save original PATH for deactivation
ZELLIJ_TMUX_SHIM_ORIG_PATH="$PATH"
export ZELLIJ_TMUX_SHIM_ORIG_PATH

# Prepend shim bin to PATH so our tmux shadows the real one
export PATH="${ZELLIJ_TMUX_SHIM_DIR}/bin:${PATH}"

# Set fake tmux env vars so Claude Code thinks it's inside tmux
export TMUX="zellij-shim:/tmp/zellij-shim,$$,0"
export TMUX_PANE="%0"

# Export state dir for shim scripts
export ZELLIJ_TMUX_SHIM_DIR
export ZELLIJ_TMUX_SHIM_ROOT
export ZELLIJ_TMUX_SHIM_STATE

# Initialize state directory — this is the security keystone.
# FIFOs, eval'd env files, and command delivery all live here.
# chmod 700 MUST succeed; if it doesn't, the shim is unsafe.
# Secure the per-user root directory first, then create the per-session subdir.
if [ -L "$_shim_root" ]; then
    echo "zellij-tmux-shim: ERROR: state root is a symlink, refusing to activate" >&2
    unset _shim_root
    return 1 2>/dev/null || exit 1
fi
if ! mkdir -p "$_shim_root"; then
    echo "zellij-tmux-shim: ERROR: failed to create state root" >&2
    unset _shim_root
    return 1 2>/dev/null || exit 1
fi
if ! chmod 700 "$_shim_root"; then
    echo "zellij-tmux-shim: ERROR: failed to secure state root" >&2
    unset _shim_root
    return 1 2>/dev/null || exit 1
fi
_owner=$(stat -c '%u' "$_shim_root" 2>/dev/null || stat -f '%u' "$_shim_root" 2>/dev/null)
if [ "$_owner" != "$(id -u)" ]; then
    echo "zellij-tmux-shim: ERROR: state root not owned by current user" >&2
    unset _shim_root _owner
    return 1 2>/dev/null || exit 1
fi
unset _owner
# Per-session subdir inherits root's 700 protection
case "$ZELLIJ_TMUX_SHIM_STATE" in
    "$_shim_root"/*) ;;
    *)
        echo "zellij-tmux-shim: ERROR: state dir escaped state root" >&2
        unset _shim_root
        return 1 2>/dev/null || exit 1
        ;;
esac
if ! mkdir -p "$ZELLIJ_TMUX_SHIM_STATE"; then
    echo "zellij-tmux-shim: ERROR: failed to create state dir" >&2
    unset _shim_root
    return 1 2>/dev/null || exit 1
fi
if ! chmod 700 "$ZELLIJ_TMUX_SHIM_STATE"; then
    echo "zellij-tmux-shim: ERROR: failed to secure state dir" >&2
    unset _shim_root
    return 1 2>/dev/null || exit 1
fi
_owner=$(stat -c '%u' "$ZELLIJ_TMUX_SHIM_STATE" 2>/dev/null || stat -f '%u' "$ZELLIJ_TMUX_SHIM_STATE" 2>/dev/null)
if [ "$_owner" != "$(id -u)" ]; then
    echo "zellij-tmux-shim: ERROR: state dir not owned by current user" >&2
    unset _shim_root _owner
    return 1 2>/dev/null || exit 1
fi
unset _owner
unset _shim_root

# Initialize next_id counter (start at 1, %0 is reserved for the host pane)
if [ ! -f "$ZELLIJ_TMUX_SHIM_STATE/next_id" ]; then
    echo "1" > "$ZELLIJ_TMUX_SHIM_STATE/next_id"
fi

# Initialize sessions file
if [ ! -f "$ZELLIJ_TMUX_SHIM_STATE/sessions" ]; then
    touch "$ZELLIJ_TMUX_SHIM_STATE/sessions"
fi

# Sweep stale state from prior crashed sessions: remove state files
# for PIDs that no longer exist.
# Uses find instead of a glob to avoid zsh NOMATCH error when no .pid files exist.
command find "$ZELLIJ_TMUX_SHIM_STATE" -maxdepth 1 -name '*.pid' 2>/dev/null | while IFS= read -r _pidfile; do
    _pid=$(cat "$_pidfile" 2>/dev/null)
    if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
        _key="${_pidfile##*/}"
        _key="${_key%.pid}"
        rm -f "$ZELLIJ_TMUX_SHIM_STATE/${_key}.pid" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.zellij_id" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.fifo" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.ready" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.cmd" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.named" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.group"
    fi
done

# Clean up orphaned .zellij_id files (no matching .pid = dead pane)
command find "$ZELLIJ_TMUX_SHIM_STATE" -maxdepth 1 -name '*.zellij_id' 2>/dev/null | while IFS= read -r _idfile; do
    _key="${_idfile##*/}"
    _key="${_key%.zellij_id}"
    [ -f "$ZELLIJ_TMUX_SHIM_STATE/${_key}.pid" ] || rm -f "$_idfile"
done

# Remove stale env snapshot and lock from prior sessions
rm -f "$ZELLIJ_TMUX_SHIM_STATE/parent.env"
rm -rf "$ZELLIJ_TMUX_SHIM_STATE/next_id.lock"

export ZELLIJ_TMUX_SHIM_ACTIVE=1
