---
name: query
description: Run a Wazuh OpenSearch query, map results to ATT&CK, and generate investigation notes
---

# SIEM Query and Documentation

Run a query against Wazuh OpenSearch and generate Obsidian-compatible investigation notes.

## Process

1. **Build the query**
   - Translate the user's request into OpenSearch DSL JSON
   - Target index: wazuh-archives-*

2. **Execute the query**
   - Use curl with WAZUH_USER and WAZUH_PASS env vars
   - Endpoint: https://localhost:9200/wazuh-archives-*/_search
   - Use -sk flag for SSL
   - SSH tunnel must be active: ssh -L 9200:127.0.0.1:9200 user@192.168.1.224

3. **Analyze results**
   - Identify key findings
   - Map to ATT&CK techniques where applicable
   - Note anomalies or items needing follow-up

4. **Generate Obsidian notes**
   - Use [[backlinks]] for techniques, IOCs, investigations
   - Save to exercises/YYYY-MM-DD/findings.md

## Output Format

- Query details and hit count
- Key findings summary
- ATT&CK mapping with [[backlinks]]
- Follow-up actions checklist
