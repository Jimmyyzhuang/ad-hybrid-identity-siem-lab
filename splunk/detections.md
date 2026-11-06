# Splunk Detections

All alerts run on a cron schedule of `*/5 * * * *` (every 5 minutes) over the **last 15 minutes**, so consecutive runs overlap and nothing falls between them. Logs land in the `windows` index via Universal Forwarders on DC01 and CLIENT01.

> Field names (`user`, `src`, `Group_Name`, etc.) come from the Splunk Add-on for Microsoft Windows. If your add-on version labels them differently (e.g. `Account_Name`, `Source_Network_Address`), adjust accordingly.

---

## 1. Password Spray Detected — High

**Technique:** MITRE ATT&CK T1110.003 (Password Spraying)
**Logic:** One source fails to log in against many *different* accounts. Each account gets only one or two bad attempts, so lockout never triggers.

```spl
index=windows EventCode=4625
| stats dc(user) as accounts_tried, values(user) as accounts, count as attempts by src
| where accounts_tried >= 5
```

**Trigger:** results > 0, once per run.

---

## 2. Privileged Group Membership Change — Critical

**Technique:** T1098 (Account Manipulation)
**Logic:** Anyone added to a privileged group. Event IDs: 4728 (global group), 4732 (local group), 4756 (universal group).

```spl
index=windows EventCode IN (4728, 4732, 4756)
    ("Domain Admins" OR "Enterprise Admins" OR "Schema Admins" OR "Administrators")
| table _time, host, EventCode, src_user, user, Group_Name
```

**Trigger:** results > 0, **for each result** (every change is reviewed individually).

**Known gap:** nesting a user into a *non-privileged* group that is itself a member of Domain Admins (e.g. user → IT-Helpers) does not mention "Domain Admins" in the event. This is covered by the scheduled `AD-Audit.ps1` script, which resolves nested membership recursively (defense in depth).

---

## 3. Brute Force Detected — High

**Technique:** T1110.001 (Password Guessing)
**Logic:** Five or more failures against the same account from the same source inside a 5-minute bucket (matches the domain lockout threshold).

```spl
index=windows EventCode=4625
| bin _time span=5m
| stats count as failures by _time, user, src
| where failures >= 5
```

**Trigger:** results > 0, for each result.

---

## 4. Account Locked Out — Medium

**Logic:** Event 4740 on the domain controller. `Caller_Computer_Name` identifies the machine that sent the bad passwords.

```spl
index=windows EventCode=4740
| table _time, host, user, Caller_Computer_Name
```

**Trigger:** results > 0. Kept at Medium because lockouts also happen for benign reasons (forgotten or stale saved passwords). When this fires together with *Brute Force Detected* on the same account, treat it as high confidence.

---

## Useful investigation searches

```spl
# Which hosts/logs are reporting
index=windows | stats count by host, source

# All failed logons with reason
index=windows EventCode=4625 | table _time, host, user, src, Failure_Reason

# Forwarder health / errors for a host
index=_internal host=CLIENT01 log_level=ERROR

# Did a scheduled alert actually run?
index=_internal sourcetype=scheduler savedsearch_name="Brute Force Detected"
| table _time, status, result_count
```
