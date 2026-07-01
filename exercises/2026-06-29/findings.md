# Findings — 2026-06-29 Exercise

## Query: T1036.003 LOLBAS Rename Detection

**Target:** win11v2 (192.168.1.54)
**Index:** `wazuh-archives-*`
**Search:** cmd.exe / lsass.exe process activity around 23:10:19 UTC on 2026-06-30
**Hits:** 35 (filtered), full process chain confirmed

### Query

```json
{
  "query": {
    "bool": {
      "must": [
        { "match_phrase": { "agent.name": "win11v2" } },
        { "range": { "@timestamp": { "gte": "2026-06-30T23:10:00", "lte": "2026-06-30T23:12:30" } } }
      ]
    }
  }
}
```

## Key Findings

Confirmed a **rename-and-execute masquerade**: `cmd.exe` was copied to `C:\Windows\Temp\lsass.exe` and launched from that path, matching [[T1036.003]] — Masquerading: Rename System Utilities.

### Process Chain

| Time (UTC) | EID | PID | Image | OriginalFileName | Parent | Command Line |
|---|---|---|---|---|---|---|
| 23:10:19.658 | 1 (create) | 9532 | `C:\Windows\System32\cmd.exe` | Cmd.Exe | powershell.exe (11208) | `"cmd.exe" /c copy %SystemRoot%\System32\cmd.exe %SystemRoot%\Temp\lsass.exe & %SystemRoot%\Temp\lsass.exe /B` |
| 23:10:19.751 | 1 (create) | 3596 | **`C:\Windows\Temp\lsass.exe`** | **Cmd.Exe** | cmd.exe (9532) | `C:\WINDOWS\Temp\lsass.exe /B` |
| 23:12:20.173 | 5 (terminate) | 3596 | `C:\Windows\Temp\lsass.exe` | — | — | — |
| 23:12:20.179 | 5 (terminate) | 9532 | `C:\Windows\System32\cmd.exe` | — | — | — |

**Detection signal:** `Image = C:\Windows\Temp\lsass.exe` but `OriginalFileName = Cmd.Exe`, and the process SHA256 (`75320A519959CC6D089EA3EBA33C38CACCB7F138A025EA439BC9686CDB79DED4`) matches the legitimate `cmd.exe` hash exactly — the binary was copied, not swapped for a different tool. This is the canonical Image/OriginalFileName mismatch pattern for rename-based masquerading.

**Additional context:** the same parent PowerShell session (PID 11208) also ran a registry Run-key persistence command ~15s earlier at 23:10:05.038Z:
```
"cmd.exe" /c REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /V "Atomic Red Team" /t REG_SZ /F /D "C:\Path\AtomicRedTeam.exe"
```
Suggests this activity is part of an Atomic Red Team test run chaining multiple techniques ([[T1547.001]] Registry Run Keys, followed by [[T1036.003]] rename masquerade) from a single PowerShell session — consistent with the threat-intel report's planned atomic tests.

## ATT&CK Mapping

- [[T1036.003]] — Masquerading: Rename System Utilities (confirmed via Image/OriginalFileName/hash mismatch)
- [[T1547.001]] — Boot or Logon Autostart Execution: Registry Run Keys (adjacent activity, same session)
- Parent technique: [[T1059.001]] — PowerShell (source of both cmd.exe spawns, PID 11208)

## Alert Validation (wazuh-alerts-*)

Queried `wazuh-alerts-*` for win11v2, 23:09:50–23:12:40 UTC, to confirm this reached alerting (not just `wazuh-archives-*`). **6 alerts fired**, confirming detection worked end-to-end:

| Time (UTC) | Rule ID | Level | Description | PID / PPID |
|---|---|---|---|---|
| 23:10:06.759 | 92052 | 4 | Windows command prompt started by an abnormal process | 4392 / 11208 |
| 23:10:06.759 | 92032 | 3 | Suspicious Windows cmd shell execution | 7988 / 4392 |
| 23:10:06.775 | 92041 | 10 | Value added to registry key has Base64-like pattern | 8104 / 4392 |
| 23:10:21.712 | 92004 | 4 | Powershell process spawned Windows command shell instance | 9532 / 11208 |
| 23:10:21.712 | 92032 | 3 | Suspicious Windows cmd shell execution | 11888 / 9532 |
| **23:10:21.728** | **61625** | **12** | **Sysmon - Suspicious Process - lsass** | **3596 / 9532** |

**Rule 61625** is the direct hit on the rename event itself (fired on the `C:\Windows\Temp\lsass.exe` process-create, `rule.mail: true` — this triggers an email notification given its level-12 severity).

### Mapping gap identified

Rule 61625 tags this alert as **T1055 (Process Injection)** / tactics *Defense Evasion, Privilege Escalation* — but no injection occurred here. The actual technique is **T1036.003 (Masquerading: Rename System Utilities)**: the rule appears to fire on process name pattern-matching (`lsass` in path) rather than validating `OriginalFileName`/hash against the genuine `lsass.exe`. Detection efficacy is fine (it fired, high severity, emailed) but the MITRE tag routes triage/reporting toward the wrong technique.

## Follow-up Actions

- [x] Check whether this activity generated a Wazuh alert already, or only appears in raw archives → **confirmed alert fired** (rule 61625, level 12)
- [ ] Fix rule 61625's MITRE mapping: retag to T1036.003 (Masquerading), or split into two rules — one for name-based anomaly (current behavior) and one for confirmed rename-masquerade (Image/OriginalFileName mismatch + hash match to a different legitimate binary)
- [ ] Confirm Sysmon config captures `OriginalFileName` and `Hashes` fields on all monitored endpoints (required for this detection to fire reliably)
- [ ] Consider a dedicated correlation rule: alert when `data.win.eventdata.image` basename is a sensitive system process name (`lsass.exe`, `svchost.exe`, `csrss.exe`, etc.) AND path is outside `System32`/`SysWOW64`, OR `originalFileName` doesn't match the `image` basename — tagged explicitly as T1036.003
- [ ] Cross-reference PID 11208 (parent powershell.exe) for the full session — confirm this maps to Atomic Red Team `T1036.003` Test #1/#5 execution per `threat-intel.md`
- [ ] Update `report.md` with this confirmed technique execution, detection status, and the T1055/T1036.003 mapping gap
