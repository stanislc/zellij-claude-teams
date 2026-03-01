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

usage() {
    cat <<'EOF'
Usage: bash install.sh [--uninstall]

Options:
  --uninstall   Remove the shim and print deactivation instructions
  --help        Show this help message

The shim installs to ${XDG_DATA_HOME:-~/.local/share}/zellij-tmux-shim/
EOF
}

do_install() {
    echo "Installing zellij-tmux-shim to ${INSTALL_DIR}..."

    mkdir -p "${INSTALL_DIR}/bin"

    # Copy scripts
    cp "${SCRIPT_DIR}/activate.sh"   "${INSTALL_DIR}/activate.sh"
    cp "${SCRIPT_DIR}/deactivate.sh" "${INSTALL_DIR}/deactivate.sh"
    cp "${SCRIPT_DIR}/bin/tmux"      "${INSTALL_DIR}/bin/tmux"
    cp "${SCRIPT_DIR}/bin/zellij-pane-wrapper" "${INSTALL_DIR}/bin/zellij-pane-wrapper"

    # Ensure executables
    chmod +x "${INSTALL_DIR}/bin/tmux"
    chmod +x "${INSTALL_DIR}/bin/zellij-pane-wrapper"

    echo "Installed successfully."
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
    echo ""
    echo "Remember to remove the activation snippet from your shell config."
}

case "${1:-}" in
    --help|-h)
        usage
        ;;
    --uninstall)
        do_uninstall
        ;;
    *)
        do_install
        ;;
esac
