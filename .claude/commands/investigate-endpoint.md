Perform a comprehensive endpoint investigation by correlating Wazuh OpenSearch telemetry with Hayabusa EVTX analysis, mapping all findings to ATT&CK techniques, and saving a unified Obsidian-compatible investigation note.

## Arguments

- `$ARGUMENTS` — the command line arguments. Parse them as follows:
  - First positional argument: hostname or IP address of the endpoint to investigate (required)
  - Optional `--timerange` flag (e.g. `--timerange -7d`); default: `-24h`
  - Optional `--case_id` flag — existing case or ticket number to link (e.g. `--case_id CASE-0001`)
  - Optional `--assignee` flag — analyst name; default: `David`

## Steps

### 1. Parse arguments

Extract the following from `$ARGUMENTS`:

- **Host** — first positional argument (required). May be a hostname (e.g. `dc`, `workstation-01`) or an IP address. If missing, stop and tell the user.
- **`--timerange`** — default: `-24h`
- **`--case_id`** — default: *(omit if not provided)*
- **`--assignee`** — default: `David`

### 2. Query Wazuh OpenSearch

Build and execute a query matching all events from the specified host within the timerange. Match against `agent.name`, `agent.ip`, and `data.srcip` to capture both agent-sourced and forwarded events.

Use curl with the `WAZUH_USER` (default: `user`) and `WAZUH_PASS` environment variables. Use `-sk` to skip SSL certificate verification.

```bash
curl -sk -u "${WAZUH_USER:-user}:${WAZUH_PASS}" \
  -H "Content-Type: application/json" \
  -X GET "https://localhost:9200/wazuh-archives-*/_search" \
  -d '<DSL_BODY>'
```

Use this DSL body, substituting `<HOST>` and `<TIMERANGE>`:

```json
{
  "size": 500,
  "query": {
    "bool": {
      "should": [
        { "term": { "agent.name": "<HOST>" } },
        { "term": { "agent.ip": "<HOST>" } },
        { "term": { "data.srcip": "<HOST>" } }
      ],
      "minimum_should_match": 1,
      "filter": [
        {
          "range": {
            "@timestamp": {
              "gte": "now<TIMERANGE>",
              "lte": "now"
            }
          }
        }
      ]
    }
  },
  "sort": [{ "@timestamp": { "order": "desc" } }],
  "aggs": {
    "top_rule_ids": {
      "terms": { "field": "rule.id", "size": 20 }
    },
    "top_rule_descriptions": {
      "terms": { "field": "rule.description", "size": 20 }
    },
    "top_event_ids": {
      "terms": { "field": "data.win.system.eventID", "size": 20 }
    },
    "top_users": {
      "terms": { "field": "data.win.eventdata.user", "size": 10 }
    },
    "severity_breakdown": {
      "terms": { "field": "rule.level", "size": 10 }
    }
  }
}
```

If the response contains an `error` field, report it and stop.

Extract from the response:
- `hits.total.value` — total event count
- `hits.hits[]._source` — up to the first 20 records for analysis
- `aggregations` — rule ID, event ID, user, and severity breakdowns

### 3. Check for EVTX files

Check whether the `evtx/` directory exists in the current working directory and whether it contains any EVTX files matching the host:

```bash
find evtx/ -iname "<HOST>*.evtx" -o -iname "<HOST>/*.evtx" 2>/dev/null
```

Also check for a subdirectory named after the host: `evtx/<HOST>/`.

- If matching EVTX files are found, record their paths and proceed to step 4.
- If no matches are found, skip step 4 and record that Hayabusa analysis was skipped.

### 4. Run Hayabusa scan (only if EVTX files were found)

Use the Hayabusa MCP tool to scan the EVTX files found in step 3. Pass:
- The EVTX file path(s) or directory containing them
- Output format: JSON (for structured parsing)
- Minimum alert level: `low` (to maximize coverage)

From the Hayabusa JSON output, extract for each finding:
- `Timestamp`
- `Computer` (hostname as recorded in the EVTX)
- `Channel` (e.g. Security, System, Sysmon/Operational)
- `EventID`
- `Level` (critical / high / medium / low / informational)
- `RuleTitle`
- `MitreTactics` and `MitreTechniques`
- `Details` (parsed event fields: user, process, command line, destination, etc.)

Group findings by level. Focus primary analysis on `critical` and `high`. Include `medium` findings when they reinforce a higher-severity pattern. Summarize `low` findings by count only.

### 5. Analyze Wazuh findings

Examine the Wazuh records and aggregations for suspicious patterns. Look for:

