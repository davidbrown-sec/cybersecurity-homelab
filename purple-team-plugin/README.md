# purple-team-workflow

A Claude Code plugin that packages an end-to-end purple team loop: ingest threat intel, map it to Atomic Red Team tests, execute in a lab, scan the resulting EVTX with Hayabusa, validate detections in Wazuh, and produce a cross-tool gap analysis. This is the same workflow used to run the Sapphire Sleet / Axios npm supply-chain exercise documented in this project's `exercises/` folder — packaged for reuse in other projects/labs.

## What's included

| Component | Purpose |
|---|---|
| `commands/ingest-ti.md` | `/ingest-ti` — turns a threat report URL/text into a TTP table + simulation plan, saved to `exercises/YYYY-MM-DD/threat-intel.md` |
| `commands/query.md` | `/query` — runs an OpenSearch DSL query against Wazuh, maps hits to ATT&CK, saves an Obsidian-style note to `exercises/YYYY-MM-DD/findings.md` |
| `commands/purple-loop.md` | `/purple-loop` — orchestrates the full 8-step loop (TI → test planning → execution → Hayabusa scan → Wazuh validation → gap analysis → report → Vectr tracking summary) |
| `agents/atomic-mapper.md` | Maps ATT&CK technique IDs to concrete `Invoke-AtomicTest` commands, filtered for Windows/lab-safety |
| `agents/endpoint-analyst.md` | Analyzes Windows Security + Sysmon logs for an incident, produces a timeline + IOCs + ATT&CK mapping |
| `agents/cloud-analyst.md` | Analyzes Azure AD sign-in/audit logs, produces a timeline + IOCs + ATT&CK mapping + endpoint-correlation hints |
| `hooks/settings-fragment.json` | `SessionStart`/`PreToolUse`/`PostToolUse`/`Stop` hooks — prereq checks, sensitive-file blocking, rule validation, completion notification |
| `mcp/server-configs.json` | MCP server config for the `hayabusa` EVTX-scanning server |
| `templates/CLAUDE.md` | Starting-point project instructions documenting the workflow, exercise folder convention, and lab environment table |

## Installation

From a project root in Claude Code:

```
/plugins install ./purple-team-plugin
```

This installs `commands/` and `agents/` automatically. Two pieces require a manual merge into your project because they touch files the plugin doesn't own outright:

1. **Hooks** — merge the contents of `hooks/settings-fragment.json` into your project's `.claude/settings.json` under the `hooks` key. If your project already has other hooks configured, merge arrays per event (`SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`) rather than overwriting.
2. **MCP server** — merge `mcp/server-configs.json` into your project's `.mcp.json` under `mcpServers`. Update the `command`/`args` paths to match where you've installed the Hayabusa MCP server on your machine (the shipped config points at a specific local Python interpreter and script path — these are almost certainly wrong for your machine and must be changed).

If you're starting a brand new project, you can copy `templates/CLAUDE.md` to your project root as-is and adjust the "Lab Environment" section to your own lab's hostnames/IPs.

The scripts referenced by the hooks fragment (`./scripts/check-prereqs.sh`, `./scripts/check-sensitive.sh`, `./scripts/validate-rule.sh`) are not included in this plugin — they're project-specific and need to exist at those relative paths in your project, or you should adjust/remove the hook entries that reference them.

## External dependencies

This plugin orchestrates external tools; it doesn't bundle them. Set these up before using the commands:

### Hayabusa (EVTX scanning, used by `/purple-loop` Step 4 and the `hayabusa` MCP server)
- Install the Hayabusa binary: https://github.com/Yamato-Security/hayabusa
- The `mcp/server-configs.json` in this plugin points at a custom MCP wrapper server (`mcp-hayabusa/server.py`) that exposes `scan_evtx`, `get_hayabusa_rules`, `analyze_coverage`, and `suggest_rule` tools over MCP. You'll need that wrapper server (or an equivalent) running and reachable at the path/command you configure.

### defuddle-cli (clean content extraction, used by `/ingest-ti`)
```
npm install -g defuddle-cli
```
If `defuddle` isn't available on `$PATH`, `/ingest-ti` falls back to `web_fetch` or asking you to paste the report content directly.

### Atomic Red Team (test execution, used by the `atomic-mapper` agent's output)
On the Windows target(s) you'll run tests against:
```powershell
Install-Module -Name invoke-atomicredteam, powershell-yaml -Scope CurrentUser -Force
Import-Module invoke-atomicredteam -Force
```
`atomic-mapper` produces `Invoke-AtomicTest` commands to run manually (or via your own automation) on the target — this plugin does not execute tests for you.

### Wazuh SIEM (used by `/query` and `/purple-loop` Step 5)
- A running Wazuh manager with OpenSearch, reachable at `https://localhost:9200` (typically via an SSH tunnel to the SIEM host, e.g. `ssh -L 9200:127.0.0.1:9200 user@<wazuh-host>`)
- Indices queried: `wazuh-archives-*` (raw events) and `wazuh-alerts-*` (fired alerts, for confirming detections actually reached alerting)

## Required environment variables

| Variable | Used by | Purpose |
|---|---|---|
| `WAZUH_USER` | `/query` | Wazuh/OpenSearch basic auth username |
| `WAZUH_PASS` | `/query` | Wazuh/OpenSearch basic auth password |

Set these in your shell before running `/query` or `/purple-loop`:
```bash
export WAZUH_USER=your-user
export WAZUH_PASS=your-password
```

## Example usage

### `/ingest-ti`
```
/ingest-ti https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/
```
Produces `exercises/2026-06-29/threat-intel.md` with a TTP table (technique, ID, confidence, priority), a kill-chain-ordered simulation plan, infrastructure requirements, and detection opportunities.

### `/query`
```
/query cmd.exe or lsass.exe process activity on win11v2 around 23:10:19 UTC — check for T1036.003 rename masquerading
```
Builds the OpenSearch DSL, runs it against `wazuh-archives-*`, analyzes hits for suspicious patterns, maps to ATT&CK, and writes `exercises/2026-06-29/findings.md` with an ATT&CK-tagged summary and follow-up checklist.

### `/purple-loop`
```
/purple-loop
```
Walks the full 8-step loop interactively: asks what threat report to simulate, invokes `/ingest-ti`, hands technique IDs to the `atomic-mapper` agent for test selection, gives you an execution checklist to run in your lab, scans the resulting EVTX with the `hayabusa` MCP server once you've exported logs, runs `/query` against Wazuh to validate the same activity reached alerting, compares Hayabusa vs. Wazuh detection/MITRE-mapping results for gaps, and closes out with a report and a Vectr-formatted tracking summary.

### `endpoint-analyst` / `cloud-analyst` agents
Invoke directly when correlating a multi-source incident, e.g.:
```
Use the endpoint-analyst agent on exercises/2026-06-29/evtx/Security.evtx and Sysmon.evtx to build a timeline of the T1036.003 activity.
```
```
Use the cloud-analyst agent on the Azure AD sign-in logs for user X between 2026-06-30T23:00 and 2026-07-01T00:00 to check for a matching cloud-side anomaly.
```
