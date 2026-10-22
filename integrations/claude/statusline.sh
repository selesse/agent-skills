#!/bin/bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
# Subscription limits: only for Pro/Max, and only after the session's first response
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Colors (xterm 256). Green, yellow and red mean how full a meter is (ctx, 5h,
# wk), so the labels use colors of their own.
lavender="\033[38;5;141m"
pink="\033[38;5;211m"
sky="\033[38;5;110m"
orchid="\033[38;5;176m"
green="\033[38;5;114m"
yellow="\033[38;5;221m"
red="\033[38;5;203m"
reset="\033[0m"

# Worktree name: extract from ~/world/trees/<name>/src
worktree=""
if [[ "$cwd" =~ world/trees/([^/]+)/src ]]; then
  tree_name="${BASH_REMATCH[1]}"
  if [[ "$tree_name" != "root" ]]; then
    worktree="$tree_name"
  fi
fi

# Branch name
branch=""
if [[ -n "$cwd" ]]; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
fi

# PR number (from Graphite local state, no network call)
pr=""
if [[ -n "$branch" && -n "$cwd" ]] && command -v gt &>/dev/null; then
  pr=$(cd "$cwd" && gt log short 2>/dev/null | grep -F "$branch" | grep -o '#[0-9]*' | head -1)
fi

# Context window color: red if >=80%, yellow if >=50%, green otherwise
ctx_color="$green"
if [[ -n "$used_pct" ]]; then
  pct_int=${used_pct%.*}
  if [[ "$pct_int" -ge 80 ]]; then
    ctx_color="$red"
  elif [[ "$pct_int" -ge 50 ]]; then
    ctx_color="$yellow"
  fi
fi

# Usage color, as for the context window: red if >=80%, yellow if >=50%, green otherwise
pct_color() {
  local pct=${1%.*}
  if [[ "$pct" -ge 80 ]]; then
    echo "$red"
  elif [[ "$pct" -ge 50 ]]; then
    echo "$yellow"
  else
    echo "$green"
  fi
}

# When the 5-hour window resets, as local HH:MM (BSD date on macOS, GNU on Linux)
five_h_resets=""
if [[ -n "$five_h_reset" ]]; then
  five_h_resets=$(date -r "$five_h_reset" +%H:%M 2>/dev/null || date -d "@$five_h_reset" +%H:%M 2>/dev/null)
fi

# Build output
parts=()
[[ -n "$model" ]] && parts+=("${lavender}${model}${reset}")
[[ -n "$worktree" ]] && parts+=("${pink}${worktree}${reset}")
[[ -n "$branch" ]] && parts+=("${sky}${branch}${reset}")
[[ -n "$pr" ]] && parts+=("${orchid}PR ${pr}${reset}")
[[ -n "$used_pct" ]] && parts+=("${ctx_color}ctx ${used_pct}%${reset}")
[[ -n "$five_h" ]] && parts+=("$(pct_color "$five_h")5h ${five_h%.*}%${five_h_resets:+ ↻$five_h_resets}${reset}")
[[ -n "$week" ]] && parts+=("$(pct_color "$week")wk ${week%.*}%${reset}")

# Join with separator
output=""
for i in "${!parts[@]}"; do
  [[ $i -gt 0 ]] && output+=" | "
  output+="${parts[$i]}"
done

echo -e "$output"
