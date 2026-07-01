#!/usr/bin/env bash
set -euo pipefail

target_dir="${1:-.}"

if [[ ! -d "$target_dir" ]]; then
  echo "Error: '$target_dir' is not a directory" >&2
  exit 1
fi

if ! command -v tree >/dev/null 2>&1; then
  echo "Error: 'tree' command is not installed" >&2
  exit 1
fi

echo "====== DIRECTORY TREE: $target_dir ======"
tree "$target_dir"

echo
echo "====== FILE CONTENTS ======"

find "$target_dir" -type f -print0 | sort -z | while IFS= read -r -d '' file; do
  printf '\n====== %s ======\n' "$file"
  cat "$file"
done