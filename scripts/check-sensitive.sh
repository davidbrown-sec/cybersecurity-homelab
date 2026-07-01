#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')

if [[ -z "$file_path" ]]; then
  exit 0
fi

if [[ "$file_path" =~ (^|/)\.env($|/) || \
      "$file_path" =~ \.key$ || \
      "$file_path" =~ \.pem$ || \
      "$file_path" =~ (^|/)secrets/ || \
      "$file_path" =~ (^|/)credentials/ ]]; then
  echo "BLOCKED: access to sensitive path denied: $file_path" >&2
  exit 2
fi

exit 0
