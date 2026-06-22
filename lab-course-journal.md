# Course Lab Journal
**Course:** Just Hacking / Constructing Defense  
**Domain:** `<REDACTED>`  
**Started:** June 2026

This journal tracks hands-on course labs as they are completed. Each entry records the objective, steps taken, what was observed in telemetry, and any gotchas encountered.

---

## How to Use This Journal

Each lab entry follows this structure:

```
## Lab [N] — [Lab Name]
**Module:** [Course module name]
**Date:** YYYY-MM-DD
**Status:** [ ] In Progress | [x] Complete

### Objective
What the lab is trying to demonstrate or teach.

### Steps Taken
Numbered steps of what was actually done.

### Telemetry / Detections
What showed up in Splunk, Malcolm, or logs.

### Notes & Gotchas
Anything unexpected, fixes required, or lessons learned.
```

---

## Labs

<!-- Add new lab entries below this line -->

---

## Lab 1 — Our Second Shell: Exploring the Network Layer
**Module:** 06 - Our Second Shell  
**Date:** 2026-06-13  
**Status:** [x] Complete (Malcolm analysis done; Splunk queries pending license reset)

### Objective
Use Metasploit's PSExec module to remotely execute a payload on a victim Windows host using valid domain admin credentials, then analyze the resulting network telemetry in Malcolm. The focus is on extracting investigative value from packet captures — NTLM authentication details, JA3/JA4 TLS fingerprints, certificate thumbprints, and connection baselining — even when traffic is encrypted.

### Steps Taken

1. Confirmed victim host (Win11V) IP address via bridged USB-C Ethernet adapter on Parallels
2. Confirmed attacker host (LinuxA) IP address on Proxmox
3. Disabled Windows Defender on Win11V via registry key:
   ```
   reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f
   ```
4. Disabled Windows Firewall on Win11V:
   ```powershell
   Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
   ```
5. Configured and launched Metasploit PSExec module with x86 payload (x64 payloads fail on ARM64 Windows)
6. Captured traffic on LinuxA using tcpdump, uploaded PCAP to Malcolm
7. Analyzed sessions in Arkime

### Telemetry / Detections

**Malcolm / Arkime — NTLM Authentication**

Query: `ip == <attacker IP> && ip == <victim IP> && protocols == ntlm`

Administrator authenticated from LinuxA to Win11V on port 445. Action: Authenticate → Result: Success. Extracted entirely from packet capture with no host-based logging required.

**Malcolm / Arkime — TLS Session Analysis**

- JA3: `0696c16261fe58808f9fa965be137acd`
- JA3s: `ec74a5c51106f0419184d0dd08fb05bc`
- Certificate Thumbprint: `da:9e:2c:b8:93:e7:0d:a1:a2:98:99:98:67:d3:e5:e2:e6:6b:38:45` (self-signed, Metasploit-generated)

**Splunk — Command Line Length Detection**

```splunk
index=sysmon
| where EventCode = 1
| eval CommandLineLength = len(CommandLine)
| eval ParentCommandLineLength = len(ParentCommandLine)
| where (ParentCommandLineLength > 2500 OR CommandLineLength > 2500)
| where ParentImage != "C:\\Windows\\explorer.exe"
| table CommandLine,ProcessGuid
```

### Notes & Gotchas

- Parallels bridged networking via Wi-Fi fails on Apple Silicon — use USB-C Ethernet adapter with dual-adapter setup
- x64 Metasploit payloads fail silently on ARM64 Windows — use x86 payloads
- Malcolm requires manual PCAP upload; does not auto-capture LAN traffic without SPAN port

---

## Lab 2 — Credential Access: File Shares
**Module:** 09 - Credential Access on Windows Hosts - File Shares  
**Date:** 2026-06-21  
**Status:** [x] Complete  
**MITRE:** T1552.001, T1135, T1039

### Objective
Detect credential access through SMB file shares using Windows Event ID 5145 (Detailed File Share audit). Create test shares and a low-privileged user, run Snaffler to enumerate shares and find sensitive files, then build detections for sensitive file access and high-volume share enumeration failures.

### Steps Taken

1. Enabled Detailed File Share auditing on DC (not enabled by default):
   ```powershell
   auditpol /set /subcategory:"Detailed File Share" /success:enable /failure:enable
   ```
2. Created `lowpriv` AD user denied access to test shares
3. Created 15 test SMB shares on DC:
   ```powershell
   $numbers = 1..15
   foreach($number in $numbers) {
       New-Item "C:\Shares\Share$number" -itemType Directory
       New-SmbShare -Name "Logs$number" -Path "C:\Shares\Share$number" -NoAccess lowpriv -FullAccess 'Everyone'
   }
   ```
