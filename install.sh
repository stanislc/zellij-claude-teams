#!/usr/bin/env bash
# install.sh — Install the zellij-tmux-shim
#
# This script copies the shim files to the XDG-compliant install directory
# and offers to add shell activation to ~/.zshrc or ~/.bashrc (asks first).
#
# Usage:
#   bash install.sh          # Install from the repo directory
#   bash install.sh --help   # Show usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim"
QUIET=0

usage() {
    cat <<'EOF'
Usage: bash install.sh [--uninstall] [--quiet] [--version]

Options:
  --uninstall   Remove the shim and print deactivation instructions
  --quiet       Skip shell activation instructions
  --version     Print the project release version without installing
  --help        Show this help message

The shim installs to ${XDG_DATA_HOME:-~/.local/share}/zellij-tmux-shim/
EOF
}

RC_BEGIN="# >>> zellij-tmux-shim >>>"
RC_END="# <<< zellij-tmux-shim <<<"

# POSIX syntax, so the same snippet works in Bash and zsh.
rc_snippet() {
    cat <<'SNIPPET'
# Zellij-tmux-shim (Claude Code agent teams in zellij)
if [ -n "${ZELLIJ:-}" ]; then
    _shim="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim/activate.sh"
    [ -f "$_shim" ] && . "$_shim"
    unset _shim
fi
SNIPPET
}

# Startup file of the user's login shell; empty when unsupported (e.g. fish).
shell_rc() {
    case "${SHELL##*/}" in
        zsh) printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) printf '%s\n' "$HOME/.bashrc" ;;
    esac
}

# Ask on a terminal only; anything but y/yes (including no terminal) is no.
ask_yes() {
    local reply
    [ -t 0 ] || return 1
    printf '%s [y/N] ' "$1"
    read -r reply || return 1
    case "$reply" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

rc_has_block() {
    [ -f "$1" ] && grep -qxF "$RC_BEGIN" "$1"
}

# Returns 0 when the snippet is (now) in the rc file, 1 when the user should add it.
offer_rc_edit() {
    local rc
    rc=$(shell_rc)
    [ -n "$rc" ] || return 1
    if rc_has_block "$rc"; then
        echo "Activation is already in ${rc}."
        return 0
    fi
    ask_yes "Add activation to ${rc}?" || return 1
    if ! { printf '\n%s\n' "$RC_BEGIN"; rc_snippet; printf '%s\n' "$RC_END"; } >> "$rc"; then
        echo "install.sh: could not write ${rc}" >&2
        return 1
    fi
    echo "Added activation to ${rc}. Restart your shell inside zellij."
}

# Remove only our marked block; write back in place so symlinked dotfiles survive.
offer_rc_removal() {
    local rc tmp
    rc=$(shell_rc)
    [ -n "$rc" ] && rc_has_block "$rc" || return 1
    ask_yes "Remove activation from ${rc}?" || return 1
    tmp=$(mktemp) || return 1
    # Drop the first complete block plus the blank line install put before it.
    # Without a matching end marker awk fails and the file is left untouched.
    if awk -v b="$RC_BEGIN" -v e="$RC_END" '
        inblk { if ($0 == e) { inblk = 0; found = 1; hold = 0 }; next }
        $0 == b && !found { inblk = 1; next }
        hold { print ""; hold = 0 }
        $0 == "" { hold = 1; next }
        { print }
        END { if (hold) print ""; exit (found ? 0 : 3) }
    ' "$rc" > "$tmp" && cat "$tmp" > "$rc"; then
        rm -f "$tmp"
        echo "Removed activation from ${rc}."
        return 0
    fi
    rm -f "$tmp"
    echo "install.sh: left ${rc} unchanged (end marker missing or write failed)" >&2
    return 1
}

do_install() {
    echo "Installing zellij-tmux-shim to ${INSTALL_DIR}..."

    mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/functions"

    # Copy scripts
    cp "${SCRIPT_DIR}/activate.sh"   "${INSTALL_DIR}/activate.sh"
    cp "${SCRIPT_DIR}/deactivate.sh" "${INSTALL_DIR}/deactivate.sh"
    cp "${SCRIPT_DIR}/activate.fish" "${INSTALL_DIR}/activate.fish"
    cp "${SCRIPT_DIR}/deactivate.fish" "${INSTALL_DIR}/deactivate.fish"
    cp "${SCRIPT_DIR}/functions/claude-zellij.fish" "${INSTALL_DIR}/functions/claude-zellij.fish"
    cp "${SCRIPT_DIR}/VERSION"       "${INSTALL_DIR}/VERSION"
    cp "${SCRIPT_DIR}/bin/tmux"      "${INSTALL_DIR}/bin/tmux"
    cp "${SCRIPT_DIR}/bin/zellij-pane-wrapper" "${INSTALL_DIR}/bin/zellij-pane-wrapper"

    # Ensure executables
    chmod +x "${INSTALL_DIR}/bin/tmux"
    chmod +x "${INSTALL_DIR}/bin/zellij-pane-wrapper"

    echo "Installed successfully."
    if [ "$QUIET" -eq 1 ]; then
        return 0
    fi
    echo ""
    if offer_rc_edit; then
        return 0
    fi
    echo "Add this snippet to your ~/.bashrc, ~/.bash_profile or ~/.zshrc:"
    echo ""
    rc_snippet
    echo ""
    echo "Then restart your shell inside zellij."
}

do_uninstall() {
    echo "Uninstalling zellij-tmux-shim..."

    # Source deactivate if currently active
    if [ -n "${ZELLIJ_TMUX_SHIM_ACTIVE:-}" ]; then
        # shellcheck disable=SC1091
        . "${INSTALL_DIR}/deactivate.sh" 2>/dev/null || true
    fi

    rm -rf "${INSTALL_DIR}"
    echo "Removed ${INSTALL_DIR}"
    if [ "$QUIET" -eq 1 ]; then
        return 0
    fi
    echo ""
    offer_rc_removal || echo "Remember to remove the activation snippet from your shell config."
}

ACTION=install
SHOW_HELP=0
SHOW_VERSION=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --uninstall) ACTION=uninstall ;;
        --quiet|-q) QUIET=1 ;;
        --version) SHOW_VERSION=1 ;;
        --help|-h) SHOW_HELP=1 ;;
        *)
            echo "install.sh: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$SHOW_HELP" -eq 1 ]; then
    usage
elif [ "$SHOW_VERSION" -eq 1 ]; then
    printf 'zellij-claude-teams %s\n' "$(cat "${SCRIPT_DIR}/VERSION")"
elif [ "$ACTION" = uninstall ]; then
    do_uninstall
else
    do_install
fi
