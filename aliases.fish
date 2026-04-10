# Source this file: source ~/claude-research/aliases.fish
# Or add to ~/.config/fish/config.fish: source ~/claude-research/aliases.fish

set -gx CLAUDE_RESEARCH_DIR "$HOME/claude-research"

alias task="bash $CLAUDE_RESEARCH_DIR/task.sh"
alias approve="bash $CLAUDE_RESEARCH_DIR/task.sh approve"
alias reject="bash $CLAUDE_RESEARCH_DIR/task.sh reject"
alias suggested="bash $CLAUDE_RESEARCH_DIR/task.sh suggested"
alias launch="bash $CLAUDE_RESEARCH_DIR/launch.sh"
alias rollup="bash $CLAUDE_RESEARCH_DIR/task.sh rollup"
alias archive="bash $CLAUDE_RESEARCH_DIR/task.sh archive"
alias stuck="bash $CLAUDE_RESEARCH_DIR/task.sh stuck"
alias rerun="bash $CLAUDE_RESEARCH_DIR/task.sh rerun"

function idea -d "Add an interactive research task"
    set -l tag (test -n "$argv[2]" && echo "$argv[2]" || echo "#i")
    bash "$CLAUDE_RESEARCH_DIR/task.sh" add-active "$argv[1]" "$tag"
end

function rgrep -d "Search across all research files"
    grep -rn --include="*.md" --include="*.py" --include="*.ipynb" $argv "$CLAUDE_RESEARCH_DIR/tasks/"
end

function _find_research_pane
    for pane_id in (tmux list-panes -t rq -F '#{pane_id}' 2>/dev/null)
        set -l role (tmux show-options -p -t "$pane_id" -v @role 2>/dev/null)
        if test "$role" = "research"
            echo "$pane_id"
            return
        end
    end
end

function research -d "Open an interactive research session in tmux"
    set -l text "$argv[1]"
    set -l output (bash "$CLAUDE_RESEARCH_DIR/task.sh" add-active "$text" "#i")
    set -l num (echo "$output" | grep -oP '#\K[0-9]{3}')
    set -l task_dir (bash "$CLAUDE_RESEARCH_DIR/task.sh" dir "$num")

    set -l target (_find_research_pane)
    if test -z "$target"
        echo "No research pane found. Is the tmux session running? (run: bash ~/claude-research/start.sh)"
        return 1
    end

    set -l content (tmux capture-pane -t "$target" -p 2>/dev/null | tr -d '[:space:]')
    if test -z "$content"
        tmux send-keys -t "$target" "cd $task_dir" Enter
        set new_pane "$target"
    else
        set new_pane (tmux split-window -t "$target" -c "$task_dir" -P -F '#{pane_id}')
    end

    tmux set-option -p -t "$new_pane" @role research
    tmux send-keys -t "$new_pane" "claude --dangerously-skip-permissions" Enter
    sleep 2
    tmux send-keys -t "$new_pane" "Research task #$num: $text" Enter

    echo "Opened #$num -> $task_dir"
end

function resume -d "Resume a stuck or incomplete task in tmux"
    set -l num "$argv[1]"
    set -l task_dir (bash "$CLAUDE_RESEARCH_DIR/task.sh" dir "$num")
    if test -z "$task_dir"
        echo "No directory found for #$num"
        return 1
    end

    # Reset [>] back to [ ] if stuck
    bash "$CLAUDE_RESEARCH_DIR/task.sh" resume "$num"

    set -l target (_find_research_pane)
    if test -z "$target"
        echo "No research pane found. Is the tmux session running?"
        return 1
    end

    set -l content (tmux capture-pane -t "$target" -p 2>/dev/null | tr -d '[:space:]')
    if test -z "$content"
        tmux send-keys -t "$target" "cd $task_dir" Enter
        set new_pane "$target"
    else
        set new_pane (tmux split-window -t "$target" -c "$task_dir" -P -F '#{pane_id}')
    end

    tmux set-option -p -t "$new_pane" @role research
    tmux send-keys -t "$new_pane" "claude --dangerously-skip-permissions" Enter
    sleep 2

    set -l task_line (grep -E "^- \\[.\\] $num " "$CLAUDE_RESEARCH_DIR/tasks.md" | head -1)
    set -l task_desc (echo "$task_line" | sed -E 's/^- \[.\] [0-9]{3} \[[0-9-]+\] //' | sed 's/ #\(auto\|interactive\)$//')

    tmux send-keys -t "$new_pane" "Resume task #$num: $task_desc. Check existing files in this directory for prior work and pick up where the previous session left off." Enter

    echo "Resumed #$num -> $task_dir"
end

function report -d "Read a task report by number"
    set -l num "$argv[1]"
    set -l f (find "$CLAUDE_RESEARCH_DIR/tasks/" -name "$num"_report.md | head -1)
    if test -n "$f"
        cat "$f"
    else
        echo "No report for #$num"
    end
end

function daily -d "Generate end-of-day rollup using Haiku"
    set -l day (test -n "$argv[1]" && echo "$argv[1]" || date +%Y-%m-%d)
    set -l rollup_file "$CLAUDE_RESEARCH_DIR/rollups/$day.md"
    mkdir -p "$CLAUDE_RESEARCH_DIR/rollups"

    set -l reports ""
    for f in (find "$CLAUDE_RESEARCH_DIR/tasks/" -name "*_summary.md" -newermt "$day 00:00" ! -newermt "$day 23:59:59" 2>/dev/null)
        set reports "$reports"(cat "$f")"\n\n"
    end

    if test -z "$reports"
        echo "No completed research for $day."
        return
    end

    claude --dangerously-skip-permissions --model claude-haiku-4-5-20251001 -p "
Write a concise daily research rollup for $day. Group by theme. Highlight key findings and open questions.

Completed research summaries:
$reports

Task queue status:
"(grep "\[$day" "$CLAUDE_RESEARCH_DIR/tasks.md")"
" > "$rollup_file"

    echo "Rollup -> $rollup_file"
    cat "$rollup_file"
end
