# Home Lab Build Journal — Complete Infrastructure Record
**Course:** Just Hacking / Constructing Defense  
**Domain:** `<REDACTED>.local`  
**Started:** May 2026  
**Status:** Telemetry stack complete ✅

---

## Hardware Overview

| Device | Role | RAM |
|--------|------|-----|
| MacBook (Apple Silicon) | Primary workstation / Windows VM host (Parallels) | 48GB |
| Mini PC #1 | Proxmox primary node | 32GB DDR4 |
| Mini PC #2 | Proxmox secondary node | 16GB DDR4 |
| Raspberry Pi 5 | Tailscale subnet router | — |

Both mini PCs clustered under Proxmox 9.1.  
Remote access via **Tailscale** mesh VPN with Pi 5 as subnet router (Accept Routes enabled).

---

## VM Inventory

| VM | OS | Host | Role | Sysmon |
|----|----|------|------|--------|
| LinuxV | Ubuntu 22.04.5 Desktop | Proxmox node 1 | Vulnerable Linux target (intentionally unpatched) | N/A |
| LinuxA | Ubuntu 22.04.5 Desktop | Proxmox node 1 | Patched Linux analyst machine | N/A |
| Malcolm | Ubuntu 22.04.5 Server | Proxmox node 1 | Network traffic analysis (Zeek, Suricata, PCAP) | N/A |
| DC | Windows Server 2019 | Proxmox node 2 | Domain Controller + DNS + Splunk SIEM | ✅ |
| Certer | Windows Server 2019 | Proxmox node 2 | ADCS Enterprise Root CA | — |
| Win11A | Windows 11 | MacBook (Parallels) | Patched Windows workstation — domain joined | ✅ |
| Win11V | Windows 11 | MacBook (Parallels) | Vulnerable Windows workstation — domain joined | ✅ |

---

## Phase 1 — Proxmox Cluster Setup

- Installed Proxmox VE 9.1 on both mini PCs
- Configured no-subscription repository using `.sources` format
  - Proxmox 9.1 uses `/etc/apt/sources.list.d/*.sources`, not `.list` — older guides need updating
- Created cluster on node 1 and joined node 2
- Verified cluster quorum

**Key lesson:** Proxmox 9.1 is based on Debian Trixie (not bookworm). Community repo configs from older guides need updating to match.

---

## Phase 2 — Tailscale Remote Access

- Installed Tailscale on Pi 5
- Configured Pi 5 as subnet router advertising the local LAN subnet
- Enabled Accept Routes in Tailscale admin console
- Enabled MagicDNS
- Installed Tailscale on MacBook for remote lab access
- Verified full mesh VPN connectivity to all Proxmox nodes

---

## Phase 3 — Linux VMs on Proxmox Node 1 (LinuxV + LinuxA)

- Downloaded Ubuntu 22.04.5 Desktop ISO
  - Note: Ubuntu 22.04.3 no longer hosted on official mirrors — must use 22.04.5
- Created both VMs with VirtIO disk and network drivers
  - VirtIO drivers are built into the Linux kernel — no extra driver ISO required
- Set static IPs via `/etc/network/interfaces` with `dns-nameservers` for permanence
- LinuxV: left intentionally unpatched to serve as vulnerable target
- LinuxA: fully patched analyst workstation
- Took post-install snapshots of both VMs

---

## Phase 4 — Malcolm (Network Traffic Analysis)

- Installed Ubuntu 22.04.5 Server on Proxmox node 1
- Cloned Malcolm repo — pull from `ghcr.io/idaholab/malcolm` (not `ghcr.io/cisagov/malcolm`)
- Ran Malcolm configuration wizard (`./scripts/configure`)
- Installed Docker Compose v5.1.3 manually to `/usr/local/bin/docker-compose`
  - The `apt` version is too old for Malcolm
- Malcolm startup: always use `cd ~/Malcolm && ./scripts/start` — do NOT use `docker-compose up -d` directly
- Malcolm TLS cert lives inside the Docker container — use `docker cp` to extract
- Took post-install snapshot

**Pending:** Set Malcolm IP to static + post-config snapshot.

---

## Phase 5 — Domain Controller (DC)

- Created VM on Proxmox node 2 using Windows Server 2019 ISO + VirtIO drivers ISO
  - VirtIO drivers ISO required for both disk AND network controllers during install
- Installed Windows Server 2019 (Desktop Experience)
- Set static IP, disabled IPv6 on the NIC (prevents domain join failures due to IPv6 DNS priority)
- Installed AD DS role and promoted server to Domain Controller:
  - New forest: `<REDACTED>.local`
  - Domain functional level: Windows Server 2016
