Execute a SIEM query against Wazuh OpenSearch, analyze results for suspicious patterns, map to ATT&CK techniques, and save an Obsidian-compatible investigation note.

## Arguments

- `$ARGUMENTS` — the command line arguments. Parse them as follows:
  - First positional argument: path to a `.json` file containing an OpenSearch DSL query
  - Optional `--timerange` flag (e.g. `--timerange -7d`); default: `-24h`
  - Optional `--severity` flag — expected severity level: `info`, `low`, `medium`, `high`, or `critical`. If provided, use this value in the note instead of auto-inferring from findings. If not provided, infer severity from findings as before.
  - Optional `--assignee` flag — analyst name to assign the investigation to (e.g. `--assignee "Jane Smith"`)
  - Optional `--case_id` flag — existing case or ticket number to link (e.g. `--case_id INC-4821`)
  - Optional `--output_dir` flag — directory path where the investigation note should be saved; default: `investigations/`

## Steps

### 1. Parse arguments

Extract the following from `$ARGUMENTS`:

- **Query file path** — first positional argument (required)
- **`--timerange`** — default: `-24h`
- **`--severity`** — default: *(infer from findings)*
- **`--assignee`** — default: *(omit field if not provided)*
- **`--case_id`** — default: *(omit field if not provided)*
- **`--output_dir`** — default: `investigations/`

If the query file path is missing, stop and tell the user.

### 2. Read the query file

Read the query file at the path provided. It contains a raw OpenSearch DSL JSON body (not SPL). If the file does not exist, stop and tell the user.

### 3. Inject the time range

Inspect the DSL body. If it already contains a `range` filter on `@timestamp` or `timestamp`, leave it as-is. Otherwise, wrap the existing query in a `bool` filter that adds:

```json
{
  "range": {
    "@timestamp": {
      "gte": "now<TIMERANGE>",
      "lte": "now"
    }
  }
}
```

Where `<TIMERANGE>` is the timerange argument (e.g. `-24h`, `-7d`).

### 4. Run the query

Execute the query using curl. Read the `WAZUH_USER` environment variable (default: `user`) and `WAZUH_PASS` environment variable for credentials. Use `-sk` to skip SSL cert verification.

```bash
curl -sk -u "${WAZUH_USER:-user}:${WAZUH_PASS}" \
  -H "Content-Type: application/json" \
  -X GET "https://localhost:9200/wazuh-archives-*/_search" \
  -d '<DSL_BODY>'
```

Capture the full JSON response. If the request fails or returns an error field, report the error and stop.

### 5. Extract key fields from the response

From the JSON response, extract:
- `hits.total.value` — total number of matching documents
- `hits.hits[]._source` — the individual log records (up to the first 10 for analysis)
- Any `aggregations` buckets if present

### 6. Analyze for suspicious patterns

Examine the returned log records. Look for:
- Privilege escalation indicators (sudo, su, runas, token manipulation)
- Credential access (LSASS access, /etc/shadow reads, SAM hive access, mimikatz strings)
- Lateral movement (SMB connections, WMI, PSExec, SSH from unusual sources)
- Persistence (cron modifications, registry run keys, startup folder writes, service installs)
- Defense evasion (log clearing, AV tampering, process injection indicators)
- Command and control (unusual outbound ports, DNS beaconing patterns, encoded payloads)
- Discovery (net commands, whoami, ipconfig, nmap, port scans)
- Execution (PowerShell encoded commands, cmd spawned from Office, script interpreters)
- Exfiltration (large data transfers, compression before transfer, unusual protocols)

Summarize each suspicious pattern found. Note specific fields like source IP, destination, user, process, rule ID, agent name, and timestamps.

### 7. Map to ATT&CK techniques

For each suspicious pattern identified, map it to one or more MITRE ATT&CK technique IDs (format: `TXXXX` or `TXXXX.XXX`). Use your knowledge of ATT&CK to assign the most specific applicable technique. List the technique ID and name.

### 8. Generate the investigation note

Construct the output as Obsidian-compatible markdown. Use this structure:

```markdown
---
date: <ISO date of today>
tags:
  - siem
  - wazuh
  - investigation
  - <att&ck-technique-id-lowercased for each technique>
techniques:
  - <TXXXX>
  - <TXXXX.XXX>
severity: <value of --severity if provided, otherwise low|medium|high|critical inferred from findings>
query_file: <basename of the query file>
timerange: <timerange used>
total_hits: <hits.total.value>
assignee: <value of --assignee, or omit this line entirely if not provided>
case_id: <value of --case_id, or omit this line entirely if not provided>
---

# Investigation: <descriptive title based on query filename and findings>

**Date:** <today's date>  
**Timerange:** <timerange>  
**Total Results:** <hits.total.value>  
**Query File:** `<query file path>`  
**Severity:** <severity value>  
**Assignee:** <value of --assignee, or `Unassigned` if not provided>  
**Case / Ticket:** <value of --case_id as a wikilink e.g. [[INC-4821]], or `None` if not provided>

## Summary of Findings

<2–5 sentence narrative summary of what the query found and what is notable or suspicious>

## Suspicious Patterns

<For each pattern found:>

### <Pattern Name>

- **Description:** <what was observed>
- **Count:** <number of occurrences if determinable>
- **Key Indicators:** <specific IPs, users, processes, rule IDs observed>
- **ATT&CK:** [[TXXXX]] — <Technique Name>

## ATT&CK Technique Mapping

| Technique | Name | Tactic |
|-----------|------|--------|
| [[TXXXX]] | <Name> | <Tactic> |

## Raw Query

```json
<the DSL query body, pretty-printed>
```

## Result Statistics

- **Total Hits:** <hits.total.value>
- **Returned for Analysis:** <number of hits.hits analyzed>
- **Index Pattern:** `wazuh-archives-*`
- **Timerange Applied:** `<timerange>`

<If aggregations were present, summarize top buckets here>

## Top Results

<For each of the first 5 hits, a brief one-line summary: timestamp | agent | rule.id | rule.description or equivalent fields>

## Analyst Notes

<!-- Add your observations, context, and next steps here -->

- [ ] Validate findings against baseline behavior
- [ ] Cross-reference with [[asset inventory]] if applicable
- [ ] Escalate if confirmed malicious
```

### 9. Save the output file

- Use the `--output_dir` value as the target directory (default: `investigations/`). Treat relative paths as relative to the current working directory.
- Create the directory if it does not exist.
- Generate a filename: `<YYYY-MM-DD>-<query-file-basename-without-extension>.md`
- If `--case_id` was provided, prefix the filename: `<case_id>-<YYYY-MM-DD>-<query-file-basename-without-extension>.md`
- Write the markdown to that file.
- Report the full path of the saved file to the user.

### 10. Print a brief summary

After saving, print to the user:
- Total hits
- Number of suspicious patterns found
- ATT&CK techniques mapped
- Path to the saved investigation file
