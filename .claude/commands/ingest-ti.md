---
name: ingest-ti
description: Process a threat intelligence report and extract actionable TTPs
---

# Threat Intelligence Ingestion

Process a threat report URL or pasted content to extract TTPs for simulation.

## Process

1. **Fetch content** (if URL provided)
   - Use defuddle-cli to extract clean content: `defuddle parse <url>`
   - If defuddle unavailable, use web_fetch or ask user to paste content

2. **Extract TTPs** (use extended thinking)
   - Identify attack techniques described in the report
   - Map each to MITRE ATT&CK technique IDs
   - Note the kill chain phase and dependencies
   - Assess confidence level for each mapping

3. **Generate simulation plan**
   - Group techniques by kill chain phase
   - Identify which can be safely simulated in a lab
   - Flag any that require special infrastructure

## Output Format

Save to exercises/YYYY-MM-DD/threat-intel.md with:
- TTP table (Technique, ID, Confidence, Priority)
- Simulation plan grouped by kill chain phase
- Infrastructure requirements
- Detection opportunities
