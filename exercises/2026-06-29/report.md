# Exercise Report — Axios npm Supply Chain Compromise (Sapphire Sleet)

**Exercise dates:** TI ingested 2026-06-29; simulation + EVTX collection 2026-06-30
**Threat actor:** Sapphire Sleet (DPRK) — see [[threat-intel]]
**Target:** win11v2 (192.168.1.54)
**Scope:** 19 TTPs mapped from source intel, 12-step kill chain queued for simulation ([[threat-intel]] § Atomic Execution Sequence)

## Status Summary

| Metric | Value |
|---|---|
| Techniques planned | 19 |
| Techniques validated via SIEM query (this exercise) | 2 — [[T1036.003]], [[T1547.001]] |
| Alerts confirmed firing | Yes — 6 alerts across both techniques |
| Detection gaps found | 1 — MITRE mapping error (see below) |
| Techniques pending validation | 17 |

Only the Defense Evasion / Persistence pairing (T1036.003 + T1547.001) has been queried and confirmed against Wazuh so far. The remaining planned techniques (T1059.007, T1059.001, T1059.005, T1564.003, T1202, T1070.004, T1071.001, T1571, T1082, T1083, T1105, T1027, T1055, T1195.002, T1059.002, T1059.006, T1071.001-adjacent encoding T1132.001) have not yet been queried against `wazuh-alerts-*`/`wazuh-archives-*` in this exercise — see [[threat-intel]] for their planned atomic tests.

## Confirmed Technique: T1036.003 — Masquerading: Rename System Utilities

**Result: CONFIRMED — executed and detected.**

- **Executed:** 2026-06-30 23:10:19–23:12:20 UTC on win11v2
- **Behavior:** `cmd.exe` copied to `C:\Windows\Temp\lsass.exe` and launched from that path (`Image` = lsass.exe, `OriginalFileName` = Cmd.Exe, SHA256 matches legitimate `cmd.exe` exactly)
- **Full process chain and raw event data:** [[findings]]
- **Deviation from plan:** `threat-intel.md` recommended Atomic Test #5 (PowerShell → `wt.exe`/`taskhostw.exe`) for fidelity to the actual Sapphire Sleet TTP. What actually ran matches Atomic Test #1 instead (generic `cmd.exe` → `lsass.exe` rename). Same technique ID, lower fidelity to the specific threat actor behavior — Test #5 (wt.exe masquerade) is still outstanding and should be run separately for full TI fidelity.

**Detection status:** Alert fired — rule `61625` "Sysmon - Suspicious Process - lsass", level 12, `rule.mail: true` (triggers email notification). Fired directly on the process-create event at 23:10:21.728Z. This is a genuine alert in `wazuh-alerts-*`, not just an archive entry — confirmed by direct query.

**Detection gap:** Rule 61625 mis-tags the technique as `T1055` (Process Injection) / tactics Defense Evasion+Privilege Escalation. No injection occurred — this is a rename masquerade. The rule appears to pattern-match on process name (`lsass` in path) without checking `OriginalFileName`/hash, so severity/triage is correct but the MITRE attribution routes incident response toward the wrong technique. Remediation tracked in [[findings]].

## Confirmed Technique: T1547.001 — Registry Run Keys (adjacent)

**Result: CONFIRMED — executed and detected.**

- **Executed:** 2026-06-30 23:10:05–23:10:06 UTC on win11v2, same PowerShell parent session (PID 11208) as the T1036.003 test, ~15s prior
- **Behavior:** `REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /V "Atomic Red Team" /t REG_SZ /F /D "C:\Path\AtomicRedTeam.exe"`
- **Detection status:** Two alerts fired — `92052` (level 4, "Windows command prompt started by an abnormal process") and `92041` (level 10, "Value added to registry key has Base64-like pattern"). Correctly attributed; no mapping issues observed.

## Session Correlation

Both confirmed techniques originated from the same parent `powershell.exe` process (PID 11208), consistent with a single Atomic Red Team test run chaining T1547.001 → T1036.003 back-to-back rather than isolated one-off tests. This matches the kill-chain design in [[threat-intel]] (steps 7–8: T1036.003 #5 then T1547.001 #1), though as noted above the executed T1036.003 test differs from the one specified there.

## Open Follow-ups

- [ ] Run Atomic Test #5 (`wt.exe`/`taskhostw.exe` masquerade) for full fidelity to the Sapphire Sleet TTP, per [[threat-intel]]
- [ ] Fix rule 61625 MITRE mapping (T1055 → T1036.003), or split into a name-based anomaly rule and a confirmed-rename rule — tracked in [[findings]]
- [ ] Query `wazuh-alerts-*`/`wazuh-archives-*` for the remaining 17 planned techniques as each is simulated
- [ ] Confirm Sysmon config captures `OriginalFileName`/`Hashes` across all lab endpoints (DC, Win11A) not just win11v2
- [ ] Continue kill-chain simulation per [[threat-intel]] § Atomic Execution Sequence, starting from step 1 (T1059.007 npm post-install hook) if not already run
