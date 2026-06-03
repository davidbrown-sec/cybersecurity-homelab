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

| Topic | Detail |
|-------|--------|
| Debian base | **trixie** (not bookworm) |
| Repo file format | `.sources` (not `.list`) |
| Disabling enterprise repo | Set `Enabled: no` — commenting out does NOT work |
| DNS permanence | Must add `dns-nameservers` to `/etc/network/interfaces` |

---

## Phase 3 — VM Builds (Linux)

Ubuntu 22.04.3 LTS no longer hosted — use **22.04.5 LTS**.

Malcolm 26.04.1 via Docker. Docker Compose v5.1.3 required (install manually; apt version too old).

---

## Phase 4 — Malcolm Static IP

Netplan file: `/etc/netplan/50-cloud-init.yaml`. Apply with `sudo netplan apply`.

---

## Phase 5 — Malcolm SSL Certificate Trust (macOS)

```bash
docker cp malcolm-nginx-proxy-1:/etc/nginx/certs/cert.pem /home/<user>/malcolm.crt
scp <user>@<malcolm-ip>:/home/<user>/malcolm.crt ~/Desktop/malcolm.crt
sudo security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain ~/Desktop/malcolm.crt
```

---

## Phase 6 — Domain Controller (DC) Build

- Windows Server 2019, q35/OVMF/VirtIO, 2 cores, 6GB RAM, 60GB disk
- VirtIO drivers required for disk and network
- AD DS promoted, Windows Server 2016 FL, Sysmon ✅, snapshot taken

---

## Phase 7 — Certer (ADCS) Build

- Windows Server 2019, Enterprise Root CA, RSA 2048-bit, SHA256, 5 year validity
- IPv6 disabled (was overriding IPv4 DNS — caused domain join failure)
- Sysmon: not required per course curriculum, snapshot taken

---

## Phase 8 — Windows 11 Workstations

Parallels shared network (separate subnet). Static IPs, DNS → DC, IPv6 disabled, static route on Mac.

- Win11A: Administrator, Sysmon ✅, domain joined ✅
- Win11V: Standard User, Sysmon ✅, domain joined ✅

---

## Phase 9 — Cloud Accounts

Azure and AWS accounts provisioned for course curriculum.

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

**Date:** 2026-06-03 | Splunk Enterprise 9.3.2

Indexes: `winlogs`, `sysmon`, `linux`, `azure`, `aws`, `kube`, `etw`. Receiving on port 9997.

**Problem:** Splunk TAs ship with inputs disabled — restart required after app extraction.  
**Fix:** Restart Splunk → 51,055 events in `winlogs` ✅

---

## Phase 12 — Sysmon on Win11A & Win11V (ARM64 Fix)

**Date:** 2026-06-03

Course `Sysmon.exe` (x86) blocked by HVCI on ARM64 Windows. Solution: `Sysmon64a.exe` from full Sysmon zip.

```powershell
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Sysmon" /f
Restart-Computer -Force
# After reboot:
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile "C:\SysmonFiles\Sysmon_new.zip"
Expand-Archive -Path "C:\SysmonFiles\Sysmon_new.zip" -DestinationPath "C:\SysmonFiles\" -Force
C:\SysmonFiles\Sysmon64a.exe -accepteula -i
Restart-Service SplunkForwarder
```

| Binary | Architecture | ARM64 Windows |
|--------|-------------|---------------|
| `Sysmon.exe` | x86 | ❌ Blocked |
| `Sysmon64.exe` | x86-64 | ❌ Blocked |
| `Sysmon64a.exe` | ARM64 native | ✅ |

**Result:** DC, WIN11A, WIN11V all live in `index=sysmon` ✅

---

## Phase 13 — Splunk Forwarder on LinuxV (Laurel Telemetry)

**Date:** 2026-06-03 | LinuxV only (LinuxA is the attacker machine)

