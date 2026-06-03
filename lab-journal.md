# Home Lab Build Journal
**Course:** Just Hacking  
**Domain:** `<REDACTED>.local`  
**Started:** May 2026

---

## Hardware Overview

| Device | Role | RAM |
|--------|------|-----|
| MacBook (Apple Silicon) | Primary workstation / Windows VM host (Parallels) | 48GB |
| Mini PC #1 | Proxmox primary VM host | 32GB DDR4 |
| Mini PC #2 | Proxmox secondary VM host | 16GB DDR4 |
| Raspberry Pi 5 | Tailscale subnet router | — |

Remote access via **Tailscale** mesh VPN with Pi 5 as subnet router.

---

## VM Inventory

| VM | OS | Host | Role | Sysmon |
|----|----|------|------|--------|
| LinuxV | Ubuntu 22.04.5 Desktop | Proxmox node 1 | Vulnerable Linux target (intentionally unpatched) | N/A |
| LinuxA | Ubuntu 22.04.5 Desktop | Proxmox node 1 | Patched Linux analyst machine | N/A |
| Malcolm | Ubuntu 22.04.5 Server | Proxmox node 1 | PCAP / network traffic analysis | N/A |
| DC | Windows Server 2019 | Proxmox node 2 | Domain Controller + DNS + Splunk SIEM | ✅ |
| Certer | Windows Server 2019 | Proxmox node 2 | ADCS Enterprise Root CA | — |
| Win11A | Windows 11 | MacBook (Parallels) | Patched Windows workstation — domain joined | ✅ |
| Win11V | Windows 11 | MacBook (Parallels) | Vulnerable Windows workstation — domain joined | ✅ |

> Sysmon installed on DC, Win11A, Win11V. ARM64 Windows (Parallels) requires `Sysmon64a.exe`. Not required on Certer per course curriculum.

All Proxmox VMs use: **q35 / OVMF (UEFI) / VirtIO** with QEMU guest agent.

---

## Phase 1 — Planning & Hardware Assessment

### Key decisions
- Node 1 (32GB): LinuxV, LinuxA, Malcolm
- Node 2 (16GB): DC, Certer
- MacBook (Parallels): Win11A, Win11V
- DC moved from UTM to Proxmox to enable snapshots
- Win11A/Win11V use Parallels instead of UTM — Parallels supports ARM Windows 11 natively

### Lessons learned
- Verify RAM specs physically
- Apple Silicon has no Windows Server ARM support — use x86_64 Proxmox for DC
- Parallels shared network puts VMs on a separate subnet from the lab LAN

---

## Phase 2 — Proxmox Installation & Configuration

**Proxmox version:** 9.1 (Debian **trixie** base)

### Proxmox 9.1 — key differences from older versions

| Topic | Detail |
|-------|--------|
| Debian base | **trixie** (not bookworm) |
| Repo file format | `.sources` (not `.list`) |
| Disabling enterprise repo | Set `Enabled: no` — commenting out the `deb` line does NOT work |
| DNS permanence | Must add `dns-nameservers` to `/etc/network/interfaces` |

### No-subscription repo config
```
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Enabled: yes
```

---

## Phase 3 — VM Builds (Linux)

### Ubuntu ISO note
Course specifies Ubuntu 22.04.3 LTS — **no longer hosted**. Use **Ubuntu 22.04.5 LTS** instead.

### Malcolm — PCAP analysis
Running **Malcolm 26.04.1** via Docker.

**Problem: Docker Compose version too old**  
Fix: Install Docker Compose v5.1.3 manually:
```bash
sudo curl -L "https://github.com/docker/compose/releases/download/v5.1.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
```

---

## Phase 4 — Malcolm Static IP

```yaml
network:
  version: 2
  ethernets:
    <INTERFACE>:
      dhcp4: no
      addresses:
        - <YOUR_MALCOLM_IP>/24
      routes:
        - to: default
          via: <YOUR_GATEWAY>
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

---

## Phase 5 — Malcolm SSL Certificate Trust (macOS)

```bash
# Extract cert from Docker container
docker cp malcolm-nginx-proxy-1:/etc/nginx/certs/cert.pem /home/<user>/malcolm.crt

# Copy to Mac
scp <user>@<malcolm-ip>:/home/<user>/malcolm.crt ~/Desktop/malcolm.crt

