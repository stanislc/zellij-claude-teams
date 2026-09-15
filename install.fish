#!/usr/bin/env fish
# Install or remove the shim plus its one fish autoload function.

set -l script_dir (command dirname (status filename))
set -l data_home $XDG_DATA_HOME
test -n "$data_home"; or set data_home $HOME/.local/share
set -l install_dir $data_home/zellij-tmux-shim
set -l config_home $XDG_CONFIG_HOME
test -n "$config_home"; or set config_home $HOME/.config
set -l function_dir $config_home/fish/functions
set -l function_path $function_dir/claude-zellij.fish
set -l action install
set -l quiet 0
set -l show_help 0
set -l show_version 0

for arg in $argv
    switch $arg
        case --uninstall
            set action uninstall
        case --quiet -q
            set quiet 1
        case --version
            set show_version 1
        case --help -h
            set show_help 1
        case '*'
            echo "install.fish: unknown option: $arg" >&2
            echo "Try 'fish install.fish --help'." >&2
            exit 2
    end
end

if test $show_help -eq 1
    echo "Usage: fish install.fish [--uninstall] [--quiet] [--version]"
    echo
    echo "Options:"
    echo "  --uninstall   Remove the shim and the claude-zellij function"
    echo "  --quiet       Only report errors"
    echo "  --version     Print the project release version without installing"
    echo "  --help        Show this help message"
    exit 0
else if test $show_version -eq 1
    command bash "$script_dir/install.sh" --version
    exit $status
end

if test "$action" = uninstall
    if test -e "$function_path"; or test -L "$function_path"
        command rm -f "$function_path"; or exit $status
        test $quiet -eq 1; or echo "Removed $function_path"
    end
    command bash "$script_dir/install.sh" --uninstall --quiet; or exit $status
    exit 0
end

command bash "$script_dir/install.sh" --quiet; or exit $status
command mkdir -p "$function_dir"; or exit $status
if test -d "$function_path"
    echo "install.fish: cannot replace function path because it is a directory: $function_path" >&2
    exit 1
end
command cp "$install_dir/functions/claude-zellij.fish" "$function_path"; or exit $status
test $quiet -eq 1; or echo "Installed the claude-zellij function to $function_path"
