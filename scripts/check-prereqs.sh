#!/usr/bin/env bash
missing=()

command -v jq >/dev/null 2>&1 || missing+=("jq")
command -v python3 >/dev/null 2>&1 || missing+=("python3")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "WARNING: missing required tools: ${missing[*]}" >&2
fi
