---
name: investigate
description: Correlate a TI report's IOCs and TTPs against live Sentinel log sources and produce an investigation report
arguments:
  - name: report
    description: Path to TI report under analysis/ (e.g. ti-2026-06-28-sapphire-sleet-axios-supply-chain.md)
    required: true
  - name: workspace
    description: Log Analytics workspace ID (falls back to $LA_WORKSPACE_ID env var)
    required: false
  - name: days
    description: Lookback window in days (default 7)
    required: false
---

# Multi-Source Threat Investigation

## Step 1: Load TI Report

Read analysis/$report. Extract:
- All IOCs: IPs, domains, hashes, file paths, registry keys, package names
- High- and medium-confidence TTPs (ATT&CK IDs and technique names)
- Any existing KQL hunting queries in the report (reuse these rather than regenerating them)

## Step 2: Check Authentication

Run: az account show

If the command fails or returns no account, stop and tell the user to run `! az login` in the prompt before proceeding.

Resolve workspace: use --workspace arg if provided, else $LA_WORKSPACE_ID env var. If neither is set, ask the user for the workspace ID.

Set lookback: use --days arg if provided, else default to 7. Format as ISO 8601 duration: P${days}D.

## Step 3: Generate and Execute Queries

For each log source below, produce a targeted KQL query using the extracted IOCs and TTPs, then run it:

az monitor log-analytics query --workspace $workspace --analytics-query "..." --timespan P${days}D

Reuse existing queries from the TI report where they target the same log source. Supplement with generated queries for sources not yet covered.

**Windows Security events** — focus on process creation (EventID 4688), registry modification (4657), scheduled task creation (4698/4702). Filter for IOC file paths, renamed system utilities, run-key paths.

**Sysmon** — focus on Event 1 (ProcessCreate: parent node.exe, renamed PowerShell), Event 3 (NetworkConnect: C2 IPs/domains on non-standard ports), Event 11 (FileCreate: IOC paths), Event 12/13/14 (RegistryEvent: IOC run keys).

**Azure AD sign-in logs (SigninLogs)** — filter for sign-ins from hostnames or IPs that appear in endpoint findings; flag non-interactive logins, impossible travel, or logins shortly after C2 contact.

**Azure AD audit logs (AuditLogs)** — filter for role assignments, app consent grants, credential additions to service principals, changes made by accounts flagged in sign-in findings.

## Step 4: Correlate

Build a unified timeline from all results, sorted by timestamp. For each hit record:
- Timestamp
- Log source
- Host or account
- ATT&CK technique ID
- IOC matched
- Raw event summary (one line)

Flag elevated-confidence findings: any host or account that appears in results from two or more log sources.

## Step 5: Output

Save to analysis/inv-[date]-[campaign-name].md (derive campaign name from the TI report filename).

Include YAML frontmatter:
- source_report: analysis/$report
- workspace: (workspace ID used)
- timespan_days: (days queried)
- date_run: (today's date)

Structure the report as:
1. Executive Summary — hit count by source, highest-confidence findings, overall assessment (no evidence / suspicious / confirmed activity)
2. Timeline — unified table sorted by timestamp
3. Per-Source Findings — one section per log source with a results table and notes
4. Cross-Source Correlations — hosts/accounts seen in multiple sources
5. Recommended Next Steps — escalate, isolate, collect additional artifacts, or close
