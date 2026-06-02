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
| DC | Windows Server 2019 | Proxmox node 2 | Domain Controller + DNS | ✅ |
| Certer | Windows Server 2019 | Proxmox node 2 | ADCS Enterprise Root CA | — |
| Win11A | Windows 11 | MacBook (Parallels) | Patched Windows workstation — domain joined | ✅ |
| Win11V | Windows 11 | MacBook (Parallels) | Vulnerable Windows workstation — domain joined | ✅ |

> Sysmon installed on DC, Win11A, Win11V. Not required on Certer per course curriculum.

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

### Windows Event Auditing
Configured via Group Policy for enhanced visibility across domain-joined machines.

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

---

## Pending

- [x] DC setup
- [x] Certer setup
- [x] Win11A — domain joined
- [x] Win11V — domain joined
- [x] Sysmon — DC, Win11A, Win11V
- [x] Azure account provisioned
- [x] AWS account provisioned
- [x] Windows Auditing & GPO configured
- [x] PowerShell Module Logging, Script Block Logging, Transcription enabled via GPO
- [x] Windows Defender disabled via GPO
- [x] C:\Transcripts folder created on DC
- [x] gpupdate /force run on all Windows machines
- [ ] Splunk SIEM configuration
- [ ] Domain user accounts
- [ ] PCAP lab exercises
- [ ] Cloud telemetry lab exercises
