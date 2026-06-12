#!/bin/bash
# Claude Code status line. Reads the JSON Claude pipes in on stdin and renders a
# two-line bar: model, dir/repo/branch/worktree, context-usage meter, session
# cost/timer, plus cached today/MTD usage. Never blocks — a stale cache triggers
# a background refresh under an atomic lock.
input=$(cat)
MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'
# Pick bar color based on context usage
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi
FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"
MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))
# ---- Directory / repo / branch / worktree ----
DIM='\033[2m'; BOLD='\033[1m'
cd "$DIR" 2>/dev/null
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
BRANCH=""
WT=""
if [ -n "$TOP" ]; then
  PLACE="${TOP##*/}"
  BR=$(git branch --show-current 2>/dev/null)
  [ -n "$BR" ] && BRANCH=" 🌿 $BR"
  [ -f "$TOP/.git" ] && WT=" ${DIM}⑂ wt${RESET}"   # a linked worktree has a .git file, not a dir
elif [ "$DIR" = "$HOME" ]; then PLACE="~"
else PLACE="${DIR##*/}"; fi
COST_FMT=$(printf '$%.2f' "$COST")

# ---- Day / MTD usage (cached, refreshed in the background) ----
USAGE_CACHE="$HOME/.claude/.statusline-usage-cache.json"
RTK_CACHE="$HOME/.claude/.statusline-rtk-cache.json"
USAGE_LOCK="$HOME/.claude/.statusline-usage.lock"
REFRESH="$HOME/.claude/statusline-refresh.sh"
PROJECTS_DIR="$HOME/.claude/projects"

# Refresh in the background when the cache is missing or older than 60s, so the
# transcript scan never blocks the render. mkdir is the atomic lock.
NEED_REFRESH=0
if [ ! -f "$USAGE_CACHE" ]; then NEED_REFRESH=1
elif [ -n "$(find "$USAGE_CACHE" -mmin +1 2>/dev/null)" ]; then NEED_REFRESH=1; fi
if [ "$NEED_REFRESH" -eq 1 ]; then
  if mkdir "$USAGE_LOCK" 2>/dev/null; then
    nohup bash "$REFRESH" "$USAGE_CACHE" "$RTK_CACHE" "$USAGE_LOCK" "$PROJECTS_DIR" >/dev/null 2>&1 &
    disown 2>/dev/null
  elif [ -n "$(find "$USAGE_LOCK" -mmin +5 2>/dev/null)" ]; then
    rmdir "$USAGE_LOCK" 2>/dev/null  # reap a stale lock from a crashed refresh
  fi
fi

humanize() {
  local n=${1:-0}
  if [ "$n" -ge 1000000000 ]; then awk -v n="$n" 'BEGIN{printf "%.1fB", n/1000000000}'
  elif [ "$n" -ge 1000000 ]; then awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}'
  elif [ "$n" -ge 1000 ]; then awk -v n="$n" 'BEGIN{printf "%.1fK", n/1000}'
  else printf "%d" "$n"; fi
}

DATELBL=$(date '+%b %d' | sed 's/ 0/ /')
DATE_SEG="${BOLD}${CYAN}${DATELBL}${RESET}"
SESSION="${DIM}session${RESET} ${YELLOW}${COST_FMT}${RESET}"
if [ -f "$USAGE_CACHE" ]; then
  D_COST=$(jq -r '.day_cost // 0' "$USAGE_CACHE")
  M_COST=$(jq -r '.mtd_cost // 0' "$USAGE_CACHE")
  D_TOK=$(humanize "$(jq -r '.day_tokens // 0' "$USAGE_CACHE")")
  M_TOK=$(humanize "$(jq -r '.mtd_tokens // 0' "$USAGE_CACHE")")
  D_COST_FMT=$(printf '$%.2f' "$D_COST")
  M_COST_FMT=$(printf '$%.2f' "$M_COST")
  LINE2="${DATE_SEG}  ${DIM}┃${RESET} ${SESSION}  ${DIM}┃ today${RESET} ${YELLOW}${D_COST_FMT}${RESET} ${DIM}·${RESET} ${CYAN}${D_TOK}${RESET} ${DIM}tok  ┃  MTD${RESET} ${YELLOW}${M_COST_FMT}${RESET} ${DIM}·${RESET} ${CYAN}${M_TOK}${RESET} ${DIM}tok${RESET}"
else
  LINE2="${DATE_SEG}  ${DIM}┃${RESET} ${SESSION}  ${DIM}┃ today / MTD — computing…${RESET}"
fi

# Optional: token-savings from the "rtk" CLI, only shown if its cache exists.
if [ -f "$RTK_CACHE" ]; then
  R_TODAY=$(jq -r '.today_saved // "0"' "$RTK_CACHE")
  R_TOTAL=$(jq -r '.total_saved // "0"' "$RTK_CACHE")
  LINE2="$LINE2  ${DIM}┃${RESET} ${GREEN}⚡ rtk${RESET} ${CYAN}${R_TODAY}${RESET} ${DIM}today ·${RESET} ${CYAN}${R_TOTAL}${RESET} ${DIM}saved${RESET}"
fi

echo -e "${CYAN}[$MODEL]${RESET} 📁 ${PLACE}${BRANCH}${WT} ${BAR_COLOR}${BAR}${RESET} ${PCT}% | ⏱️   ${MINS}m ${SECS}s"
echo -e "$LINE2"
