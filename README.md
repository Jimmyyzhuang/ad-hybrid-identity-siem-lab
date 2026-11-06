# Hybrid Identity & SIEM Home Lab

## Overview

The project focuses on building and securing an identity environment that simulates a real-world company. The aim was to create the same setup many businesses run today: an on-premises Active Directory domain connected to Microsoft's cloud identity service, Entra ID, with automated user management and security monitoring on top. The whole lab runs on virtual machines on my laptop, with a Windows Server domain controller, a Windows 11 employee workstation, and an Ubuntu server running Splunk as the SIEM.

Throughout the project, I applied core identity and security concepts, including organizational units, Group Policy, hybrid identity sync, and least-privilege administration. I wrote PowerShell scripts to automate employee onboarding and offboarding, plus an audit script that scans the directory for risky accounts like stale users and hidden admins. To test my defenses, I simulated common identity attacks against my own lab, such as password spraying, brute force, and privilege escalation, then found the evidence in the logs and built Splunk alerts to catch each one automatically. Along the way, I troubleshot real issues with permissions, time synchronization, Group Policy precedence, and log collection.

Overall, this project demonstrates that I am capable of building, automating, securing, and monitoring an enterprise identity environment, and of thinking like both a systems administrator and a security analyst.

## Key Features

* Active Directory domain with OUs, users, security groups, and Group Policies
* Hybrid identity: on-premises AD synced to Microsoft Entra ID
* PowerShell automation for onboarding, bulk onboarding, and offboarding
* AD security audit script that flags stale accounts and hidden Domain Admins
* Splunk SIEM collecting Windows event logs from the server and workstation
* Alerts detecting password spraying, brute force, lockouts, and privilege escalation

## Tools Used

* Windows Server 2025, Windows 11, Ubuntu Server
* Active Directory, Group Policy, DNS
* Microsoft Entra ID / Entra Cloud Sync
* PowerShell
* Splunk Enterprise and Universal Forwarder
* KVM / virt-manager on Linux Mint

## Project Files

* scripts/New-Employee.ps1
* scripts/Bulk-Onboard.ps1
* scripts/Offboard-Employee.ps1
* scripts/AD-Audit.ps1
* splunk/detections.md
* splunk/inputs.conf
* docs/full-writeup.md

## Outcome

Successfully built a working hybrid identity environment with automated user lifecycle management and a SIEM that detected every simulated attack, demonstrating hands-on skills in identity administration, scripting, and security monitoring.

<!-- Add your best screenshot here (see note in chat) -->
