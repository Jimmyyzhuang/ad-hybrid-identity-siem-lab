# Hybrid Identity & SIEM Home Lab

A self-built enterprise identity environment: on-prem **Active Directory** synced to **Microsoft Entra ID**, **PowerShell** automation for the user lifecycle, an **AD security audit** script, and a **Splunk** SIEM with detections for common identity attacks — all running on KVM virtual machines on a Linux Mint host.

**Author:** Jimmy Zhuang · MIS, San José State University (Dec 2026)

---

## Architecture

```
                         ┌──────────────────────────────┐
                         │   Microsoft Entra ID (cloud) │
                         │   tenant: jzhuanglaboutlook  │
                         └──────────────▲───────────────┘
                                        │ Entra Cloud Sync
                                        │ (password hash sync, OU-scoped)
 Linux Mint host (KVM / libvirt) ───────┼───────────────────────────────────
 NAT network 192.168.122.0/24           │
                                        │
   ┌────────────────────────┐   ┌───────┴────────────────┐   ┌─────────────────────────┐
   │ CLIENT01               │   │ DC01                   │   │ SPLUNK01                │
   │ Windows 11 Enterprise  │──▶│ Windows Server 2025    │   │ Ubuntu Server           │
   │ Domain-joined endpoint │   │ AD DS · DNS · GPO      │   │ Splunk Enterprise       │
   │ DHCP (.100+)           │   │ Authoritative NTP      │   │ 192.168.122.20          │
   │ Universal Forwarder ───┼─┐ │ 192.168.122.10         │   │ receiving on :9997      │
   └────────────────────────┘ │ │ Universal Forwarder ───┼─┐ │ Web UI on :8000         │
                              │ └────────────────────────┘ │ └────────────▲────────────┘
                              └────────────────────────────┴──────────────┘
                                       Windows event logs → index=windows
```

| Host | OS | Role |
|---|---|---|
| DC01 | Windows Server 2025 | Domain controller (`corp.jimmylab.local`), DNS, Group Policy, Cloud Sync agent, NTP source |
| CLIENT01 | Windows 11 Enterprise | Domain-joined workstation; attack source for simulations |
| SPLUNK01 | Ubuntu Server | Splunk Enterprise SIEM, managed over SSH |

---

## Phase 1 — Active Directory Foundation

- Built DC01, assigned a static IP, promoted it to a new forest `corp.jimmylab.local`.
- Designed an OU structure separating people, groups, workstations, admin accounts and disabled users:

```
JimmyLab
├── Admin Accounts      (privileged accounts, NOT synced to cloud)
├── Employees
│   ├── IT · HR · Sales · Finance
├── Groups              (SG-IT, SG-HR, SG-Sales, SG-Finance)
├── Workstations        (CLIENT01)
└── Disabled Users      (offboarding destination)
```

- Followed **tiered admin practice**: separate `adm-` account for privileged work instead of daily use of the built-in Administrator.
- Joined CLIENT01 to the domain and moved it into the Workstations OU so GPOs apply.
- Group Policies:
  - **Account Lockout** — 5 failed attempts (linked at domain level; fixed link-order precedence over the Default Domain Policy).
  - **Workstation Screen Lock** — 10-minute inactivity limit.
  - **Security Audit Policy** — advanced auditing for credential validation, Kerberos, logon, account/group management, lockouts, and process creation with command line.

## Phase 2 — Hybrid Identity with Entra ID

- Created an Entra ID tenant and a least-privilege **Hybrid Identity Administrator** account for sync setup (not Global Admin).
- **UPN remediation:** added the routable tenant suffix to AD and switched users off the non-routable `.local` suffix before syncing, so on-prem and cloud sign-in names match.
- Deployed **Microsoft Entra Cloud Sync** (provisioning agent on DC01, gMSA service account) with **password hash sync**.
- **Scoped sync to the Employees and Groups OUs only**, keeping admin accounts on-prem.
- Verified source-of-authority behavior: AD changes (e.g. job title) flow to the cloud; cloud-side edits of synced users are blocked.

## Phase 3 — PowerShell Lifecycle Automation (`/scripts`)

