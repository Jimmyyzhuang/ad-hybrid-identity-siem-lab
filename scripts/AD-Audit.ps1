# ===== AD-Audit.ps1 =====
# Scans Active Directory for common security risks and saves a report.
#   1. Stale accounts (enabled, but no login in X days, or never)
#   2. Passwords that never expire
#   3. Disabled accounts still in groups
#   4. Privileged accounts (including hidden nested membership)
#   5. Accounts allowed to have no password

# --- SETTINGS ---
$StaleDays        = 90
$ReportFolder     = "C:\Scripts\Reports"
$PrivilegedGroups = @("Domain Admins", "Enterprise Admins", "Schema Admins")
$BuiltInAccounts  = @("krbtgt", "Guest")     # built-in accounts Windows keeps disabled on purpose

$Today  = Get-Date -Format "yyyy-MM-dd"
$Cutoff = (Get-Date).AddDays(-$StaleDays)

# Create the report folder if it doesn't exist yet
if (-not (Test-Path $ReportFolder)) { New-Item -ItemType Directory -Path $ReportFolder | Out-Null }

$Findings = @()

# Load every user once, with all the details the checks need
$AllUsers = Get-ADUser -Filter * -Properties LastLogonDate, WhenCreated, PasswordNeverExpires, PasswordNotRequired, MemberOf
Write-Host "Auditing $($AllUsers.Count) accounts..." -ForegroundColor Cyan

# --- CHECK 1: Stale accounts ---
foreach ($U in ($AllUsers | Where-Object { $_.Enabled })) {
    if ($U.LastLogonDate) {
        if ($U.LastLogonDate -lt $Cutoff) {
            $Findings += [PSCustomObject]@{ Check="Stale account"; Risk="Medium"; Name=$U.Name; Username=$U.SamAccountName; Detail="Last login $($U.LastLogonDate.ToString('yyyy-MM-dd'))" }
        }
    }
    elseif ($U.WhenCreated -lt $Cutoff) {
        $Findings += [PSCustomObject]@{ Check="Stale account"; Risk="Medium"; Name=$U.Name; Username=$U.SamAccountName; Detail="Never logged in (created $($U.WhenCreated.ToString('yyyy-MM-dd')))" }
    }
}

# --- CHECK 2: Passwords that never expire ---
foreach ($U in ($AllUsers | Where-Object { $_.Enabled -and $_.PasswordNeverExpires })) {
    $Findings += [PSCustomObject]@{ Check="Password never expires"; Risk="Medium"; Name=$U.Name; Username=$U.SamAccountName; Detail="Password is never forced to change" }
}

# --- CHECK 3: Disabled accounts still in groups ---
foreach ($U in ($AllUsers | Where-Object { -not $_.Enabled -and $_.MemberOf.Count -gt 0 -and $_.SamAccountName -notin $BuiltInAccounts })) {
    $GroupNames = ($U.MemberOf | ForEach-Object { ($_ -split ",")[0] -replace "CN=", "" }) -join "; "
    $Findings += [PSCustomObject]@{ Check="Disabled but still in groups"; Risk="Medium"; Name=$U.Name; Username=$U.SamAccountName; Detail="Still in: $GroupNames" }
}

# --- CHECK 4: Privileged accounts ---
foreach ($G in $PrivilegedGroups) {
    $Direct = Get-ADGroupMember $G | Select-Object -ExpandProperty SamAccountName
    $Everyone = Get-ADGroupMember $G -Recursive | Where-Object { $_.objectClass -eq "user" }

    foreach ($M in $Everyone) {
        if ($M.SamAccountName -in $Direct) {
            $Detail = "Direct member of $G"
            $Risk   = "High"
        } else {
            $Detail = "HIDDEN member of $G (through a nested group)"
            $Risk   = "Critical"
        }
        $Findings += [PSCustomObject]@{ Check="Privileged account"; Risk=$Risk; Name=$M.Name; Username=$M.SamAccountName; Detail=$Detail }
    }
}

# --- CHECK 5: Accounts allowed to have no password ---
foreach ($U in ($AllUsers | Where-Object { $_.Enabled -and $_.PasswordNotRequired })) {
    $Findings += [PSCustomObject]@{ Check="Password not required"; Risk="High"; Name=$U.Name; Username=$U.SamAccountName; Detail="Account can be set with a blank password" }
}

# --- SUMMARY ON SCREEN ---
Write-Host "`nFound $($Findings.Count) issues:" -ForegroundColor Yellow
$Findings | Group-Object Check | Select-Object @{n="Check";e={$_.Name}}, Count | Format-Table -AutoSize

# --- SAVE THE REPORTS ---
$CsvPath  = "$ReportFolder\AD-Audit-$Today.csv"
$HtmlPath = "$ReportFolder\AD-Audit-$Today.html"

$Findings | Export-Csv $CsvPath -NoTypeInformation

$Style = "<style>body{font-family:Segoe UI;margin:20px} table{border-collapse:collapse} th,td{border:1px solid #ccc;padding:6px 10px} th{background:#1f4e79;color:white}</style>"
$Findings | Sort-Object Risk, Check | ConvertTo-Html -Head $Style -Title "AD Audit $Today" -PreContent "<h1>AD Security Audit - $Today</h1><p>$($Findings.Count) findings</p>" | Out-File $HtmlPath

Write-Host "Reports saved:`n  $CsvPath`n  $HtmlPath" -ForegroundColor Cyan
