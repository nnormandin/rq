# Add to .bashrc: source ~/claude-research/aliases.sh

export CLAUDE_RESEARCH_DIR="$HOME/claude-research"

alias task="bash $CLAUDE_RESEARCH_DIR/task.sh"
alias approve="bash $CLAUDE_RESEARCH_DIR/task.sh approve"
alias reject="bash $CLAUDE_RESEARCH_DIR/task.sh reject"
alias suggested="bash $CLAUDE_RESEARCH_DIR/task.sh suggested"
alias launch="bash $CLAUDE_RESEARCH_DIR/launch.sh"
alias rollup="bash $CLAUDE_RESEARCH_DIR/task.sh rollup"
alias archive="bash $CLAUDE_RESEARCH_DIR/task.sh archive"
alias stuck="bash $CLAUDE_RESEARCH_DIR/task.sh stuck"
alias rerun="bash $CLAUDE_RESEARCH_DIR/task.sh rerun"

idea() {
  bash "$CLAUDE_RESEARCH_DIR/task.sh" add-active "$1" "${2:-#i}"
}

rgrep() {
  grep -rn --include="*.md" --include="*.py" --include="*.ipynb" "$@" "$CLAUDE_RESEARCH_DIR/tasks/"
}

_find_research_pane() {
  for pane_id in $(tmux list-panes -t rq -F '#{pane_id}'); do
    role=$(tmux show-options -p -t "$pane_id" -v @role 2>/dev/null)
    if [ "$role" = "research" ]; then
      echo "$pane_id"
      return
    fi
  done
}

research() {
  local text="$1"
  local output
  output=$(bash "$CLAUDE_RESEARCH_DIR/task.sh" add-active "$text" "#i")
  local num=$(echo "$output" | grep -oP '#\K[0-9]{3}')
  local task_dir=$(bash "$CLAUDE_RESEARCH_DIR/task.sh" dir "$num")

  local target=$(_find_research_pane)
  if [ -z "$target" ]; then
    echo "No research pane found. Is the tmux session running?"
    return 1
  fi

  local content=$(tmux capture-pane -t "$target" -p | tr -d '[:space:]')
  if [ -z "$content" ]; then
    tmux send-keys -t "$target" "cd $task_dir" Enter
    new_pane="$target"
  else
    new_pane=$(tmux split-window -t "$target" -c "$task_dir" -P -F '#{pane_id}')
  fi

  tmux set-option -p -t "$new_pane" @role research
  tmux send-keys -t "$new_pane" "claude --dangerously-skip-permissions" Enter
  sleep 2
  tmux send-keys -t "$new_pane" "Research task #${num}: ${text}" Enter

  echo "Opened #${num} -> ${task_dir}"
}

resume() {
  local num="$1"
  local task_dir=$(bash "$CLAUDE_RESEARCH_DIR/task.sh" dir "$num")
  if [ -z "$task_dir" ]; then
    echo "No directory found for #${num}"
    return 1
  fi

  # Reset [>] back to [ ] if stuck
  bash "$CLAUDE_RESEARCH_DIR/task.sh" resume "$num"

  local target=$(_find_research_pane)
  if [ -z "$target" ]; then
    echo "No research pane found. Is the tmux session running?"
    return 1
  fi

  local content=$(tmux capture-pane -t "$target" -p | tr -d '[:space:]')
  if [ -z "$content" ]; then
    tmux send-keys -t "$target" "cd $task_dir" Enter
    new_pane="$target"
  else
    new_pane=$(tmux split-window -t "$target" -c "$task_dir" -P -F '#{pane_id}')
  fi

  tmux set-option -p -t "$new_pane" @role research
  tmux send-keys -t "$new_pane" "claude --dangerously-skip-permissions" Enter
  sleep 2

  local task_line=$(grep -E "^\- \[.\] ${num} " "$CLAUDE_RESEARCH_DIR/tasks.md" | head -1)
  local task_desc=$(echo "$task_line" | sed -E 's/^- \[.\] [0-9]{3} \[[0-9-]+\] //' | sed 's/ #\(auto\|interactive\)$//')

  tmux send-keys -t "$new_pane" "Resume task #${num}: ${task_desc}. Check existing files in this directory for prior work and pick up where the previous session left off." Enter

  echo "Resumed #${num} -> ${task_dir}"
}

report() {
  local num="$1"
  local f=$(find "$CLAUDE_RESEARCH_DIR/tasks/" -name "${num}_report.md" | head -1)
  if [ -n "$f" ]; then
    cat "$f"
  else
    echo "No report for #${num}"
  fi
}

# Generate end-of-day rollup using Haiku
daily() {
  local day="${1:-$(date +%Y-%m-%d)}"
  local rollup_file="${CLAUDE_RESEARCH_DIR}/rollups/${day}.md"
  mkdir -p "${CLAUDE_RESEARCH_DIR}/rollups"

  # Gather all reports from today
  local reports=""
  for f in $(find "$CLAUDE_RESEARCH_DIR/tasks/" -name "*_summary.md" -newermt "$day 00:00" ! -newermt "$day 23:59:59" 2>/dev/null); do
    reports+="$(cat "$f")"$'\n\n'
  done

  if [ -z "$reports" ]; then
    echo "No completed research for ${day}."
    return
  fi

  claude --dangerously-skip-permissions --model claude-haiku-4-5-20251001 -p "
Write a concise daily research rollup for ${day}. Group by theme. Highlight key findings and open questions.

Completed research summaries:
${reports}

Task queue status:
$(grep "\[${day}" "$CLAUDE_RESEARCH_DIR/tasks.md")
" > "$rollup_file"

  echo "Rollup -> ${rollup_file}"
  cat "$rollup_file"
}