4. Created `passwords.txt` in Logs1 share as a sensitive file target
5. Validated Event ID 5145 telemetry from Win11A:
   - Successful share browse → 5145 with `Relative Target Name: \`, access granted
   - Denied access as `lowpriv` → 5145 with explicit deny ACE
   - File-level access → 5145 with `Relative Target Name: passwords.txt`
6. Downloaded Snaffler v1.0.126 to Win11A (Defender + Tamper Protection disabled first)
7. Ran Snaffler as Administrator — found `passwords.txt` plus real sensitive files including `unattend.xml` with credential material left from OS installation
8. Ran Snaffler as `lowpriv` — generated bulk failure telemetry against all 15 denied shares
9. Built and validated detection queries in Wazuh (Splunk license hard-blocked)

### Telemetry / Detections

**Wazuh — Sensitive File Access Detection**

```
data.win.system.eventID: 5145 AND data.win.eventdata.relativeTargetName: *password*
```
Result: 19 hits — caught `passwords.txt` plus Splunk `remote-password-management` files from Snaffler's C$ crawl.

**Wazuh — Share Enumeration by Account**

```
data.win.system.eventID: 5145 AND data.win.eventdata.subjectUserName: lowpriv
```
Result: 116 hits — spike in histogram corresponds to Snaffler run timing.

**Key field mappings in Wazuh for Event ID 5145:**
- `data.win.eventdata.shareName` — share path
- `data.win.eventdata.relativeTargetName` — filename within share (`\` = share root browse)
- `data.win.eventdata.subjectUserName` — account performing access
- `data.win.eventdata.ipAddress` — source IP
- `data.win.system.severityValue` — `AUDIT_SUCCESS` or `AUDIT_FAILURE`

### Notes & Gotchas

- **Event ID 5145 requires manual auditpol enablement** — `Detailed File Share` subcategory is off by default
- **auditpol vs GPO:** Local auditpol settings can be overwritten on next gpupdate if a GPO defines audit policy — proper fix is to configure via Advanced Audit Policy Configuration in GPO
- **Snaffler v1.0.126 required** — latest version was broken at time of course writing
- **Defender + Tamper Protection:** Must disable Tamper Protection in Windows Security UI before registry-based Defender disable will stick
- **Real finding:** Snaffler found `unattend.xml` at `ADMIN$\Panther\` containing redacted credential material from Windows installation — demonstrates real-world impact of share enumeration
- **SYSVOL/ADMIN$ noise:** These shares generate thousands of 5145 events and must be filtered for file share crawling detections

---

## Lab 3 — Credential Access: DCSync
**Module:** 11 - Credential Access on Windows Hosts - DCSync  
**Date:** 2026-06-21  
**Status:** [x] Complete  
**MITRE:** T1003.006

### Objective
Execute a DCSync attack using Mimikatz to replicate Active Directory credentials from the domain controller, then detect it using Windows Event ID 4662 (directory service object access) correlated with Event ID 4624 (logon) to identify the source as a workstation rather than a legitimate DC.

### Steps Taken

1. Enabled Directory Service Access auditing on DC:
   ```powershell
   auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
   ```
2. Downloaded and extracted Mimikatz to Win11A
3. Executed DCSync from Mimikatz on Win11A:
   ```
   lsadump::dcsync /domain:<REDACTED> /user:Administrator
   ```
4. Mimikatz successfully replicated Administrator credentials including NTLM hash and Kerberos keys
5. Queried Wazuh for Event ID 4662 with DCSync replication GUID
6. Correlated 4662 logon ID with 4624 to identify source IP as Win11A (a workstation)

### Telemetry / Detections

**Wazuh — DCSync Detection (Event ID 4662)**

```
data.win.system.eventID: 4662 AND data.win.eventdata.properties: *1131f6ad*
```
Result: 1 hit — GUID `{1131f6ad-9c07-11d1-f79f-00c04fc2dcd2}` (DS-Replication-Get-Changes-All) confirmed in properties field.

**Wazuh — Logon Correlation (Event ID 4624)**

```
data.win.system.eventID: 4624 AND data.win.eventdata.targetLogonId: <logon ID from 4662>
```
Result: 1 hit — source IP confirmed as Win11A (a workstation). Authentication via Kerberos, Logon Type 3. Only domain controllers should perform AD replication — replication from a workstation IP is definitive DCSync evidence.

**Key detection logic:**
- Event 4662 fires when directory replication rights are exercised
- GUID `{1131f6ad-9c07-11d1-f79f-00c04fc2dcd2}` = DS-Replication-Get-Changes-All
- Joining with 4624 via LogonId exposes the source IP
- Source IP not belonging to a DC = confirmed attack

### Notes & Gotchas

- **Event ID 4662 requires manual auditpol enablement** — `Directory Service Access` subcategory is off by default
- **Splunk license hard-blocked** — all queries run in Wazuh; field names differ from course SPL examples
- **Malcolm network detection skipped** — `zeek.notice.msg == drsuapi::DRSGetNCChanges` would detect this at the network layer but Malcolm has no live capture configured without a SPAN port

---

<!-- Template for future labs — copy and paste below -->
<!--
## Lab N — [Lab Name]
**Module:**  
**Date:**  
**Status:** [ ] In Progress

### Objective


### Steps Taken
1. 

### Telemetry / Detections
```splunk

```

### Notes & Gotchas

-->
