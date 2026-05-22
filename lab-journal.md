# Home Lab Build Journal
**Course:** Just Hacking  
**Domain:** `<REDACTED>.local`  
**Started:** May 2026

---

## Hardware Overview

| Device | Role | RAM |
|--------|------|-----|
| MacBook (Apple Silicon) | Primary workstation / Windows VM host | 48GB |
| Mini PC #1 | Proxmox warm spare / snapshot node | 16GB DDR4 |
| Mini PC #2 | Proxmox primary VM host | 32GB DDR4 |
| Raspberry Pi 5 | Tailscale subnet router | — |

Remote access via **Tailscale** mesh VPN with Pi 5 as subnet router.

---

## VM Inventory

| VM | OS | RAM | Disk | Role |
|----|----|-----|------|------|
| LinuxV | Ubuntu 22.04.5 Desktop | 10GB | 60GB | Vulnerable Linux target (intentionally unpatched) |
| LinuxA | Ubuntu 22.04.5 Desktop | 5GB | 50GB | Patched Linux analyst machine |
| Malcolm | Ubuntu 22.04.5 Server | 12GB | 80GB | PCAP / network traffic analysis |
| DC | Windows Server | TBD | TBD | Domain Controller + Splunk SIEM |
| Certer | Windows Server | TBD | TBD | ADCS certificate authority |
| Win11A | Windows 11 | TBD | TBD | Patched Windows workstation |
| Win11V | Windows 11 | TBD | TBD | Vulnerable Windows workstation |

All Proxmox VMs use: **q35 / OVMF (UEFI) / VirtIO** with QEMU guest agent.  
Windows VMs hosted on MacBook using **UTM** (preferred over VMware Fusion for Apple Silicon).

---

## Phase 1 — Planning & Hardware Assessment

### Key decisions
- Split VMs across physical machines based on RAM and load
- Heavy VMs (LinuxV, Malcolm) → Mini PC #2 running Proxmox
- Light VMs (DC, Certer, Win11A, Win11V) → MacBook using UTM
- Mini PC #1 → Proxmox warm spare/snapshot node (no permanent VMs)

### Lessons learned
- Verify RAM specs physically — assumptions about which machine is "stronger" can be wrong
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

## Phase 3 — VM Builds

### Ubuntu ISO note
Course specifies Ubuntu 22.04.3 LTS, which is **no longer hosted** on Ubuntu's servers.  
**Use Ubuntu 22.04.5 LTS** as a functional substitute.

### LinuxV — Vulnerable target
- Left intentionally unpatched after clean install
- Relevant vulnerability class: critical Linux kernel privilege escalation (kernels since v4.14)
- Proxmox hosts on kernel 7.0 are unaffected
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
| Proxmox password reset | `qm guest passwd <vmid> <user>` from Proxmox shell |

---

## Pending

- [ ] DC (Domain Controller) VM setup on MacBook via UTM
- [ ] Certer VM setup
- [ ] Win11A and Win11V VM setup
- [ ] Splunk SIEM configuration on DC
- [ ] PCAP work with Malcolm and Zeek
