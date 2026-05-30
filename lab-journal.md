# Home Lab Build Journal
**Course:** Just Hacking  
**Domain:** `<REDACTED>.local`  
**Started:** May 2026

---

## Hardware Overview

| Device | Role | RAM |
|--------|------|-----|
| MacBook (Apple Silicon) | Primary workstation / Windows VM host (UTM) | 48GB |
| Mini PC #1 | Proxmox primary VM host | 32GB DDR4 |
| Mini PC #2 | Proxmox secondary VM host | 16GB DDR4 |
| Raspberry Pi 5 | Tailscale subnet router | — |

Remote access via **Tailscale** mesh VPN with Pi 5 as subnet router.

---

## VM Inventory

| VM | OS | RAM | Disk | Host | Role |
|----|----|-----|------|------|------|
| LinuxV | Ubuntu 22.04.5 Desktop | 10GB | 60GB | Proxmox node 1 | Vulnerable Linux target (intentionally unpatched) |
| LinuxA | Ubuntu 22.04.5 Desktop | 5GB | 50GB | Proxmox node 1 | Patched Linux analyst machine |
| Malcolm | Ubuntu 22.04.5 Server | 12GB | 80GB | Proxmox node 1 | PCAP / network traffic analysis |
| DC | Windows Server 2019 | 6GB | 60GB | Proxmox node 2 | Domain Controller + DNS |
| Certer | Windows Server 2019 | 4GB | 60GB | Proxmox node 2 | ADCS Enterprise Root CA |
| Win11A | Windows 11 | TBD | TBD | MacBook (UTM) | Patched Windows workstation |
| Win11V | Windows 11 | TBD | TBD | MacBook (UTM) | Vulnerable Windows workstation |

All Proxmox VMs use: **q35 / OVMF (UEFI) / VirtIO** with QEMU guest agent.

---

## Phase 1 — Planning & Hardware Assessment

### Key decisions
- Split VMs across physical machines based on RAM and load
- Node 1 (32GB): LinuxV, LinuxA, Malcolm
- Node 2 (16GB): DC, Certer
- MacBook (UTM): Win11A, Win11V
- DC moved from UTM to Proxmox to enable snapshots (UTM on Apple Silicon has no snapshot support)
- Apple Silicon has no Windows Server ARM support — x86_64 Proxmox nodes required for DC

### Lessons learned
- Verify RAM specs physically — assumptions about which machine is stronger can be wrong
- DDR4 SO-DIMM prices have risen significantly; check current pricing before planning upgrades

---

## Phase 2 — Proxmox Installation & Configuration

**Proxmox version:** 9.1 (Debian **trixie** base)

### Proxmox 9.1 — key differences from older versions

| Topic | Detail |
|-------|--------|
| Debian base | **trixie** (not bookworm) |
| Repo file format | `.sources` (not `.list`) |
| Disabling enterprise repo | Set `Enabled: no` — commenting out the `deb` line does NOT work in `.sources` format |
| DNS permanence | Must add `dns-nameservers` to `/etc/network/interfaces` — web UI setting does not persist |

### No-subscription repo config (`.sources` format)
```
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Enabled: yes
```

### Problems & fixes

**DNS typo caused apt failures**  
Mistyped the DNS IP during install, which caused all `apt` commands to fail silently.  
Fix: Corrected in `/etc/network/interfaces` and added `dns-nameservers` directive to make it permanent.

**Enterprise repo subscription errors**  
Default Proxmox install enables the enterprise repo, which requires a paid subscription.  
Fix: Disable enterprise repo using `Enabled: no` in the `.sources` file, then add no-subscription repo.

---

## Phase 3 — VM Builds (Linux)

### Ubuntu ISO note
Course specifies Ubuntu 22.04.3 LTS, which is **no longer hosted** on Ubuntu's servers.  
**Use Ubuntu 22.04.5 LTS** as a functional substitute.

### LinuxV — Vulnerable target
- Left intentionally unpatched after clean install
- Relevant vulnerability class: critical Linux kernel privilege escalation (kernels since v4.14)
- Proxmox hosts are unaffected
- Snapshot taken immediately after clean install, before any updates

