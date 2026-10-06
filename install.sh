#!/usr/bin/env bash
# Install p3-stack skills for T3 Code.
# Links into .claude/skills (Claude Code) and .agents/skills (Codex-style tools).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${HOME}"

if [[ "${1:-}" == "--project" ]]; then
  BASE="${2:?usage: ./install.sh --project /path/to/repo}"
fi

for TARGET in "$BASE/.claude/skills" "$BASE/.agents/skills"; do
  mkdir -p "$TARGET"
  installed=0
  skipped=0

  for skill in "$ROOT"/skills/*/; do
    name="$(basename "$skill")"
    if [[ -e "$TARGET/$name" && ! -L "$TARGET/$name" ]]; then
      printf 'skip %s in %s (exists and is not a symlink)\n' "$name" "$TARGET" >&2
      skipped=$((skipped + 1))
      continue
    fi
    ln -sfn "${skill%/}" "$TARGET/$name"
    installed=$((installed + 1))
  done

  printf 'linked %d skills into %s' "$installed" "$TARGET"
  if [[ "$skipped" -gt 0 ]]; then
    printf ' (%d skipped)' "$skipped"
  fi
  printf '\n'
done
