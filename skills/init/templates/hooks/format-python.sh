#!/usr/bin/env bash
# PostToolUse hook: run black + isort on .py files after Edit/MultiEdit/Write.

input=$(cat)
[[ "$input" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || exit 0
file_path="${BASH_REMATCH[1]}"

[[ "$file_path" == *.py ]] || exit 0

# Resolve a tool from the project venv first — init installs black/isort as dev
# dependencies, so on most machines they exist only there, not on the hook's PATH.
find_tool() {
  local candidate
  for candidate in "${CLAUDE_PROJECT_DIR:-.}/.venv/bin/$1" "${CLAUDE_PROJECT_DIR:-.}/.venv/Scripts/$1.exe"; do
    [[ -x "$candidate" ]] && { echo "$candidate"; return; }
  done
  command -v "$1"
}

black_bin=$(find_tool black)
if [[ -n "$black_bin" ]] && ! output=$("$black_bin" --quiet "$file_path" 2>&1); then
  echo "[format-python] black failed: $(echo "$output" | head -1)" >&2
fi

isort_bin=$(find_tool isort)
if [[ -n "$isort_bin" ]] && ! output=$("$isort_bin" --quiet --profile black "$file_path" 2>&1); then
  echo "[format-python] isort failed: $(echo "$output" | head -1)" >&2
fi
