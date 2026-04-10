#!/bin/bash
# launch.sh — batch launcher with post-completion Haiku summary
BASE="${CLAUDE_RESEARCH_DIR:-$HOME/claude-research}"
TASKS_FILE="${BASE}/tasks.md"
TASKS_DIR="${BASE}/tasks"
CLAUDE_MD="${BASE}/CLAUDE.md"
LOG="${BASE}/batch.log"

preamble=$(cat "$CLAUDE_MD" 2>/dev/null || echo "")

# Summarize a completed task using a fast model
summarize_task() {
  local num="$1"
  local task_dir="$2"
  local report="${task_dir}/${num}_report.md"

  [ ! -f "$report" ] && return

  # Use Haiku for a quick title + one-liner
  summary=$(claude --dangerously-skip-permissions --model claude-haiku-4-5-20251001 -p "
Read this research report and output ONLY two lines:
Line 1: A concise, descriptive title (max 60 chars)
Line 2: A one-sentence summary of the key finding

$(head -c 4000 "$report")
" 2>/dev/null)

  if [ -n "$summary" ]; then
    title=$(echo "$summary" | head -1)
    one_liner=$(echo "$summary" | sed -n '2p')

    # Write summary file
    echo -e "# ${title}\n\n${one_liner}" > "${task_dir}/${num}_summary.md"

    # Append summary line under the task in tasks.md
    escaped_title=$(echo "      -> ${title}: ${one_liner}" | sed 's/[&/\]/\\&/g')
    flock "$TASKS_FILE" sed -i "/^\- \[x\] ${num} /a\\${escaped_title}" "$TASKS_FILE"

    echo "$(date '+%Y-%m-%d %H:%M:%S') [summary] #${num}: ${title}" >> "$LOG"
  fi
}

count=0
while IFS= read -r line; do
  [[ ! "$line" =~ ^\-\ \[\ \]\ ([0-9]{3})\ \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\ (.+)\ \#auto$ ]] && continue
  num="${BASH_REMATCH[1]}"
  task="${BASH_REMATCH[2]}"

  task_dir=$(find "$TASKS_DIR" -maxdepth 1 -type d -name "${num}_*" | head -1)
  if [ -z "$task_dir" ]; then
    slug=$(echo "$task" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_' | head -c 40)
    task_dir="${TASKS_DIR}/${num}_${slug}"
    mkdir -p "${task_dir}/${num}_data"
  fi

  flock "$TASKS_FILE" sed -i "s|^\- \[ \] ${num} |- [>] ${num} |" "$TASKS_FILE"

  (
    echo "$(date '+%Y-%m-%d %H:%M:%S') [start] #${num}: ${task}" >> "$LOG"

    cd "$task_dir"
    claude --dangerously-skip-permissions -p "${preamble}

TASK #${num}: ${task}

Working directory: ${task_dir}
Shared utilities: ${BASE}/shared/

File naming: prefix all files with ${num}_ (e.g. ${num}_research.ipynb, ${num}_report.md)
Data subdirectory: ${num}_data/

When identifying follow-up research directions, append to ${TASKS_FILE}:
flock ${TASKS_FILE} bash -c 'num=\$(printf \"%03d\" \$(( \$(grep -oP \"^- \\[.\\] \\K[0-9]{3}\" ${TASKS_FILE} | sort -n | tail -1 | sed \"s/^0*//\") + 1 ))); ts=\$(date +\"%Y-%m-%d\"); echo \"- [?] \${num} [\${ts}] <research question> #auto\" >> ${TASKS_FILE}'

Write your full findings to ${num}_report.md in this directory.
When finished, print TASK_COMPLETE as the last line of output.
" > "${task_dir}/${num}_output.log" 2>&1

    flock "$TASKS_FILE" sed -i "s|^\- \[>\] ${num} |- [x] ${num} |" "$TASKS_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [done] #${num}" >> "$LOG"

    # Haiku summary pass
    summarize_task "$num" "$task_dir"

    # Auto-archive completed task to ## Done
    bash "${BASE}/task.sh" archive > /dev/null 2>&1
  ) &

  echo "[launch] #${num}: ${task} (PID $!)"
  ((count++))
done < "$TASKS_FILE"

if [ "$count" -eq 0 ]; then
  echo "No approved #auto tasks." | tee -a "$LOG"
else
  echo "Launched ${count} tasks." | tee -a "$LOG"
fi
