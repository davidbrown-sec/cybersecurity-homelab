#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')

if [[ -z "$file_path" ]]; then
  echo "ERROR: could not extract file_path from input" >&2
  exit 2
fi

if [[ ! "$file_path" =~ ^rules/.*\.(yml|yaml)$ ]]; then
  exit 0
fi

python3 - "$file_path" >&2 <<'PYEOF' || exit 2

import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed (pip install pyyaml)")
    sys.exit(1)

file_path = sys.argv[1]

try:
    with open(file_path) as f:
        rule = yaml.safe_load(f)
except FileNotFoundError:
    print(f"ERROR: file not found: {file_path}")
    sys.exit(1)
except Exception as e:
    print(f"ERROR: could not parse YAML: {e}")
    sys.exit(1)

errors = []

if not isinstance(rule, dict) or not rule.get('title'):
    errors.append("missing 'title' field")
if not isinstance(rule, dict) or not rule.get('description'):
    errors.append("missing 'description' field")

tags = rule.get('tags', []) if isinstance(rule, dict) else []
if not any(str(t).lower().startswith('attack.t') for t in tags):
    errors.append("'tags' must contain at least one 'attack.t' entry")

if errors:
    for err in errors:
        print(f"ERROR: {err}")
    sys.exit(1)

print("OK: rule is valid")
PYEOF

exit 0