### Malcolm — PCAP analysis
Running **Malcolm 26.04.1** via Docker (`ghcr.io/idaholab/malcolm`).

**Problem: Docker Compose version too old**  
The `apt` package for docker-compose is incompatible with Malcolm.  
Fix: Install Docker Compose v5.1.3 manually and symlink it:
```bash
sudo curl -L "https://github.com/docker/compose/releases/download/v5.1.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
```

**Problem: LVM not using full allocated disk**  
After install, LVM only used a portion of the disk.  
Fix: Expand LVM after Malcolm install to use full disk.

**Malcolm does not run as root**  
Running `sudo ./scripts/start` fails.  
Fix: Run as the regular user: `./scripts/start`

---

## Phase 4 — Malcolm Static IP

Malcolm was initially assigned a DHCP address. Set to static using Netplan.

**Netplan file location:** `/etc/netplan/50-cloud-init.yaml` (not `00-installer-config.yaml`)

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
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

Apply with:
```bash
sudo netplan apply
```

### Proxmox VM password reset (without knowing old password)
If you forget the VM user password, reset it from the **Proxmox node shell** (VM must be running):
```bash
qm guest passwd <vmid> <username>
```

---

## Phase 5 — Malcolm SSL Certificate Trust (macOS)

Malcolm uses a self-signed TLS certificate. To eliminate the browser warning on macOS:

**Step 1 — Extract cert from the nginx Docker container (on Malcolm VM):**
```bash
docker cp malcolm-nginx-proxy-1:/etc/nginx/certs/cert.pem /home/<user>/malcolm.crt
```

**Step 2 — Copy cert to your Mac:**
```bash
scp <user>@<malcolm-ip>:/home/<user>/malcolm.crt ~/Desktop/malcolm.crt
```

**Step 3 — Import and trust via Terminal (GUI import will fail with error -25294):**
```bash
sudo security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain ~/Desktop/malcolm.crt
```

### Notes
- The cert lives **inside** the Docker container, not on the host filesystem — Malcolm must be running
- Mac's LibreSSL (`openssl` CLI) cannot extract the cert directly from the live HTTPS connection — use `docker cp` instead
- Keychain GUI import fails for self-signed server certs; the `security` CLI command is the reliable method

---

## Phase 6 — Domain Controller (DC) Build

**Date:** 2026-05-29  
**OS:** Windows Server 2019 Standard Evaluation  

### Why DC moved from UTM to Proxmox
Original plan had DC on MacBook via UTM. UTM on Apple Silicon has no snapshot support, which is critical for AD lab work (need to restore after attacks/misconfigurations). Moved to a Proxmox node which has full snapshot support. Additionally, Windows Server has no ARM support, making x86_64 Proxmox nodes the correct host.

### VM specs
- Machine: q35 / OVMF (UEFI)
- CPU: host, 2 cores
- RAM: 6GB
- Disk: 60GB (local-lvm, SCSI, writeback, discard)
- Network: VirtIO
- QEMU guest agent: enabled

### VirtIO drivers
Windows Server 2019 requires VirtIO drivers for disk and network during installation. Attached `virtio-win.iso` as a second CD drive. After OS install, installed network driver from `NetKVM\2k19\amd64\netkvm.inf`.

### Configuration
- Hostname: `dc`
- Static IP: assigned (not published)
- Preferred DNS: self (post-promotion)
- Alternate DNS: local gateway

### AD DS installation & promotion
- Role: Active Directory Domain Services
- Operation: Add a new forest
- Root domain: `<REDACTED>.local`
- Forest functional level: Windows Server 2016
- Domain functional level: Windows Server 2016
- DNS Server: Yes
- Global Catalog: Yes
- DSRM password: configured
- DNS delegation: No (expected warning for new internal domain)

### Post-promotion
- Server rebooted and rejoined as domain Administrator
- Host firewall disabled via PowerShell: `Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False`
- Clean snapshot taken in Proxmox

### Problems & fixes

**Boot device selection at first boot**  
UEFI boot menu appeared instead of booting directly from ISO.  
Fix: Selected correct DVD-ROM from boot device menu.

