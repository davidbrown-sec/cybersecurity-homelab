# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Purple Team Workflow

End-to-end purple team loop: threat intel → simulation → detection → validation → reporting.

## Commands

- `/ingest-ti <url>` - Process threat intelligence, extract TTPs
- `/query <search>` - Run SIEM query, generate Obsidian notes
- `/purple-loop` - Full guided workflow

## Agents

- `atomic-mapper` - Map techniques to Atomic Red Team tests

## MCP Servers

- `hayabusa` - EVTX analysis and threat hunting

## Exercise Structure

Exercises stored in `exercises/YYYY-MM-DD/`:
- `evtx/` - Collected event logs
- `findings.md` - Detection results
- `report.md` - Exercise summary

## Lab Environment

ConDef lab:
- DC (Domain Controller) — 192.168.1.50
- Win11V2 — 192.168.1.54
- Win11A — 192.168.1.53
- Wazuh SIEM — 192.168.1.224 (OpenSearch at localhost:9200 via SSH tunnel)
