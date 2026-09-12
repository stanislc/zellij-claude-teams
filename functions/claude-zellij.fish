# claude-zellij.fish — Run Claude Code with the zellij-tmux-shim, on demand.
#
# Drop this file into ~/.config/fish/functions/ (fish autoloads it on first
# use, so nothing runs at shell startup). Then:
#
#   claude-zellij                # inside zellij: shim active, teammates get panes
#   claude-zellij --resume       # all arguments pass straight through to claude
#
# Outside zellij the real binary runs untouched. Inside zellij, the shim is
# activated in a child fish that immediately execs claude with
# CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 (Claude Code gates agent teams behind
# it) and --teammate-mode tmux (the default since Claude Code 2.1.179 is
# in-process, which never touches tmux). Your interactive shell never carries
# the fake $TMUX, a shadowed `tmux` on PATH, or the teams flag. Your own
# arguments come last, so they override the injected flag.
# Use this instead of the config.fish snippet if you'd rather not have every
# zellij shell activated.
#
# Prefer it to be transparent? That's your call, in your own config:
#   alias claude=claude-zellij

function claude-zellij --wraps claude --description 'Claude Code with the zellij-tmux-shim (when inside zellij)'
    set -l bin (command -s claude)
    if test -z "$bin"
        echo "claude-zellij: claude: command not found" >&2
        return 127
    end

    # Not in zellij: plain claude.
    if test -z "$ZELLIJ"
        $bin $argv
        return
    end

    # Flags that make Claude Code spawn teammates through (our) tmux.
    set -l teams_flags --teammate-mode tmux

    # Already activated (e.g. via the config.fish snippet): just enable teams.
    if test -n "$ZELLIJ_TMUX_SHIM_ACTIVE"
        env CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 $bin $teams_flags $argv
        return
    end

    set -l data_home $XDG_DATA_HOME
    test -n "$data_home"; or set data_home $HOME/.local/share
    set -l activate $data_home/zellij-tmux-shim/activate.fish
    if not test -f $activate
        echo "claude-zellij: $activate not found — run install.sh first; starting claude without the shim" >&2
        $bin $argv
        return
    end

    # Activate in a throwaway child fish and exec claude from there. The child
    # exits with claude's status; this shell's environment is untouched.
    fish --no-config -c 'source $argv[1]; and set -gx CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1; and exec $argv[2] $argv[3..-1]' -- $activate $bin $teams_flags $argv
end