# Trust via Terminal (GUI import fails)
sudo security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain ~/Desktop/malcolm.crt
```

---

## Phase 6 — Domain Controller (DC) Build

- OS: Windows Server 2019
- Machine: q35 / OVMF / VirtIO, 2 cores, 6GB RAM, 60GB disk
- VirtIO drivers required for disk (`vioscsi\2k19\amd64`) and network (`NetKVM\2k19\amd64`)
- Role: AD DS, promoted to domain controller
- Domain: `<REDACTED>.local`, Forest/Domain functional level: Windows Server 2016
- DNS + Global Catalog enabled
- Firewall disabled: `Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False`
- Sysmon installed and enabled ✅
- Snapshot taken post-promotion

---

## Phase 7 — Certer (ADCS) Build

- OS: Windows Server 2019
- Machine: q35 / OVMF / VirtIO, 2 cores, 4GB RAM, 60GB disk
- Joined to domain, DNS pointing to DC
- IPv6 disabled (was overriding IPv4 DNS)
- ADCS: Enterprise CA, Root CA, RSA 2048-bit, SHA256, 5 year validity
- CA name: `<REDACTED>-CERTER-CA`
- Sysmon: not required per course curriculum
- Snapshot taken post-configuration

**Problem: Domain join failed**  
IPv6 DNS taking priority over IPv4.  
Fix: Disable IPv6 on adapter via `ncpa.cpl`.

---

## Phase 8 — Windows 11 Workstations

### Network architecture
Parallels on Apple Silicon uses shared network (separate subnet from lab LAN). Bridged networking unreliable on Apple Silicon. Working solution:
- Static IPs on Parallels shared network
- DNS manually set to DC IP via elevated PowerShell
- IPv6 disabled on adapter
- Static route added on Mac: `sudo route add -net <LAB_SUBNET> <PARALLELS_GATEWAY>`

### Win11A — Patched workstation
- Parallels shared network, static IP assigned
- DNS: DC IP
- Domain joined ✅
- Account type: Administrator
- Sysmon installed and enabled ✅
- Snapshot: `clean-domain-joined`

### Win11V — Vulnerable workstation
- Parallels shared network, static IP assigned
- DNS: DC IP
- Domain joined ✅
- Account type: Standard User (realistic victim)
- Sysmon installed and enabled ✅
- Snapshot: `clean-domain-joined`

**Common problems:**
- Domain join fails — Parallels DNS via IPv6 taking priority. Fix: disable IPv6, set DNS manually as Administrator.
- Bridged networking shows "Media disconnected" on Apple Silicon. Fix: use shared network with manual DNS.

---

## Phase 9 — Cloud Accounts

### Microsoft Azure
- Account provisioned for course curriculum
- Planned use: cloud telemetry, identity and access management labs, detection engineering

### AWS
- Account provisioned for course curriculum
- Planned use: CloudTrail log analysis, IAM security labs, detection engineering

---

## Phase 10 — Windows Auditing & GPO Configuration

**Date:** 2026-06-01  
**Applied to:** DC (via Group Policy), Win11A, Win11V  

### PowerShell Logging (via GPO)
All three settings configured under:  
`Computer Configuration → Administrative Templates → Windows Components → Windows PowerShell`

| Setting | Value |
|---------|-------|
| Turn on Module Logging | Enabled |
| Turn on PowerShell Script Block Logging | Enabled |
| Turn on PowerShell Transcription | Enabled — output directory: `C:\Transcripts` |
| Turn on Script Execution | Not Configured |

- `C:\Transcripts` folder created on DC
- `gpupdate /force` run on all Windows machines after GPO changes

### Windows Defender (via GPO)
Disabled across the domain to allow payload testing without interference:

| Setting | Value |
|---------|-------|
| Turn off Windows Defender Antivirus | Enabled |
| Turn off Real-Time Protection | Enabled |

> **Note:** Win11 hosts may need Defender disabled manually at test time if GPO doesn't fully suppress it for specific payloads.

---

## Phase 11 — Splunk SIEM Deployment

**Date:** 2026-06-03  
**Host:** DC (co-hosted, per course design)  
**Version:** Splunk Enterprise 9.3.2  

### Architecture
Splunk Enterprise installed directly on the DC. Indexes created for all course telemetry sources. Windows workstations forward via Universal Forwarder on port 9997.

### Indexes created

| Index | Telemetry source |
|-------|-----------------|
| `winlogs` | Windows Event Logs (Security, Application, System) |
| `sysmon` | Sysmon operational events |
| `linux` | Linux auditd/Laurel |
| `azure` | Azure telemetry |
| `aws` | CloudTrail / AWS telemetry |
| `kube` | Kubernetes logs |
| `etw` | ETW (Event Tracing for Windows) |

### Problem & fix — no telemetry after install

**Symptom:** No events in `sysmon` or `winlogs` indexes after running the install script.

**Root cause:** Splunk Technology Add-ons (`Splunk_TA_windows`, `Splunk_TA_microsoft_sysmon`) ship with all inputs **disabled** by default. The course app package provides `local/inputs.conf` overrides to enable them, but Splunk must be restarted after extraction for configs to take effect.

**Fix:** `Restart-Service Splunkd`

**Result:** 51,055 events in `winlogs` within minutes; indexing rate 15.57 KB/s ✅

### Verification queries
```splunk
index=winlogs earliest=-5m
index=sysmon earliest=-5m
index=sysmon OR index=winlogs | stats count by host, sourcetype
```

---

## Phase 12 — Sysmon on Win11A & Win11V (ARM64 Fix)

**Date:** 2026-06-03

### Problem
After the Splunk Universal Forwarder was installed on Win11A and Win11V, `index=sysmon` only showed DC. The forwarder config was correct but no Sysmon events were being generated on either machine.

### Root cause chain

1. **Sysmon service was Stopped** — the service existed in the registry but could not start
2. **Sysmon binary missing from `C:\Windows\`** — the course script downloaded `Sysmon.exe` to `C:\SysmonFiles\` but never ran the installer, so the driver was never actually installed
3. **Install attempts failed: "driver blocked from loading"** — Win11 on Parallels (Apple Silicon) runs ARM64 Windows. The course-downloaded `Sysmon.exe` is an x86 binary. Windows ARM64 blocks x86 kernel drivers via HVCI (Virtualization Based Security / Memory Integrity)
4. **Uninstall was stuck** — broken partial install left the service registered but the driver binary missing, causing `-u force` to fail with "Access is denied"
5. **Sysmon config XML was malformed** — `C:\SysmonFiles\sysmonconfig.xml` contained an invalid XML comment (`<!--SCPTAG: Sysmon Modular-->`), causing config load to fail

### Fix

```powershell
# 1. Clean up broken registry entry
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Sysmon" /f