**"We couldn't find any drives" during Windows Setup**  
Windows installer couldn't see the VirtIO SCSI disk.  
Fix: Clicked "Load driver" and browsed to `vioscsi\2k19\amd64` on the VirtIO ISO.

**No network after OS install**  
Windows Server doesn't include VirtIO network drivers.  
Fix: Installed from `NetKVM\2k19\amd64\netkvm.inf` on the VirtIO ISO.

**Ctrl+Alt+Delete from Mac**  
Cannot send Ctrl+Alt+Delete directly from Mac keyboard in Proxmox console.  
Fix: Use "Send Key" menu in the Proxmox noVNC console toolbar.

---

## Phase 7 — Certer (ADCS) Build

**Date:** 2026-05-29  
**OS:** Windows Server 2019 Standard Evaluation  

### VM specs
- Machine: q35 / OVMF (UEFI)
- CPU: host, 2 cores
- RAM: 4GB
- Disk: 60GB (local-lvm, SCSI, writeback, discard)
- Network: VirtIO
- QEMU guest agent: enabled

### Configuration
- Hostname: `certer`
- Static IP: assigned (not published)
- Preferred DNS: DC IP
- Alternate DNS: local gateway
- IPv6 disabled on adapter (was taking DNS priority over IPv4)

### Domain join
- Joined to `<REDACTED>.local` via PowerShell: `Add-Computer -DomainName "<REDACTED>.local" -Credential <DOMAIN>\Administrator -Restart`
- Verified with: `systeminfo | findstr /i "domain"`

### ADCS installation & configuration
- Role: Active Directory Certificate Services
- Role service: Certification Authority only
- Setup type: Enterprise CA (domain member)
- CA type: Root CA
- Private key: New
- Cryptography: RSA, 2048-bit, SHA256
- CA name: `<REDACTED>-CERTER-CA`
- Validity period: 5 years
- Database: default paths
- Configuration result: ✅ succeeded

### Post-configuration
- Clean snapshot taken in Proxmox

### Problems & fixes

**Domain join failed — "domain does not exist or could not be contacted"**  
Certer was resolving DNS via IPv6 router address instead of the DC.  
Fix: Disabled IPv6 on the Ethernet adapter so IPv4 DNS (pointing to DC) was used exclusively.

---

## Key Lessons Summary

| Topic | Lesson |
|-------|--------|
| Proxmox 9.1 repos | `.sources` format; use `Enabled: no` not comment-out |
| Proxmox 9.1 Debian base | Trixie, not bookworm |
| DNS permanence | Set `dns-nameservers` in `/etc/network/interfaces` |
| Ubuntu ISO | 22.04.3 no longer hosted; use 22.04.5 |
| Docker Compose | Install v5.1.3 manually; apt version too old for Malcolm |
| Malcolm startup | Never run as root; use `./scripts/start` |
| Malcolm certs | Cert is inside Docker container, use `docker cp` |
| Malcolm user | Default user is `user`, not `admin` |
| Apple Silicon | UTM handles x86_64 emulation better than VMware Fusion |
| Apple Silicon | No Windows Server ARM support — use x86_64 Proxmox for DC |
| UTM snapshots | UTM on Apple Silicon has no snapshot support — use Proxmox for VMs needing snapshots |
| Proxmox password reset | `qm guest passwd <vmid> <user>` from Proxmox shell |
| VirtIO drivers | Required for disk AND network during Windows Server install on Proxmox |
| Windows boot | UEFI boot menu may appear — select correct DVD-ROM manually |
| IPv6 DNS priority | IPv6 DNS can take priority over IPv4 — disable IPv6 on adapter if domain join fails |
| ADCS Enterprise CA | Requires Enterprise Admin credentials (domain admin), not local admin |

---

## Pending

- [x] DC (Domain Controller) VM setup on Proxmox
- [x] Certer VM setup on Proxmox
- [ ] Disable firewall on Certer
- [ ] Win11A and Win11V VM setup on MacBook (UTM)
- [ ] Splunk SIEM configuration on DC
- [ ] PCAP work with Malcolm and Zeek
- [ ] Join Win11A and Win11V to domain