- Disabled Windows Firewall:
  ```powershell
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
  ```
- Took post-promotion snapshot

---

## Phase 6 — Certer (ADCS / Certificate Authority)

- Created VM on Proxmox node 2
- Installed Windows Server 2019, set static IP, disabled IPv6
- Joined to domain
- Installed AD CS role as Enterprise Root CA
- Sysmon not installed on Certer (course does not require it)
- Took post-install snapshot

---

## Phase 7 — Windows 11 Workstations (Win11A + Win11V)

- Apple Silicon does not support Windows Server — workstations hosted in Parallels on MacBook
- Parallels uses a shared network (separate subnet from LAN)
- Bridged networking is unreliable on Apple Silicon — shared network with static route workaround used
- Set static IPs on both, manual DNS pointed to DC
- Disabled IPv6 on both NICs
- Joined both to domain
- Took post-join snapshots

---

## Phase 8 — Sysmon Deployment

**Hosts:** DC, Win11A, Win11V

- DC (Proxmox, x86_64): standard `Sysmon64.exe`
- Win11A + Win11V (Parallels, ARM64): required `Sysmon64a.exe`
  - Standard x86 Sysmon driver is blocked by HVCI on ARM64 — must use ARM64 binary
  - Broken installs: use `reg delete HKLM\SYSTEM\CurrentControlSet\Services\SysmonDrv` + reboot to clean up
- Installed with SwiftOnSecurity config on all three hosts
- Sysmon NOT installed on Certer (course does not require)

---

## Phase 9 — Cloud Accounts

- Azure account provisioned, Entra ID tenant created
- AWS account provisioned
- Both accounts prepared for cloud telemetry modules

---

## Phase 10 — Windows Auditing & GPO

Group Policy settings applied via new GPO linked to the domain:

| Setting | Value |
|---------|-------|
| PowerShell Module Logging | Enabled |
| PowerShell Script Block Logging | Enabled |
| PowerShell Transcription | Enabled — output to `C:\Transcripts` |
| PowerShell Script Execution Policy | Not Configured |
| Windows Defender Antivirus | Turned off |
| Real-Time Protection | Disabled via policy |

- Created `C:\Transcripts` on DC manually
- Ran `gpupdate /force` on all Windows machines
- Win11 hosts may need Defender disabled manually when testing certain payloads

---

## Phase 11 — Splunk Enterprise on DC

- Installed Splunk Enterprise on DC (co-hosted per course plan)
- Created indexes: `winlogs`, `sysmon`, `linux`, `kube`, `aws`, `azure`
- Deployed Splunk Universal Forwarder on DC, Win11A, Win11V, Certer
- Configured Windows Event Log inputs for Security, System, Application, PowerShell logs
- Sysmon logs forwarded to `sysmon` index

**Key lessons:**
- Use `sudo bash << 'EOF'` for multi-line install scripts on Linux — `sudo` on first command only leaves remaining lines unprivileged
- Course scripts use placeholder IPs — always replace with actual DC IP before running
- Splunk TAs ship with inputs disabled — restart Splunk after each TA deployment

---

## Phase 12 — Linux Telemetry (Laurel / auditd)

**Host:** LinuxV only (victim machine)

- Installed and configured `auditd` on LinuxV
- Installed `Laurel` as an auditd plugin (converts output to JSON)
  - `systemctl status laurel` → "not found" is normal — Laurel runs as an auditd plugin, not a systemd service
- Installed Splunk Universal Forwarder on LinuxV
- Configured forwarder to ship Laurel JSON logs to `linux` index
- LinuxA does NOT need a forwarder

---

## Phase 13 — Kubernetes Monitoring (Minikube)

**Host:** LinuxV

- Installed Minikube on LinuxV
- Configured Kubernetes audit policy:
  - Created directory `~/.minikube/files/etc/ssl/certs/` before writing audit policy — path must exist first
  - Started Minikube with audit policy flag
- Configured Splunk HEC input on DC — disabled SSL on HEC global settings for plain HTTP
- Deployed Splunk Connect for Kubernetes via Helm chart pointed to HEC endpoint
- Logs flowing to `kube` index

---

## Phase 14 — Sysmon ARM64 Fix + Forwarder Cleanup

- Confirmed ARM64 Sysmon binary required for Win11A + Win11V (Parallels / Apple Silicon)
- Cleaned up broken Sysmon installs using `reg delete` + reboot pattern
- Verified all three Sysmon hosts reporting to `index=sysmon`
- Confirmed `index=winlogs` has all 4 Windows hosts

---

## Phase 15 — AWS CloudTrail Telemetry

**Date:** 2026-06-03

