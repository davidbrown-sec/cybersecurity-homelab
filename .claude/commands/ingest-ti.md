---
name: ingest-ti
description: Ingest a threat intelligence report URL and extract TTPs, IOCs, and a simulation plan
arguments:
  - name: url
    description: URL to the threat intel report
    required: true
---

# Threat Intelligence Ingestion

## Step 1: Extract Content

Run defuddle to get clean content from the URL:
defuddle parse "$url" --format markdown

## Step 2: Analyze the Content

Identify:
- Campaign/threat actor name, target industries, time period
- TTPs mapped to MITRE ATT&CK (ID, how used, confidence level)
- IOCs: IPs, domains, hashes, file paths, registry keys

## Step 3: Simulation Plan

Suggest Atomic Red Team tests for identified techniques. Prioritize high confidence techniques with available atomic tests.

## Step 4: Output

Save to analysis/ti-[date]-[campaign-name].md with YAML frontmatter including source URL and date.
