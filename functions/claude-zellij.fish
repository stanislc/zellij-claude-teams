# Run Claude Code with the zellij tmux shim in an isolated child fish.
function claude-zellij --wraps claude --description 'Claude Code with the zellij-tmux-shim (when inside zellij)'
    set -l fish_bin (status fish-path)
    set -l claude_bin (command -s claude)
    if test -z "$claude_bin"
        echo "claude-zellij: claude: command not found" >&2
        return 127
    end
    if test -z "$ZELLIJ"
        command "$claude_bin" $argv
        return $status
    end

    set -l explicit_mode 0
    set -l before_separator 1
    set -l expect_mode_value 0
    for arg in $argv
        if test $before_separator -eq 0
            continue
        end
        if test "$arg" = --
            set before_separator 0
            continue
        end
        if test $expect_mode_value -eq 1
            set explicit_mode 1
            set expect_mode_value 0
            continue
        end
        if test "$arg" = --teammate-mode
            set expect_mode_value 1
        else if string match -q -- '--teammate-mode=*' "$arg"
            set explicit_mode 1
        end
    end
    set -l launch_args
    if test $explicit_mode -eq 0
        set launch_args --teammate-mode tmux
    end
    set -a launch_args $argv

    set -l data_home $XDG_DATA_HOME
    test -n "$data_home"; or set data_home $HOME/.local/share
    set -l activate "$data_home/zellij-tmux-shim/activate.fish"
    if test -n "$ZELLIJ_TMUX_SHIM_ACTIVE"; and test -n "$ZELLIJ_TMUX_SHIM_DIR"
        set activate "$ZELLIJ_TMUX_SHIM_DIR/activate.fish"
    end
    if not test -f "$activate"
        echo "claude-zellij: $activate not found; run install.fish first; starting claude without the shim" >&2
        command "$claude_bin" $argv
        return $status
    end

    "$fish_bin" --no-config -c 'source $argv[1]; or exit $status; set -gx CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1; exec $argv[2] $argv[3..-1]' -- "$activate" "$claude_bin" $launch_args
end
