# Claude Research Queue

Task queue for managing research with Claude CLI, tmux, and bash.

## Setup

```bash
# Make scripts executable
chmod +x ~/claude-research/*.sh

# Bash (work):
echo 'source ~/claude-research/aliases.sh' >> ~/.bashrc
source ~/claude-research/aliases.sh

# Fish (home):
echo 'source ~/claude-research/aliases.fish' >> ~/.config/fish/config.fish
source ~/claude-research/aliases.fish
```

Hooks are in `~/.claude/settings.json` (already merged). They color tmux panes
green (task complete) or red (needs input).

## Quick Start

```bash
# Start tmux session with monitoring sidebar
bash ~/claude-research/start.sh

# Add ideas throughout the day
idea "analyze latency patterns in production logs"
idea "pull quarterly metrics from dashboard" "#a"

# Review Claude's suggestions
suggested
approve 003
approve all
reject 005

# Launch all approved #a tasks in parallel
launch

# Open interactive research session in tmux
research "deep dive on caching strategy"

# Resume a stuck or crashed task
stuck                # list tasks stuck in [>]
resume 003           # reopen in tmux with prior context

# Search across all research
rgrep "latency"

# Read a report
report 003

# End-of-day summary (Haiku-generated)
daily

# Move completed tasks out of Active view
archive
```

## Concepts

There are two kinds of tasks:

- **`#i` (interactive)** -- you're driving. Opens a live Claude session in a tmux
  pane where you collaborate in real time. Use `idea "question"` or
  `research "question"` to create these. Default for `idea` and `research`.

- **`#a` (auto)** -- Claude does its thing, you review later. Data pulls,
  comparisons, straightforward analyses. You queue them up, run `launch`, and they
  execute in the background (up to 4 at a time). Each produces a report and a
  Haiku-generated summary. Use `task add "question"` or `idea "question" "#a"`.

Both produce the same outputs (reports, logs, summaries). The difference is when
you pay attention -- now or later.

Claude can suggest follow-up tasks (tagged `#a` or `#i`) during any session. These
appear as `[?] Suggested` for you to approve or reject before they run.

## Task Lifecycle

```
idea / task add          task add-active
      |                        |
      v                        v
  [?] Suggested           [ ] Active (approved)
      |                        |
  approve                   launch / research
      |                        |
      v                        v
  [ ] Active               [>] Running
                               |
                          +---------+
                          |         |
                          v         v
                      [x] Done   [>] Stuck
                          |         |
                       archive   resume
                          |         |
                          v         v
                      ## Done    [ ] Active (retry)
```

## Commands

| Command | Action |
|---------|--------|
| `idea "question"` | Add to active queue (#i default) |
| `idea "question" "#a"` | Add as auto task |
| `task add "question"` | Add to suggested queue (#a default) |
| `approve 003` / `approve all` | Approve suggestions -> active |
| `reject 005` | Remove suggestion |
| `suggested` | List pending suggestions |
| `launch` | Run all approved #a tasks in parallel |
| `rerun 003` | Reset task to [ ] #a for next launch |
| `research "question"` | Open interactive tmux pane |
| `resume 003` | Resume stuck/incomplete task |
| `stuck` | List tasks stuck in [>] state |
| `archive` | Move [x] tasks to ## Done section |
| `report 003` | Print report for task |
| `rgrep "term"` | Search all research files |
| `rollup [date]` | Quick task summary for date |
| `daily [date]` | Haiku-generated daily rollup |
| `task list` | Print full tasks.md |

## Task Format

```
- [?] 003 [2026-04-10] Compare caching strategies across services #a
- [x] 001 [2026-04-10] Analyze production latency patterns #a
      -> Latency Hotspots: P99 latency driven by cold cache misses in auth service
```

## Tags

| Tag | Meaning |
|-----|---------|
| `#a` | Auto -- Claude works, you review later. Launched by `launch` |
| `#i` | Interactive -- you're driving. Opened by `research` |

## File Structure

```
claude-research/
  tasks.md              # task queue (Active / Suggested / Done)
  tasks/
    001_analyze_latency/
      001_research.ipynb
      001_report.md
      001_summary.md    # Haiku-generated title + one-liner
      001_data/
      001_output.log    # raw Claude session output
  shared/
    utils.py
    data/
  rollups/
    2026-04-10.md       # daily rollup
  batch.log             # launcher activity log
  CLAUDE.md             # research protocol for Claude
  task.sh               # task management CLI
  launch.sh             # batch launcher
  start.sh              # tmux layout
  aliases.sh            # bash aliases/functions
  aliases.fish          # fish aliases/functions
```

## Tmux Layout

```
+------------------------------------+-----------+
|                                    | tasks.md  |
|      Interactive research          | (live)    |
|      panes (tiled)                 |           |
|                                    +-----------+
|      Red bg = needs input          | reports   |
|      Green bg = complete           | (latest)  |
|                                    +-----------+
|                                    | batch log |
+------------------------------------+-----------+
            ~75%                        ~25%
```
