#!/usr/bin/env fish
#
# install.fish — Install the zellij-tmux-shim for fish
#
# Runs install.sh (which installs the shim itself) and also installs the
# autoloaded claude-zellij function into your fish config, so installing,
# updating and uninstalling are one command instead of a manual copy.
#
# Usage:
#   fish install.fish              # install, or update an existing install
#   fish install.fish --uninstall  # remove the shim and the function
#   fish install.fish --help

set -l script_dir (dirname (status filename))

set -l data_home $XDG_DATA_HOME
test -n "$data_home"; or set data_home $HOME/.local/share
set -l install_dir $data_home/zellij-tmux-shim

set -l fish_dir $__fish_config_dir
test -n "$fish_dir"; or set fish_dir $HOME/.config/fish
set -l func_dir $fish_dir/functions
set -l func $func_dir/claude-zellij.fish

set -l action install
for arg in $argv
    switch $arg
        case --help -h
            echo "Usage: fish install.fish [--uninstall]"
            echo
            echo "Options:"
            echo "  --uninstall   Remove the shim and the claude-zellij function"
            echo "  --help        Show this help message"
            echo
            echo "The shim installs to $install_dir"
            echo "The claude-zellij function installs to $func"
            exit 0
        case --uninstall
            set action uninstall
        case '*'
            echo "install.fish: unknown option: $arg" >&2
            echo "Try 'fish install.fish --help'." >&2
            exit 2
    end
end

if test $action = uninstall
    if test -f $func
        rm -f $func; and echo "Removed $func"
    end
    bash $script_dir/install.sh --uninstall --quiet; or exit $status
    echo
    echo "If you added the always-on snippet to config.fish, remove it too."
    exit 0
end

# Install, or update over an existing install.
bash $script_dir/install.sh --quiet; or exit $status

mkdir -p $func_dir; and cp $install_dir/functions/claude-zellij.fish $func; or exit $status
echo "Installed the claude-zellij function to $func"
echo
echo "Nothing runs at shell startup: fish autoloads the function on first use."
echo "Inside zellij, use it in place of 'claude':"
echo
echo "    claude-zellij                 # teammates spawn as zellij panes"
echo "    claude-zellij --resume        # arguments pass straight through"
echo
echo "Outside zellij it runs the real claude untouched. To update later, pull"
echo "and re-run this script; to remove everything, 'fish install.fish --uninstall'."
