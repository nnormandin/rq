#!/bin/bash
# start.sh — single-window tmux layout for 37" monitor
# Left 75%: research panes (tiled, grow as you add sessions)
# Right 25%: tasks.md | reports | batch log (stacked)
BASE="${CLAUDE_RESEARCH_DIR:-$HOME/claude-research}"
SESSION="rq"

tmux kill-session -t "$SESSION" 2>/dev/null
touch "$BASE/batch.log"

# Pane 0: research area (left)
tmux new-session -d -s "$SESSION" -n "research" -c "$BASE"

# Pane 1: monitoring sidebar (right 25%)
tmux split-window -t "$SESSION" -h -l 25% -c "$BASE"

# Pane 1 → tasks.md live view (top of sidebar)
tmux send-keys -t "$SESSION.1" "watch -n 2 '
  running=\$(grep -cF -- \"- [>]\" tasks.md 2>/dev/null || echo 0)
  queued=\$(grep -cF -- \"- [ ]\" tasks.md 2>/dev/null || echo 0)
  done=\$(grep -cF -- \"- [x]\" tasks.md 2>/dev/null || echo 0)
  suggested=\$(grep -cF -- \"- [?]\" tasks.md 2>/dev/null || echo 0)
  printf \"[R] %s run | [Q] %s queue | [D] %s done | [S] %s new\\n\\n\" \$running \$queued \$done \$suggested
  sed \"/^## Done/,\\\$d\" tasks.md
'" Enter

# Pane 2: reports list (middle of sidebar)
tmux split-window -t "$SESSION.1" -v -l 66% -c "$BASE"
tmux send-keys -t "$SESSION.2" "watch -n 5 'echo \"=== Recent Reports ===\"; echo; find tasks/ -name \"*_report.md\" -printf \"%T@ %Tc  %p\n\" 2>/dev/null | sort -rn | head -15 | cut -d\" \" -f2-'" Enter

# Pane 3: batch log (bottom of sidebar)
tmux split-window -t "$SESSION.2" -v -l 50% -c "$BASE"
tmux send-keys -t "$SESSION.3" "tail -f $BASE/batch.log" Enter

# Tag panes so research() only splits within research area
tmux set-option -p -t "$SESSION.0" @role research
tmux set-option -p -t "$SESSION.1" @role monitor
tmux set-option -p -t "$SESSION.2" @role monitor
tmux set-option -p -t "$SESSION.3" @role monitor

# Focus research pane
tmux select-pane -t "$SESSION.0"

tmux attach -t "$SESSION"
