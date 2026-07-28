#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_config="$repo_root/examples/config.codex-tv-remote.jsonc"
target_dir="${HOME}/.config/siriremote"
target_config="$target_dir/config.jsonc"

if [[ ! -f "$source_config" ]]; then
  echo "Missing preset: $source_config" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  jq empty "$source_config"
elif command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$source_config" >/dev/null
else
  echo "Warning: jq/python3 not found; skipping JSON validation." >&2
fi

mkdir -p "$target_dir"

if [[ -f "$target_config" ]]; then
  backup="$target_config.backup.$(date +%Y%m%d-%H%M%S)"
  cp "$target_config" "$backup"
  echo "Backed up existing config to: $backup"
fi

cp "$source_config" "$target_config"
echo "Installed Siri Remote config to: $target_config"
echo "Restart HyperVibe or wait for hot reload to apply it."
