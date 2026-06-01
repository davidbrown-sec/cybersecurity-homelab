# Cybersecurity Home Lab

A hands-on home lab built to support structured offensive and defensive security training, covering Active Directory attacks, ADCS abuse, Linux exploitation, Kubernetes security, and network traffic analysis.

---

## Skills Demonstrated

| Area | Tools & Technologies |
|------|---------------------|
| Hypervisor & Infrastructure | Proxmox VE 9.1, Parallels Desktop (Apple Silicon), Proxmox clustering |
| Network Traffic Analysis | Malcolm 26.04.1, Zeek, Arkime, OpenSearch Dashboards |
| SIEM | Splunk (in progress) |
| Active Directory | Windows Server 2019, Domain Controller, ADCS (Enterprise Root CA) |
| Endpoint Telemetry | Sysmon (DC, Win11A, Win11V) |
| Linux Security | Ubuntu 22.04, privilege escalation techniques, kernel vulnerabilities |
| Cloud Security | Azure, AWS (accounts provisioned for course curriculum) |
| Containerization | Docker, Docker Compose |
| Remote Access | Tailscale mesh VPN |
| Scripting & Automation | Bash, PowerShell, netplan, git automation |

---

## Lab Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Home Lab Network                   │
│                                                     │
│  ┌──────────────┐        ┌──────────────────────┐  │
│  │  Proxmox     │        │  MacBook (Apple       │  │
│  │  Cluster     │        │  Silicon) - Parallels │  │
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

| VM | OS | Host | Role | Sysmon |
|----|----|------|------|--------|
| LinuxV | Ubuntu 22.04.5 | Proxmox node 1 | Vulnerable Linux target (intentionally unpatched) | N/A |
| LinuxA | Ubuntu 22.04.5 | Proxmox node 1 | Patched Linux analyst/attacker machine | N/A |
| Malcolm | Ubuntu 22.04.5 Server | Proxmox node 1 | PCAP & network traffic analysis | N/A |
| DC | Windows Server 2019 | Proxmox node 2 | Domain Controller + DNS | ✅ |
| Certer | Windows Server 2019 | Proxmox node 2 | Active Directory Certificate Services (ADCS) — Enterprise Root CA | — |
| Win11A | Windows 11 | MacBook (Parallels) | Patched Windows workstation — domain joined | ✅ |
| Win11V | Windows 11 | MacBook (Parallels) | Vulnerable Windows workstation — domain joined | ✅ |

> Sysmon is installed on DC, Win11A, and Win11V. Certer does not require Sysmon per course curriculum.

---

## Cloud Accounts

| Platform | Purpose |
|----------|---------|
| Microsoft Azure | Cloud security labs — telemetry, identity, and detection (course curriculum) |
| AWS | Cloud security labs — CloudTrail, IAM, and detection (course curriculum) |

---

## Course Coverage

This lab is built to support the **Just Hacking** course, covering:

- **Active Directory** — enumeration, attacks, lateral movement
- **ADCS** — certificate-based attacks (ESC1–ESC8)
- **Linux attacks** — privilege escalation, kernel exploits
- **Kubernetes** — container security and cluster attacks
- **Network traffic analysis** — PCAP analysis with Malcolm and Zeek
- **SIEM** — log ingestion and detection engineering with Splunk
- **Cloud telemetry** — Azure and AWS log analysis and detection

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
- [x] Certer — ADCS Enterprise Root CA
- [x] Win11A — patched workstation, domain joined
- [x] Win11V — vulnerable workstation, domain joined
- [x] Sysmon — installed and enabled on DC, Win11A, Win11V
- [x] Azure account provisioned
- [x] AWS account provisioned
- [ ] Splunk SIEM configuration
- [ ] Domain user accounts
- [ ] PCAP lab exercises with Malcolm/Zeek
- [ ] Cloud telemetry lab exercises