### Architecture
AWS CloudTrail trail configured to log all management events across all regions, writing to S3. Splunk AWS TA (v8.1.2) polls the S3 bucket via Generic S3 input.

### Setup
- CloudTrail trail: multi-region, logging to S3
- Splunk: Generic S3 input, `sourcetype=aws:cloudtrail`, `index=aws`

### Problem & Fix
Initial input created with `sourcetype=aws:s3:accesslogs`. Source type cannot be edited after creation.  
**Fix:** Delete and recreate with correct source type (`aws:cloudtrail`).

### Result
80 CloudTrail events in `index=aws` ✅  
Fields: `awsRegion`, `eventCategory: Management`, `eventName`, `eventSource`, `eventType: AwsApiCall`

---

## Phase 16 — Azure / Entra ID Telemetry

**Date:** 2026-06-03

### Architecture
Azure/Entra ID sign-in and audit logs ingested via Splunk Add-on for Microsoft Cloud Services.

### Result
43 Azure/Entra events in `index=azure` ✅  
Fields: `category: MicrosoftServicePrincipalSignInLogs`, `operationName: Sign-in activity`, `resultSignature: SUCCESS`

### Verification
```splunk
index=azure earliest=-24h
```

---

## Telemetry Stack — Complete ✅

| Index | Source | Status |
|-------|--------|--------|
| `winlogs` | DC, Win11A, Win11V, Certer | ✅ |
| `sysmon` | DC, Win11A, Win11V | ✅ |
| `linux` | LinuxV (Laurel/auditd) | ✅ |
| `kube` | LinuxV (Minikube audit logs) | ✅ |
| `aws` | AWS CloudTrail | ✅ |
| `azure` | Azure/Entra sign-in logs | ✅ |

All 6 indexes live. Telemetry collection phase complete.

---

## Key Lessons — Full Reference

| Topic | Lesson |
|-------|--------|
| Proxmox 9.1 repos | `.sources` format; use `Enabled: no` not comment-out |
| Proxmox 9.1 Debian base | Trixie, not bookworm |
| DNS permanence | Set `dns-nameservers` in `/etc/network/interfaces` |
| Ubuntu ISO | 22.04.3 no longer hosted; use 22.04.5 |
| Docker Compose | Install v5.1.3 manually; apt version too old for Malcolm |
| Malcolm image source | Pull from `ghcr.io/idaholab/malcolm`, not `ghcr.io/cisagov/malcolm` |
| Malcolm startup | Never run as root; use `./scripts/start` from `~/Malcolm` |
| Malcolm certs | Cert lives inside Docker container — use `docker cp` to extract |
| Apple Silicon | No Windows Server ARM support — use x86_64 Proxmox for DC/Certer |
| Parallels networking | Shared network on separate subnet — use static route + manual DNS |
| Parallels bridged | Unreliable on Apple Silicon — use shared network workaround |
| VirtIO drivers | Required for disk AND network during Windows Server install on Proxmox |
| VirtIO on Linux | VirtIO drivers built into Linux kernel — no extra ISO needed |
| IPv6 DNS priority | Disable IPv6 on adapter if domain join fails |
| GPO PowerShell logging | Module Logging + Script Block + Transcription all enabled via GPO |
| Defender via GPO | Must set both Antivirus AND Real-Time Protection policies |
| Splunk TA inputs | TAs ship with inputs disabled — restart Splunk after app deployment |
| Splunk Linux install | Use `sudo bash << 'EOF'` — `sudo` on first command only leaves rest unprivileged |
| Splunk course IPs | Course scripts use placeholder IPs — always replace with actual DC IP |
| Sysmon on ARM64 | Use `Sysmon64a.exe` on ARM64 Windows — x86 driver blocked by HVCI |
| Sysmon broken install | Use `reg delete` + reboot to clean up stuck Sysmon service |
| Laurel service | Laurel runs as auditd plugin — `systemctl status laurel` not found is normal |
| Linux forwarder scope | Only LinuxV (victim) needs the Splunk forwarder |
| Minikube audit dir | Create `~/.minikube/files/etc/ssl/certs/` before writing audit policy |
| Splunk HEC SSL | Disable SSL on HEC global settings for plain HTTP helm chart endpoint |
| Splunk AWS TA source type | Cannot edit source type after input creation — delete and recreate if wrong |
| AWS CloudTrail region | Specify correct AWS region in Splunk input or logs won't be found |

---

## Build Pending Items

- [ ] Set Malcolm IP to static
- [ ] Take post-config Malcolm snapshot
- [ ] Create domain users in AD (for attack labs)
- [ ] PCAP lab exercises with Malcolm and Zeek
