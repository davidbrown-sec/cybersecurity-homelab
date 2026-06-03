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

---

## Phases 1–14

*(See previous entries — phases 1–14 cover infrastructure, AD, Certer, workstations, GPO, Splunk, Sysmon ARM64 fix, Linux forwarder, Kubernetes monitoring)*

---

## Phase 15 — AWS CloudTrail Telemetry

**Date:** 2026-06-03

### Architecture
AWS CloudTrail trail configured to log all management events across all regions, writing to S3. Splunk AWS TA (v8.1.2) polls the S3 bucket via Generic S3 input and ingests logs into the `aws` index.

### AWS Setup
- CloudTrail trail: multi-region, home region US East (Ohio)
- Logging to S3 bucket
- Status: Logging ✅

### Splunk Setup
- App: Splunk Add-on for AWS (v8.1.2)
- Input type: Generic S3
- Data type: CloudTrail
- Source type: `aws:cloudtrail`
- Index: `aws`

### Problem & fix — wrong source type
Initial input was created with `sourcetype=aws:s3:accesslogs`. The Splunk AWS TA UI does not allow editing source type after creation.  
**Fix:** Delete the input and recreate with `sourcetype=aws:cloudtrail`.

### Result
80 CloudTrail events in `index=aws` ✅  
Fields: `awsRegion`, `eventCategory: Management`, `eventName`, `eventSource`, `eventType: AwsApiCall`

---

## Telemetry Stack

| Index | Source | Status |
|-------|--------|--------|
| `winlogs` | DC, Win11A, Win11V, Certer | ✅ |
| `sysmon` | DC, Win11A, Win11V | ✅ |
| `linux` | LinuxV (Laurel/auditd) | ✅ |
| `kube` | LinuxV (Minikube audit logs) | ✅ |
| `aws` | AWS CloudTrail | ✅ |
| `azure` | Azure/Entra (pending) | 🔜 |

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
| Parallels networking | Shared network on separate subnet — use static route + manual DNS |
| VirtIO drivers | Required for disk AND network during Windows Server install |
| IPv6 DNS priority | Disable IPv6 on adapter if domain join fails |
| GPO PowerShell logging | Module Logging + Script Block + Transcription all enabled via GPO |
| Splunk TA inputs | TAs ship with inputs disabled — restart Splunk after app deployment |
| Splunk Linux install | Use `sudo bash << 'EOF'` — `sudo` on first command only leaves rest unprivileged |
| Splunk course IPs | Course scripts use placeholder IPs — replace with actual DC IP before running |
| Sysmon on ARM64 | Use `Sysmon64a.exe` on ARM64 Windows — x86 driver blocked by HVCI |
| Sysmon broken install | Use `reg delete` + reboot to clean up stuck Sysmon service |
| Laurel service | Laurel runs as auditd plugin — `systemctl status laurel` not found is normal |
| Linux forwarder scope | Only LinuxV (victim) needs the Splunk forwarder |
| Minikube audit dir | Create `~/.minikube/files/etc/ssl/certs/` before writing audit policy |
| Splunk HEC SSL | Disable SSL on HEC global settings for plain HTTP helm chart endpoint |
| Splunk AWS TA source type | Cannot edit source type after input creation — delete and recreate if wrong |

---

## Pending

- [x] DC setup
- [x] Certer setup
- [x] Win11A — domain joined
- [x] Win11V — domain joined
- [x] Sysmon — DC, Win11A, Win11V all live ✅
- [x] Azure account provisioned
- [x] AWS account provisioned
- [x] Windows Auditing & GPO configured
- [x] Splunk Enterprise deployed — all Windows hosts live ✅
- [x] LinuxV Laurel telemetry — index=linux live ✅
- [x] Kubernetes monitoring — index=kube live ✅
- [x] AWS CloudTrail — index=aws live ✅
- [ ] Cloud telemetry — Azure/Entra
- [ ] Create domain users in AD
- [ ] PCAP lab exercises