| Script | Purpose |
|---|---|
| `New-Employee.ps1` | Onboard one user: naming convention, department OU, group membership, department and duplicate checks |
| `Bulk-Onboard.ps1` | Onboard from CSV with a temporary password and must-change-at-first-logon; per-row validation, skips bad rows without stopping, writes a Created/Skipped/Failed report |
| `Offboard-Employee.ps1` | Disable, scramble password, strip groups (recorded first for restore), stamp ticket #, move to Disabled Users, append audit log |

Safety features: department validation, duplicate-username checks, name sanitization (`O'Connor` → `loconnor`), `try/catch` with `-ErrorAction Stop`, and a guard that refuses to auto-offboard Domain Admins (checked recursively).

## Phase 4 — AD Security Audit (`AD-Audit.ps1`)

Scans the directory and produces CSV + HTML reports for:

1. Stale accounts (no logon in 90+ days or never)
2. Passwords set to never expire
3. Disabled accounts still holding group memberships
4. Privileged accounts — flags **hidden Domain Admins** granted through nested groups as Critical
5. Accounts flagged password-not-required

**Exercise:** planted three misconfigurations (never-expiring password, sloppy manual disable, nested admin via an `IT-Helpers` group), detected them, remediated, and re-ran the audit to verify a clean result.

## Phase 5 — Splunk SIEM & Detection Engineering (`/splunk`)

- Installed Splunk Enterprise on Ubuntu Server; opened receiving port 9997, created a dedicated `windows` index, installed the Splunk Add-on for Microsoft Windows.
- Deployed Universal Forwarders to DC01 and CLIENT01 collecting Security, System and Application logs.
- Simulated attacks (assumed-breach scenario) and built scheduled alerts:

| Alert | Detects | Key Event IDs | Severity |
|---|---|---|---|
| Password Spray Detected | One source, ≥5 distinct accounts failing | 4625 | High |
| Privileged Group Membership Change | Additions to admin groups | 4728, 4732, 4756 | Critical |
| Brute Force Detected | ≥5 failures on one account in 5 min | 4625 | High |
| Account Locked Out | Lockouts, with source machine | 4740 | Medium |

Full SPL and reasoning: [`splunk/detections.md`](../splunk/detections.md).

**Defense in depth:** the group-change alert cannot see nested escalation (user added to a group that is itself in Domain Admins). The scheduled audit script closes that gap by resolving membership recursively.

---

## Troubleshooting Log (real issues solved)

| Problem | Root cause | Fix |
|---|---|---|
| Lockout policy not enforcing | Default Domain Policy outranked new GPO | Moved GPO to link order 1, `gpupdate /force` on DC |
| Cloud Sync sign-in blocked | IE Enhanced Security Configuration | Disabled temporarily for setup, re-enabled after |
| Splunk service crash-looping | First start run as root; service runs as `splunk` user | `chown -R splunk:splunk /opt/splunk`, reset failed state |
| Forwarder config "Access denied" | Hardened forwarder folder ACLs | `takeown` / `icacls` on the `local` config folder |
| No Security log from CLIENT01 | Forwarder's virtual service account couldn't read Security log | Ran service as LocalSystem (least-privilege alt: Event Log Readers) |
| Client clock off by 1 hr (DST), TLS sign-in failing | Domain time hierarchy had no authoritative source | Configured DC01 as reliable NTP source (`w32tm`); clients sync from DC |
| VM won't start after moving ISOs | Stale CD-ROM source path | Ejected install media from VM hardware config |

---

## Skills Demonstrated

Active Directory · Group Policy · DNS · Microsoft Entra ID · Entra Cloud Sync · Hybrid identity · PowerShell · Splunk (SPL, alerting, forwarders) · Windows event log analysis · Linux server administration (SSH, systemd, permissions) · KVM/libvirt virtualization · Detection engineering · Least privilege & tiered administration

## Future Improvements

- Bulk offboarding from CSV and automatic rollback on partial failure
- Run the forwarder under a least-privilege service account
- Enable HTTPS on Splunk Web
- Kerberoasting simulation and detection (Event 4769)
- Detect password spraying against the Entra ID sign-in page via Entra sign-in logs
- Deploy LAPS for local admin password management

---

*Lab environment only. All attack simulations were run against systems I own. Usernames are fictional, and the passwords in the scripts are lab-only test values.*
