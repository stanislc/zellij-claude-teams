#!/usr/bin/env bash
# install.sh — Install the zellij-tmux-shim
#
# This script copies the shim files to the XDG-compliant install directory
# and prints shell activation snippets.
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
    echo "Add ONE of the following snippets to your shell config:"
    echo ""
    echo "=== For ~/.bashrc or ~/.bash_profile ==="
    cat <<'BASH_SNIPPET'
# --- Zellij-tmux-shim (Claude Code agent teams in zellij) ---
if [ -n "$ZELLIJ" ]; then
    _shim="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim/activate.sh"
    [ -f "$_shim" ] && . "$_shim"
    unset _shim
fi
BASH_SNIPPET
    echo ""
    echo "=== For ~/.zshrc ==="
    cat <<'ZSH_SNIPPET'
# --- Zellij-tmux-shim (Claude Code agent teams in zellij) ---
if [[ -n "$ZELLIJ" ]]; then
    _shim="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim/activate.sh"
    [[ -f "$_shim" ]] && source "$_shim"
    unset _shim
fi
ZSH_SNIPPET
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
    echo "Remember to remove the activation snippet from your shell config."
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