- **Privilege escalation:** runas, token impersonation (EID 4672, 4673), UAC bypass, SeDebugPrivilege grants
- **Credential access:** LSASS access (EID 4656 on lsass.exe), SAM hive reads (EID 4663), DCSync (EID 4662 on domain object), Mimikatz strings in command lines
- **Lateral movement:** SMB access (EID 5140/5145), WMI execution (EID 4688 with wmic), PSExec artifacts, remote logons (EID 4624 Type 3 from unexpected source)
- **Persistence:** scheduled task creation (EID 4698), service installs (EID 7045), registry run key writes (EID 4657), startup folder writes
- **Defense evasion:** security log clearing (EID 1102, 104), process injection indicators, AV/EDR service stops, suspicious process parent–child chains
- **Command and control:** encoded PowerShell (EID 4104 with Base64), outbound connections to unusual ports, DNS lookups with high-entropy names
- **Discovery:** whoami, net user/group, ipconfig, systeminfo, nltest, LDAP enumeration, BloodHound artifacts
- **Execution:** PowerShell with `-enc`/`-EncodedCommand` (EID 4103/4104), Office processes spawning cmd/powershell, script interpreters (wscript, cscript, mshta)
- **Exfiltration:** large outbound transfers, archiving sensitive paths (7z, rar, zip on Documents/Desktop), unusual protocols

For each pattern found: note the rule ID(s), Windows Event ID(s), timestamps, user, process, and occurrence count.

### 6. Analyze Hayabusa findings (only if step 4 was performed)

Group Hayabusa output by ATT&CK tactic. For each `critical` or `high` finding:
- Record the rule title, matched EventID, channel, and timestamp
- Extract detail fields (user, process name, command line, source/destination IP, etc.)
- Note the ATT&CK technique(s) Hayabusa has already mapped

For `medium` findings: summarize by rule title and count. Flag any that map to the same technique as a Wazuh finding.

### 7. Correlate Wazuh and Hayabusa findings

Identify events appearing in **both** data sources. Apply these correlation criteria:

- **Same EventID on the same host** — if both Wazuh and Hayabusa flagged the same Windows Event ID, this is a corroborated signal.
- **Same timestamp window (±5 minutes)** — events in both sources around the same time strengthen confidence.
- **Same ATT&CK technique** — independent mapping to the same technique by both tools is a high-confidence indicator.
- **Complementary detail** — note where Hayabusa parsed specific fields (command line, user, target object) that Wazuh only logged at a rule level, or vice versa.

Assign confidence per corroborated finding:
- **High:** same EventID + overlapping timestamp + same technique in both sources
- **Medium:** same EventID or same technique within the timerange in both sources
- **Low:** co-occurrence on the same host in the same timerange, different EventIDs or techniques

### 8. Map all findings to ATT&CK

Combine findings from both sources into a unified technique list. For each unique technique:
- Use the most specific ID available (`TXXXX.XXX` preferred over `TXXXX`)
- Note which source(s) surfaced it: **Wazuh only**, **Hayabusa only**, or **Both**
- Note the tactic

Then infer overall investigation severity:
- **Critical:** credential dumping, DCSync, domain admin compromise, ransomware indicators, or 3+ high-severity techniques
- **High:** confirmed lateral movement, persistence established, privilege escalation, or 2+ high-severity techniques
- **Medium:** discovery activity, single suspicious execution, 1 high or 3+ medium techniques
- **Low:** anomalous but non-threatening activity, informational techniques only

### 9. Generate the investigation note

Construct the output as Obsidian-compatible markdown using this structure:

