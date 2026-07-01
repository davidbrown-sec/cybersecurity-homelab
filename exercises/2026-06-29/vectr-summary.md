# Vectr Campaign Entry

**Campaign Name:** Axios npm Supply Chain Compromise — Sapphire Sleet
**Campaign Date:** 2026-06-30 (execution) / 2026-06-29 (TI ingested)
**Threat Actor:** Sapphire Sleet (DPRK) — UNC1069 / STARDUST CHOLLIMA / BlueNoroff / CryptoCore
**Target Organization Asset:** win11v2 (192.168.1.54)
**Source Report:** Microsoft Security Blog, 2026-04-01
**Related notes:** [[threat-intel]], [[findings]], [[report]]

---

## Test Case 1 — T1547.001: Boot or Logon Autostart Execution: Registry Run Keys

| Field | Value |
|---|---|
| Tactic | Persistence |
| Technique | T1547.001 |
| Atomic Test | T1547.001 Test #1 (Reg Key Run) |
| Execution Time | 2026-06-30 23:10:05.038Z |
| Executed Command | `REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /V "Atomic Red Team" /t REG_SZ /F /D "C:\Path\AtomicRedTeam.exe"` |
| Executor | powershell.exe → cmd.exe → reg.exe (PID chain 11208→4392→8104) |
| **Outcome** | **Detected** |
| Detection Source 1 | Wazuh — rules 92052 (level 4), 92041 (level 10) |
| Detection Source 2 | Hayabusa/Sysmon — "Potential Persistence Attempt Via Run Keys Using Reg.EXE" (medium), "Direct Autorun Keys Modification" (medium) |
| MITRE Mapping Accuracy | Correct on both platforms (`attack.t1547.001`) |
| Time to Detect | ~0.7s (alert timestamp vs. event timestamp) |
| Comments | Clean detection, no gaps. |

---

## Test Case 2 — T1036.003: Masquerading: Rename System Utilities

| Field | Value |
|---|---|
| Tactic | Defense Evasion |
| Technique | T1036.003 |
| Atomic Test | Atomic Test #1 pattern (generic binary rename) — **not** the Test #5 (`wt.exe`) variant specified in threat-intel.md; fidelity gap, see notes |
| Execution Time | 2026-06-30 23:10:19.751Z (spawn) → 23:12:20.173Z (terminate) |
| Executed Command | `"cmd.exe" /c copy %SystemRoot%\System32\cmd.exe %SystemRoot%\Temp\lsass.exe & %SystemRoot%\Temp\lsass.exe /B` |
| Executor | powershell.exe → cmd.exe → `C:\Windows\Temp\lsass.exe` (PID chain 11208→9532→3596) |
| Artifact | `C:\Windows\Temp\lsass.exe`, SHA256 `75320A519959CC6D089EA3EBA33C38CACCB7F138A025EA439BC9686CDB79DED4` (== legit cmd.exe hash) |
| **Outcome** | **Detected, with MITRE mapping defect** |
| Detection Source 1 | Wazuh — rule 61625 (level 12, emails), plus 2 supporting parent-chain alerts (92004, 92032) |
| Detection Source 2 | Hayabusa/Sysmon — "LOLBAS Renamed" (high), "System File Execution Location Anomaly" (high), "Potential Defense Evasion Via Binary Rename" (medium) |
| MITRE Mapping Accuracy | **Wazuh: WRONG** (rule 61625 tags T1055/Process Injection) — **Hayabusa: Correct** (`attack.t1036`, `attack.t1036.003`) |
| Time to Detect | ~9.7s (Wazuh rule 61625 fired at 23:10:21.728Z vs. event at 23:10:19.751Z) |
| Comments | Genuine detection gap is a **content/mapping defect**, not a coverage miss. Cross-validated with independent tool (Hayabusa) using different rule source (Sigma community rules) — confirms defect is specific to Wazuh rule 61625, not an inherent classification ambiguity. Remediation: retag rule 61625 to T1036.003, using Hayabusa's "Potential Defense Evasion Via Binary Rename" as a reference model. |

---

## Campaign Summary Stats

- **Techniques executed:** 2 of 19 planned
- **Detection rate:** 2/2 (100%) — both techniques generated alerts on both SIEM/detection platforms
- **Correct MITRE attribution rate:** 1/2 (50%) — T1547.001 correct on both tools; T1036.003 correct on Hayabusa only
- **Findings requiring remediation:** 1 (Wazuh rule 61625 mapping fix)
- **Outstanding:** 17 techniques not yet simulated; Atomic Test #5 (`wt.exe` masquerade) still needed for full TI fidelity on T1036.003
