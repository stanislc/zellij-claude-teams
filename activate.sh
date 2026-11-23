#!/usr/bin/env bash
# Source this file to activate the zellij-tmux-shim.
# Usage: source activate.sh

__zellij_tmux_shim_prepend_path() {
    local _zct_bin="$1"
    local _zct_rest="${PATH-}"
    local _zct_component _zct_clean="" _zct_first=1 _zct_more
    while :; do
        case "$_zct_rest" in
            *:*) _zct_component=${_zct_rest%%:*}; _zct_rest=${_zct_rest#*:}; _zct_more=1 ;;
            *) _zct_component=$_zct_rest; _zct_more=0 ;;
        esac
        if [ "$_zct_component" != "$_zct_bin" ]; then
            if [ "$_zct_first" -eq 1 ]; then
                _zct_clean=$_zct_component
                _zct_first=0
            else
                _zct_clean="${_zct_clean}:${_zct_component}"
            fi
        fi
        [ "$_zct_more" -eq 1 ] || break
    done
    if [ "$_zct_first" -eq 1 ]; then PATH=$_zct_bin; else PATH="${_zct_bin}:${_zct_clean}"; fi
    export PATH
}

__zellij_tmux_shim_activate() {
    local _zct_data_home _zct_runtime_base _zct_root _zct_session _zct_state _zct_uid
    local _zct_shim_dir _zct_real_tmux _zct_path_present _zct_path_value
    local _zct_tmux_present _zct_tmux_value _zct_pane_present _zct_pane_value
    if [ -z "${ZELLIJ:-}" ]; then
        echo "zellij-tmux-shim: not inside zellij, skipping activation" >&2
        return 1
    fi

    _zct_data_home=${XDG_DATA_HOME:-${HOME}/.local/share}
    _zct_shim_dir="${_zct_data_home}/zellij-tmux-shim"
    if [ -n "${ZELLIJ_TMUX_SHIM_ACTIVE:-}" ]; then
        __zellij_tmux_shim_prepend_path "${ZELLIJ_TMUX_SHIM_DIR:-$_zct_shim_dir}/bin"
        return 0
    fi

    _zct_runtime_base=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
    _zct_uid=$(PATH=/usr/bin:/bin command id -u) || return 1
    _zct_root="${_zct_runtime_base}/zellij-tmux-shim-${_zct_uid}"
    _zct_session=${ZELLIJ_SESSION_NAME:-default}
    case "$_zct_session" in
        ''|.|..|*/*) echo "zellij-tmux-shim: ERROR: invalid zellij session name" >&2; return 1 ;;
    esac
    _zct_state="${_zct_root}/${_zct_session}"

    if [ "${PATH+x}" = x ]; then _zct_path_present=1; _zct_path_value=$PATH; else _zct_path_present=0; _zct_path_value=; fi
    if [ "${TMUX+x}" = x ]; then _zct_tmux_present=1; _zct_tmux_value=$TMUX; else _zct_tmux_present=0; _zct_tmux_value=; fi
    if [ "${TMUX_PANE+x}" = x ]; then _zct_pane_present=1; _zct_pane_value=$TMUX_PANE; else _zct_pane_present=0; _zct_pane_value=; fi
    _zct_real_tmux=$(command -v tmux 2>/dev/null || true)

    # Complete all state checks and initialization before exporting activation state.
    (
        PATH=/usr/bin:/bin
        export PATH
        umask 077
        if [ -L "$_zct_root" ]; then
            echo "zellij-tmux-shim: ERROR: state root is a symlink, refusing to activate" >&2
            exit 1
        fi
        if ! mkdir -p "$_zct_root" || ! chmod 700 "$_zct_root"; then
            echo "zellij-tmux-shim: ERROR: failed to create or secure state root" >&2
            exit 1
        fi
        _zct_owner=$(stat -c '%u' "$_zct_root" 2>/dev/null || stat -f '%u' "$_zct_root" 2>/dev/null)
        if [ "$_zct_owner" != "$_zct_uid" ]; then
            echo "zellij-tmux-shim: ERROR: state root not owned by current user" >&2
            exit 1
        fi
        if [ -L "$_zct_state" ]; then
            echo "zellij-tmux-shim: ERROR: session state is a symlink, refusing to activate" >&2
            exit 1
        fi
        if [ -e "$_zct_state" ] && [ ! -d "$_zct_state" ]; then
            echo "zellij-tmux-shim: ERROR: session state is not a directory" >&2
            exit 1
        fi
        if ! mkdir -p "$_zct_state" || ! chmod 700 "$_zct_state"; then
            echo "zellij-tmux-shim: ERROR: failed to create or secure session state" >&2
            exit 1
        fi
        _zct_owner=$(stat -c '%u' "$_zct_state" 2>/dev/null || stat -f '%u' "$_zct_state" 2>/dev/null)
        if [ "$_zct_owner" != "$_zct_uid" ]; then
            echo "zellij-tmux-shim: ERROR: session state not owned by current user" >&2
            exit 1
        fi
        if [ ! -e "$_zct_state/next_id" ]; then printf '1\n' > "$_zct_state/next_id" || exit 1; fi
        if [ ! -f "$_zct_state/next_id" ]; then
            echo "zellij-tmux-shim: ERROR: next_id is not a regular file" >&2
            exit 1
        fi
        if [ ! -e "$_zct_state/sessions" ]; then : > "$_zct_state/sessions" || exit 1; fi
        if [ ! -f "$_zct_state/sessions" ]; then
            echo "zellij-tmux-shim: ERROR: sessions is not a regular file" >&2
            exit 1
        fi

        _zct_pid_list="$_zct_state/.activate-pids.$$"
        find "$_zct_state" -maxdepth 1 -name '*.pid' -type f > "$_zct_pid_list" || exit 1
        _zct_has_live=0
        while IFS= read -r _zct_pidfile; do
            [ -n "$_zct_pidfile" ] || continue
            _zct_pid=$(cat "$_zct_pidfile" 2>/dev/null || true)
            case "$_zct_pid" in
                ''|0|0*|*[!0-9]*) _zct_live=0 ;;
                *) if kill -0 "$_zct_pid" 2>/dev/null; then _zct_live=1; else _zct_live=0; fi ;;
            esac
            if [ "$_zct_live" -eq 1 ]; then _zct_has_live=1; continue; fi
            _zct_key=${_zct_pidfile##*/}; _zct_key=${_zct_key%.pid}
            for _zct_ext in pid zellij_id fifo ready cmd named group title; do
                rm -f "$_zct_state/${_zct_key}.${_zct_ext}" || exit 1
            done
        done < "$_zct_pid_list"
        rm -f "$_zct_pid_list"

        _zct_id_list="$_zct_state/.activate-ids.$$"
        find "$_zct_state" -maxdepth 1 -name '*.zellij_id' -type f > "$_zct_id_list" || exit 1
        while IFS= read -r _zct_idfile; do
            [ -n "$_zct_idfile" ] || continue
            _zct_key=${_zct_idfile##*/}; _zct_key=${_zct_key%.zellij_id}
            [ -f "$_zct_state/${_zct_key}.pid" ] || rm -f "$_zct_idfile" || exit 1
        done < "$_zct_id_list"
        rm -f "$_zct_id_list"
        _zct_lock_live=0
        if [ -d "$_zct_state/next_id.lock" ] && [ ! -L "$_zct_state/next_id.lock" ]; then
            _zct_lock_pid=$(cat "$_zct_state/next_id.lock/pid" 2>/dev/null || true)
            case "$_zct_lock_pid" in
                ''|0|0*|*[!0-9]*) ;;
                *) if kill -0 "$_zct_lock_pid" 2>/dev/null; then _zct_lock_live=1; fi ;;
            esac
        fi
        if [ "$_zct_has_live" -eq 0 ] && [ "$_zct_lock_live" -eq 0 ]; then
            rm -f "$_zct_state/parent.env" || exit 1
        fi
    ) || return 1

    export ZELLIJ_TMUX_SHIM_DIR=$_zct_shim_dir
    export ZELLIJ_TMUX_SHIM_STATE=$_zct_state
    export ZELLIJ_TMUX_SHIM_REAL_TMUX=$_zct_real_tmux
    export ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT=$_zct_path_present
    export ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE=$_zct_path_value
    export ZELLIJ_TMUX_SHIM_ORIG_PATH=$_zct_path_value
    export ZELLIJ_TMUX_SHIM_ORIG_PATH_SET=$_zct_path_present
    export ZELLIJ_TMUX_SHIM_SAVED_TMUX_PRESENT=$_zct_tmux_present
    export ZELLIJ_TMUX_SHIM_SAVED_TMUX_VALUE=$_zct_tmux_value
    export ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_PRESENT=$_zct_pane_present
    export ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_VALUE=$_zct_pane_value
    __zellij_tmux_shim_prepend_path "$_zct_shim_dir/bin"
    export TMUX="zellij-shim:/tmp/zellij-shim,$$,0"
    export TMUX_PANE=%0
    export ZELLIJ_TMUX_SHIM_ACTIVE=1
}

if __zellij_tmux_shim_activate; then
    unset -f __zellij_tmux_shim_activate __zellij_tmux_shim_prepend_path
    return 0 2>/dev/null || exit 0
else
    unset -f __zellij_tmux_shim_activate __zellij_tmux_shim_prepend_path
    return 1 2>/dev/null || exit 1
fi