```markdown
---
date: <ISO date of today>
host: <hostname or IP>
tags:
  - siem
  - wazuh
  - investigation
  - endpoint
  - <att&ck-technique-id-lowercased for each technique>
techniques:
  - <TXXXX>
  - <TXXXX.XXX>
severity: <critical|high|medium|low from step 8>
timerange: <timerange used>
total_wazuh_hits: <hits.total.value>
hayabusa_findings: <count of Hayabusa findings, or "skipped">
assignee: <assignee value>
case_id: <case_id value, or omit this line if not provided>
data_sources:
  - wazuh
  <- hayabusa (include only if EVTX files were scanned)>
---

# Endpoint Investigation: <hostname> — <brief characterization e.g. "Credential Access & Discovery on Domain Controller">

**Date:** <today's date>  
**Host:** `<hostname or IP>`  
**Timerange:** <timerange>  
**Severity:** <severity>  
**Assignee:** <assignee>  
**Case / Ticket:** <[[case_id]] or `None`>  
**Data Sources:** Wazuh (<hits.total.value> events)<, Hayabusa (<N> findings) — include only if applicable>

## Executive Summary

<3–6 sentence narrative. What was the host doing during the timerange? What is the most alarming finding? Does Hayabusa corroborate Wazuh? What stage of the attack lifecycle does the activity suggest?>

## Wazuh Findings

**Total Events:** <hits.total.value>  
**Timerange:** <timerange>

### Top Rule Alerts

| Rule ID | Description | Count | Level |
|---------|-------------|-------|-------|
| <id> | <description> | <count> | <level> |

<List top 5–10 rules from aggregations.>

### Suspicious Activity

<For each pattern from step 5:>

#### <Pattern Name>

- **Description:** <what was observed>
- **Event IDs:** <EIDs involved>
- **Count:** <occurrences>
- **Key Indicators:** <user, process, rule ID, timestamps>
- **ATT&CK:** [[TXXXX]] — <Technique Name>

## Hayabusa Findings

<If no EVTX files were found:>
No EVTX files matching `<hostname>` were found in the `evtx/` directory. Hayabusa analysis was skipped.

<If EVTX files were scanned:>

**EVTX Files Scanned:** <list of file paths>  
**Total Findings:** <N>  
**Critical:** <N> | **High:** <N> | **Medium:** <N> | **Low:** <N>

### Critical & High Findings

<For each critical/high Hayabusa finding:>

#### <RuleTitle>

- **EventID:** <EID>
- **Channel:** <channel>
- **Timestamp:** <timestamp>
- **Level:** <level>
- **Details:** <key parsed fields — user, process, command line, destination, etc.>
- **ATT&CK:** [[TXXXX]] — <Technique Name>

### Medium Findings Summary

| Rule Title | EventID | Count | ATT&CK |
|------------|---------|-------|--------|
| <title> | <EID> | <N> | [[TXXXX]] |

## Correlated Findings

<If Hayabusa was skipped:>
Correlation skipped — Hayabusa analysis was not performed.

<If both sources have data, for each corroborated finding:>

### <Finding Title>

- **Confidence:** <High | Medium | Low>
- **Wazuh:** Rule <id> — <description>, <timestamp>
- **Hayabusa:** <RuleTitle> (<level>), <timestamp>
- **Shared EventID:** <EID>
- **Shared Technique:** [[TXXXX]]
- **Note:** <why this correlation matters — e.g. "Both sources independently flagged EID 4624 Type 3 at 00:47 UTC, confirming a remote logon 76 seconds after whoami executed">

## ATT&CK Coverage

| Technique | Name | Tactic | Source | Confidence |
|-----------|------|--------|--------|------------|
| [[TXXXX]] | <Name> | <Tactic> | Wazuh / Hayabusa / Both | High / Medium / Low |

## Result Statistics

- **Wazuh Total Hits:** <hits.total.value>
- **Wazuh Records Analyzed:** <N>
- **Hayabusa Findings:** <N or "skipped">
- **Corroborated Findings:** <N>
- **Unique ATT&CK Techniques:** <N>
- **Index Pattern:** `wazuh-archives-*`
- **Timerange Applied:** <timerange>

### Top Event IDs (from Wazuh aggregations)

| EventID | Count |
|---------|-------|
| <eid> | <count> |

### Severity Breakdown (Wazuh rule levels)

| Level | Count |
|-------|-------|
| <level> | <count> |

## Analyst Notes

<!-- Add your observations, context, and next steps here -->

- [ ] Determine how initial access was established — review logon events (EID 4624) before the first suspicious activity timestamp
- [ ] Reconstruct the full process execution chain on `<hostname>` — pull Sysmon EID 1 logs if available
- [ ] Check for lateral movement **from** this host — query Wazuh for events on other hosts that reference `<hostname>` as a source
- [ ] Verify whether any persistence mechanisms identified are still active
- [ ] Cross-reference with [[asset inventory]] — confirm host role, owner, and expected behavioral baseline
- [ ] Escalate to IR if findings are confirmed malicious
```

### 10. Save the output file

- Save to the `investigations/` directory relative to the current working directory. Create it if it does not exist.
- Filename format:
  - With `--case_id`: `<case_id>-<YYYY-MM-DD>-<hostname>.md`
  - Without `--case_id`: `<YYYY-MM-DD>-<hostname>.md`
- Write the markdown to that file and report the full path to the user.

### 11. Print a brief summary

After saving, print:
- Host investigated
- Wazuh event count
- Hayabusa findings count (or "skipped — no EVTX files found")
- Number of corroborated findings
- ATT&CK techniques identified
- Overall severity
- Path to the saved investigation note
