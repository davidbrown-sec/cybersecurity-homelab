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
- Domain joined ✅, Administrator account, Sysmon ✅, Snapshot: `clean-domain-joined`

### Win11V — Vulnerable workstation
- Domain joined ✅, Standard User account, Sysmon ✅, Snapshot: `clean-domain-joined`

---

## Phase 9 — Cloud Accounts

- Azure: provisioned for course curriculum (telemetry, identity, detection labs)
- AWS: provisioned for course curriculum (CloudTrail, IAM, detection labs)

---

## Phase 10 — Windows Auditing & GPO Configuration

**Date:** 2026-06-01  

| Setting | Value |
|---------|-------|
| PowerShell Module Logging | Enabled |
| PowerShell Script Block Logging | Enabled |
| PowerShell Transcription | Enabled (`C:\Transcripts`) |
| Windows Defender Antivirus | Disabled |
| Real-Time Protection | Disabled |

---

## Phase 11 — Splunk SIEM Deployment

**Date:** 2026-06-03 | Splunk Enterprise 9.3.2 on DC

**Problem:** No telemetry after install — Splunk TAs ship with inputs disabled; restart required after app extraction.  
**Fix:** `Restart-Service Splunkd` → 51,055 events in `winlogs` ✅

---

## Phase 12 — Sysmon on Win11A & Win11V (ARM64 Fix)

**Date:** 2026-06-03

**Root cause:** Course `Sysmon.exe` is x86 — blocked by HVCI on ARM64 Windows (Parallels/Apple Silicon). Needed `Sysmon64a.exe` from the full Sysmon zip.

```powershell
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Sysmon" /f
Restart-Computer -Force
# After reboot:
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile "C:\SysmonFiles\Sysmon_new.zip"
Expand-Archive -Path "C:\SysmonFiles\Sysmon_new.zip" -DestinationPath "C:\SysmonFiles\" -Force
C:\SysmonFiles\Sysmon64a.exe -accepteula -i
Restart-Service SplunkForwarder
```

| Binary | Architecture | Works on ARM64 Windows |
|--------|-------------|----------------------|
| `Sysmon.exe` | x86 | ❌ Blocked by HVCI |
| `Sysmon64.exe` | x86-64 | ❌ Blocked by HVCI |
| `Sysmon64a.exe` | ARM64 native | ✅ |

**Result:** DC, WIN11A, WIN11V all live in `index=sysmon` ✅

---

## Phase 13 — Splunk Forwarder on LinuxV (Laurel Telemetry)

**Date:** 2026-06-03

Only LinuxV (victim) requires the Splunk forwarder — LinuxA is the attacker machine.

**Pre-checks:** auditd running ✅, Laurel running as auditd plugin ✅, `/var/log/laurel/audit.log` present ✅

```bash
sudo bash << 'EOF'
apt-get install -y curl
mkdir /opt/splunkforwarder
wget -O /opt/splunkforwarder/splunk.deb "https://download.splunk.com/products/universalforwarder/releases/9.3.2/linux/splunkforwarder-9.3.2-d8bb32809498-linux-2.6-amd64.deb"
useradd -m splunkfwd
groupadd splunkfwd
dpkg -i /opt/splunkforwarder/splunk.deb
chown -R splunkfwd:splunkfwd /opt/splunkforwarder
/opt/splunkforwarder/bin/splunk add forward-server <DC_IP>:9997 --accept-license --answer-yes --no-prompt
/opt/splunkforwarder/bin/splunk add monitor /var/log/laurel/audit.log -index linux
/opt/splunkforwarder/bin/splunk start
EOF
```

> Replace `<DC_IP>` with your DC's IP. Course script uses a placeholder — always substitute before running.

**Result:** 668 events in `index=linux` — structured JSON Laurel events ✅

---

## Key Lessons Summary

| Topic | Lesson |
|-------|--------|
| Proxmox 9.1 repos | `.sources` format; `Enabled: no` not comment-out |
| Ubuntu ISO | 22.04.3 no longer hosted; use 22.04.5 |
| Docker Compose | Install v5.1.3 manually; apt version too old for Malcolm |
| Malcolm startup | Never run as root |
| VirtIO on Linux | VirtIO drivers built into Linux kernel — no extra ISO needed |
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
| Splunk TA inputs | TAs ship with inputs disabled — restart Splunk after app deployment |
| Splunk Linux install | Use `sudo bash << 'EOF'` — `sudo` on first command only leaves rest unprivileged |
| Splunk course IPs | Course scripts use placeholder IPs — replace with actual DC IP before running |
| Sysmon on ARM64 | Use `Sysmon64a.exe` on ARM64 Windows (Parallels/Apple Silicon) — x86 driver blocked by HVCI |
| Sysmon config XML | Course sysmonconfig.xml may have malformed XML comments — install without config if needed |
| Sysmon broken install | Use `reg delete` + reboot to clean up a stuck Sysmon service before reinstalling |
| Laurel service | Laurel runs as auditd plugin — `systemctl status laurel` not found is normal |
| Linux forwarder scope | Only LinuxV (victim) needs the Splunk forwarder — LinuxA is the attacker machine |

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
- [x] LinuxV Laurel telemetry flowing — index=linux live ✅
- [ ] Domain user accounts
- [ ] PCAP lab exercises
- [ ] Cloud telemetry lab exercises