# 2. Reboot to release kernel driver lock
Restart-Computer -Force

# 3. After reboot — download full Sysmon zip (includes ARM64 binary)
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile "C:\SysmonFiles\Sysmon_new.zip"
Expand-Archive -Path "C:\SysmonFiles\Sysmon_new.zip" -DestinationPath "C:\SysmonFiles\" -Force

# 4. Install using ARM64 native binary
C:\SysmonFiles\Sysmon64a.exe -accepteula -i

# 5. Restart forwarder
Restart-Service SplunkForwarder
```

### Key lesson
**On ARM64 Windows (Parallels on Apple Silicon), use `Sysmon64a.exe`** — not `Sysmon.exe` (x86) or `Sysmon64.exe` (x86-64). The ARM64 native binary is only included in the full Sysmon zip download, not as a standalone download.

| Binary | Architecture | Works on ARM64 Windows |
|--------|-------------|----------------------|
| `Sysmon.exe` | x86 (32-bit) | ❌ Driver blocked by HVCI |
| `Sysmon64.exe` | x86-64 | ❌ Driver blocked by HVCI |
| `Sysmon64a.exe` | ARM64 native | ✅ |

### Result
All three hosts reporting to `index=sysmon`: **DC, WIN11A, WIN11V** ✅

---

## Key Lessons Summary

| Topic | Lesson |
|-------|--------|
| Proxmox 9.1 repos | `.sources` format; `Enabled: no` not comment-out |
| Ubuntu ISO | 22.04.3 no longer hosted; use 22.04.5 |
| Docker Compose | Install v5.1.3 manually; apt version too old for Malcolm |
| Malcolm startup | Never run as root |
| Apple Silicon | No Windows Server ARM support — use Proxmox for DC |
| UTM/Parallels snapshots | No snapshot support in UTM; use Proxmox for VMs needing snapshots |
| Parallels networking | Shared network on separate subnet — use static route + manual DNS |
| Parallels bridged | Unreliable on Apple Silicon — use shared network workaround |
| VirtIO drivers | Required for disk AND network during Windows Server install |
| IPv6 DNS priority | Disable IPv6 on adapter if domain join fails |
| ADCS Enterprise CA | Requires domain admin credentials, not local admin |
| PowerShell DNS cmds | Must run as Administrator |
| GPO PowerShell logging | Module Logging + Script Block + Transcription all enabled via GPO |
| Defender via GPO | Must set both Antivirus AND Real-Time Protection policies to fully disable |
| Win11 Defender | May need manual disable at test time even with GPO applied |
| Splunk TA inputs | TAs ship with inputs disabled — restart Splunk after app deployment for configs to load |
| Sysmon on ARM64 | Use `Sysmon64a.exe` on ARM64 Windows (Parallels/Apple Silicon) — x86 driver blocked by HVCI |
| Sysmon config XML | Course sysmonconfig.xml may have malformed XML comments — install without config if needed |
| Sysmon broken install | Use `reg delete` + reboot to clean up a stuck Sysmon service before reinstalling |

---

## Pending

- [x] DC setup
- [x] Certer setup
- [x] Win11A — domain joined
- [x] Win11V — domain joined
- [x] Sysmon — DC, Win11A, Win11V all live in index=sysmon ✅
- [x] Azure account provisioned
- [x] AWS account provisioned
- [x] Windows Auditing & GPO configured
- [x] PowerShell Module Logging, Script Block Logging, Transcription enabled via GPO
- [x] Windows Defender disabled via GPO
- [x] C:\Transcripts folder created on DC
- [x] gpupdate /force run on all Windows machines
- [x] Splunk Enterprise deployed — winlogs and sysmon live from all 3 hosts ✅
- [ ] Domain user accounts
- [ ] PCAP lab exercises
- [ ] Cloud telemetry lab exercises
