# Cybersecurity Home Lab

A hands-on home lab built to support structured offensive and defensive security training, covering Active Directory attacks, ADCS abuse, Linux exploitation, Kubernetes security, and network traffic analysis.

---

## Skills Demonstrated

| Area | Tools & Technologies |
|------|---------------------|
| Hypervisor & Infrastructure | Proxmox VE 9.1, UTM (Apple Silicon), Proxmox clustering |
| Network Traffic Analysis | Malcolm 26.04.1, Zeek, Arkime, OpenSearch Dashboards |
| SIEM | Splunk (in progress) |
| Active Directory | Windows Server 2019, Domain Controller, ADCS (certificate authority) |
| Linux Security | Ubuntu 22.04, privilege escalation techniques, kernel vulnerabilities |
| Containerization | Docker, Docker Compose |
| Remote Access | Tailscale mesh VPN |
| Scripting & Automation | Bash, launchd, netplan, git automation |

---

## Lab Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Home Lab Network                   │
│                                                     │
│  ┌──────────────┐        ┌──────────────────────┐  │
│  │  Proxmox     │        │  MacBook (Apple       │  │
│  │  Cluster     │        │  Silicon) - UTM       │  │
│  │  (2 nodes)   │        │                      │  │
│  │              │        │  • Win11A (patched)   │  │
│  │  • LinuxV    │        │  • Win11V (vuln.)     │  │
│  │  • LinuxA    │        └──────────────────────┘  │
│  │  • Malcolm   │                                   │
│  │  • DC        │                                   │
│  │  • Certer    │                                   │
│  └──────────────┘                                   │
│                                                     │
│  ┌──────────────┐                                   │
│  │ Raspberry    │  ← Tailscale subnet router        │
│  │ Pi 5         │    (remote lab access)            │
│  └──────────────┘                                   │
└─────────────────────────────────────────────────────┘
```

---

## VM Inventory

| VM | OS | Host | Role |
|----|----|------|------|
| LinuxV | Ubuntu 22.04.5 | Proxmox | Vulnerable Linux target (intentionally unpatched) |
| LinuxA | Ubuntu 22.04.5 | Proxmox | Patched Linux analyst/attacker machine |
| Malcolm | Ubuntu 22.04.5 Server | Proxmox | PCAP & network traffic analysis |
| DC | Windows Server 2019 | Proxmox | Domain Controller + DNS |
| Certer | Windows Server | Proxmox | Active Directory Certificate Services (ADCS) |
| Win11A | Windows 11 | MacBook (UTM) | Patched Windows workstation |
| Win11V | Windows 11 | MacBook (UTM) | Vulnerable Windows workstation |

---

## Course Coverage

This lab is built to support the **Just Hacking** course, covering:

- **Active Directory** — enumeration, attacks, lateral movement
- **ADCS** — certificate-based attacks (ESC1–ESC8)
- **Linux attacks** — privilege escalation, kernel exploits
- **Kubernetes** — container security and cluster attacks
- **Network traffic analysis** — PCAP analysis with Malcolm and Zeek
- **SIEM** — log ingestion and detection engineering with Splunk

---

## Build Journal

See [`lab-journal.md`](./lab-journal.md) for a detailed log of the build process, including problems encountered and fixes applied at each phase.

---

## Status

- [x] Proxmox cluster (2 nodes)
- [x] LinuxV — vulnerable target
- [x] LinuxA — analyst machine
- [x] Malcolm — PCAP analysis (static IP, SSL cert trusted)
- [x] DC — Domain Controller (Windows Server 2019, promoted to domain controller)
- [ ] Certer — ADCS
- [ ] Win11A / Win11V — Windows workstations
- [ ] Splunk SIEM configuration
- [ ] PCAP lab exercises with Malcolm/Zeek
