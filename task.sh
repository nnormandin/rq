#!/bin/bash
# task.sh — task management CLI with timestamps
BASE="${CLAUDE_RESEARCH_DIR:-$HOME/claude-research}"
TASKS_FILE="${BASE}/tasks.md"
TASKS_DIR="${BASE}/tasks"

mkdir -p "$TASKS_DIR"

ts() { date +"%Y-%m-%d"; }

next_number() {
  local max=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^\-\ \[.\]\ ([0-9]{3})\  ]]; then
      num=$((10#${BASH_REMATCH[1]}))
      (( num > max )) && max=$num
    fi
  done < "$TASKS_FILE"
  printf "%03d" $((max + 1))
}

make_task_dir() {
  local num="$1"
  local text="$2"
  local slug=$(echo "$text" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_' | head -c 40)
  local dir="${TASKS_DIR}/${num}_${slug}"
  mkdir -p "${dir}/${num}_data"
  echo "$dir"
}

case "${1:-list}" in
  add)
    shift
    text="$1"; tag="${2:-#auto}"
    num=$(next_number)
    dir=$(make_task_dir "$num" "$text")
    flock "$TASKS_FILE" sed -i "/^## Suggested/a - [?] ${num} [$(ts)] ${text} ${tag}" "$TASKS_FILE"
    echo "Suggested #${num}: ${text} ${tag}"
    echo "  -> ${dir}"
    ;;

  add-active)
    shift
    text="$1"; tag="${2:-#interactive}"
    num=$(next_number)
    dir=$(make_task_dir "$num" "$text")
    flock "$TASKS_FILE" sed -i "/^## Active/a - [ ] ${num} [$(ts)] ${text} ${tag}" "$TASKS_FILE"
    echo "Added #${num}: ${text} ${tag}"
    echo "  -> ${dir}"
    ;;

  approve)
    shift
    if [ "$1" = "all" ]; then
      # Collect suggested tasks, ensure dirs exist
      lines=()
      while IFS= read -r line; do
        if [[ "$line" =~ ^\-\ \[\?\]\ ([0-9]{3})\  ]]; then
          num="${BASH_REMATCH[1]}"
          rest=$(echo "$line" | sed "s/^- \[?\] ${num} //")
          text=$(echo "$rest" | sed 's/ #\(auto\|interactive\)$//' | sed 's/^\[[0-9-]* [0-9:]*\] //')
          [ -d "${TASKS_DIR}/${num}_"* ] 2>/dev/null || make_task_dir "$num" "$text" > /dev/null
          lines+=("$(echo "$line" | sed 's/^- \[?\]/- [ ]/')")
        fi
      done < "$TASKS_FILE"
      # Remove all suggested lines, then insert them under ## Active
      flock "$TASKS_FILE" bash -c '
        sed -i "/^- \[?\]/d" "'"$TASKS_FILE"'"
        for line in "$@"; do
          escaped=$(echo "$line" | sed '\''s/[&/\]/\\&/g'\'')
          sed -i "/^## Active/a\\${escaped}" "'"$TASKS_FILE"'"
        done
      ' -- "${lines[@]}"
      echo "Approved all (${#lines[@]} tasks)."
    else
      num="$1"
      flock "$TASKS_FILE" bash -c "
        sed -i 's/^- \[?\] ${num} /- [ ] ${num} /' \"$TASKS_FILE\"
        line=\$(grep -F '- [ ] ${num} ' \"$TASKS_FILE\" | head -1)
        if [ -n \"\$line\" ]; then
          sed -i \"/^- \[ \] ${num} /d\" \"$TASKS_FILE\"
          escaped=\$(echo \"\$line\" | sed 's/[&/\\\\]/\\\\&/g')
          sed -i \"/^## Active/a\\\\\${escaped}\" \"$TASKS_FILE\"
        fi
      "
      echo "Approved #${num}"
    fi
    ;;

  reject)
    shift; num="$1"
    flock "$TASKS_FILE" sed -i "/^\- \[?\] ${num} /d" "$TASKS_FILE"
    echo "Rejected #${num}"
    ;;

  list)     cat "$TASKS_FILE" ;;
  suggested) grep -F -- '- [?]' "$TASKS_FILE" || echo "No pending suggestions." ;;
  running)  grep -F -- '- [>]' "$TASKS_FILE" || echo "Nothing running." ;;

  dir)
    shift; num="$1"
    find "$TASKS_DIR" -maxdepth 1 -type d -name "${num}_*" | head -1
    ;;

  archive)
    # Move all [x] lines (and their summary lines) from Active to Done
    if ! grep -qF -- '- [x]' "$TASKS_FILE"; then
      echo "Nothing to archive."
    else
      flock "$TASKS_FILE" awk '
        /^- \[x\] /    { done[++n]=$0; skip=1; next }
        skip && /^[[:space:]]+->/ { done[++n]=$0; next }
        { skip=0 }
        /^## Done$/    { print; for(i=1;i<=n;i++) print done[i]; next }
        { print }
      ' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
      echo "Archived to ## Done."
    fi
    ;;

  stuck)
    # List tasks stuck in [>] running state
    grep -F -- '- [>]' "$TASKS_FILE" || echo "No stuck tasks."
    ;;

  resume)
    shift; num="$1"
    task_dir=$(find "$TASKS_DIR" -maxdepth 1 -type d -name "${num}_*" | head -1)
    if [ -z "$task_dir" ]; then
      echo "No directory found for #${num}"
      exit 1
    fi

    # Reset state from [>] to [ ] if stuck
    flock "$TASKS_FILE" sed -i "s|^\- \[>\] ${num} |- [ ] ${num} |" "$TASKS_FILE"

    task_line=$(grep -E -- "^- \[.\] ${num} " "$TASKS_FILE" | head -1)
    task_desc=$(echo "$task_line" | sed -E 's/^- \[.\] [0-9]{3} \[[0-9-]+\] //' | sed 's/ #\(auto\|interactive\)$//')

    echo "Reset #${num}: ${task_desc}"
    echo "  -> ${task_dir}"
    ;;

  rollup)
    shift
    day="${1:-$(date +%Y-%m-%d)}"
    echo "=== Research Rollup: ${day} ==="
    echo ""
    grep "\[${day}" "$TASKS_FILE" | while IFS= read -r line; do
      echo "$line"
      # Print summary line if it exists (next line starting with spaces + ->)
    done
    echo ""
    echo "Reports completed:"
    find "$TASKS_DIR" -name "*_report.md" -newermt "$day 00:00" ! -newermt "$day 23:59:59" 2>/dev/null | while read -r f; do
      echo "  $f"
    done
    ;;

  *)
    echo "Usage: task {add|add-active|approve|reject|list|suggested|running|stuck|resume|archive|dir|rollup} [args]"
    ;;
esac