Laurel runs as auditd plugin — `systemctl status laurel` returning "Unit not found" is normal.

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

**Result:** 668 events in `index=linux` ✅

---

## Phase 14 — Kubernetes Monitoring (Minikube + Splunk HEC)

**Date:** 2026-06-03  
**Host:** LinuxV  
**Stack:** Minikube v1.38.1, Kubernetes v1.35.1, Helm, Splunk OpenTelemetry Collector

### Steps

```bash
# 1. Create audit policy directory (required before writing the file)
mkdir -p ~/.minikube/files/etc/ssl/certs/

# 2. Stop Minikube
minikube stop

# 3. Write audit policy (no environment-specific values — use as-is)
cat <<EOF > ~/.minikube/files/etc/ssl/certs/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - "RequestReceived"
rules:
  - level: RequestResponse
    resources:
    - group: ""
      resources: ["pods"]
  - level: Metadata
    resources:
    - group: ""
      resources: ["pods/log", "pods/status"]
  - level: None
    resources:
    - group: ""
      resources: ["configmaps"]
      resourceNames: ["controller-leader"]
  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
    - group: ""
      resources: ["endpoints", "services"]
  - level: None
    userGroups: ["system:authenticated"]
    nonResourceURLs: ["/api*", "/version"]
  - level: Request
    resources:
    - group: ""
      resources: ["configmaps"]
    namespaces: ["kube-system"]
  - level: Metadata
    resources:
    - group: ""
      resources: ["secrets", "configmaps"]
  - level: Request
    resources:
    - group: ""
    - group: "extensions"
  - level: Metadata
    omitStages:
      - "RequestReceived"
EOF

# 4. Start Minikube with audit logging
minikube start \
  --extra-config=apiserver.audit-policy-file=/etc/ssl/certs/audit-policy.yaml \
  --extra-config=apiserver.audit-log-path=-
```

**5. Create Splunk HEC token:**
- Settings → Add Data → Monitor → HTTP Event Collector
- Name: `K8s`, Index: `kube`
- Settings → Data Inputs → HTTP Event Collector → Global Settings → Enable, uncheck SSL → Save
- Copy the token value

**6. Deploy Splunk collector via Helm:**
```bash
helm repo add splunk-otel-collector-chart https://signalfx.github.io/splunk-otel-collector-chart

helm install my-splunk-otel-collector \
  --set="splunkPlatform.endpoint=http://<DC_IP>:8088/services/collector,\
splunkPlatform.token=<HEC_TOKEN>,\
splunkPlatform.index=kube,\
clusterName=<REDACTED>,\
logsEngine=otel,\
splunkPlatform.logsEnabled=true" \
  splunk-otel-collector-chart/splunk-otel-collector
```

> Replace `<DC_IP>` with DC IP and `<HEC_TOKEN>` with token from Splunk. Course uses placeholder IP — substitute before running.

### Problem & fix
First attempt failed: audit policy heredoc wrote to a non-existent path.  
**Fix:** `mkdir -p ~/.minikube/files/etc/ssl/certs/` before running the heredoc.

### Result
2,493 Kubernetes audit events in `index=kube` ✅  
Fields: `apiVersion: audit.k8s.io/v1`, `kind: Event`, `auditID`, `requestURI`, `stage: ResponseComplete`

---

## Telemetry Stack — Complete

| Index | Source | Status |
|-------|--------|--------|
| `winlogs` | DC, Win11A, Win11V, Certer | ✅ |
| `sysmon` | DC, Win11A, Win11V | ✅ |
| `linux` | LinuxV (Laurel/auditd) | ✅ |
| `kube` | LinuxV (Minikube audit logs) | ✅ |
| `azure` | Azure (pending) | 🔜 |
| `aws` | AWS (pending) | 🔜 |

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
- [ ] Cloud telemetry — AWS
- [ ] Cloud telemetry — Azure/Entra
- [ ] Create domain users in AD
- [ ] PCAP lab exercises
