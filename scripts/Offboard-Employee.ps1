# ===== Offboard-Employee.ps1 =====
# Offboards one departing employee: disables the account, scrambles the password,
# removes group access, stamps the reason, moves it to Disabled Users, and logs it.
#
# Usage:  C:\Scripts\Offboard-Employee.ps1 -Username cmendez -Ticket "HR-1042"

param(
    [Parameter(Mandatory)] [string]$Username,
    [Parameter(Mandatory)] [string]$Ticket
)

# --- SETTINGS ---
$DisabledOU = "OU=Disabled Users,OU=JimmyLab,DC=corp,DC=jimmylab,DC=local"
$LogPath    = "C:\Scripts\Offboarding-Log.csv"
$Today      = Get-Date -Format "yyyy-MM-dd"

# --- CHECK 1: Does the user exist? ---
$User = Get-ADUser -Filter "SamAccountName -eq '$Username'" -Properties Enabled
if (-not $User) {
    Write-Host "STOPPED: No user named '$Username' was found." -ForegroundColor Red
    return
}

# --- CHECK 2: Is this a Domain Admin? (never auto-offboard admins) ---
$Admins = Get-ADGroupMember "Domain Admins" -Recursive | Select-Object -ExpandProperty SamAccountName
if ($Username -in $Admins) {
    Write-Host "STOPPED: '$Username' is a Domain Admin. Admin accounts must be offboarded manually." -ForegroundColor Red
    return
}

# --- CHECK 3: Already offboarded? ---
if (-not $User.Enabled -and $User.DistinguishedName -like "*$DisabledOU") {
    Write-Host "STOPPED: '$Username' is already disabled and in Disabled Users." -ForegroundColor Yellow
    return
}

# --- RECORD THEIR GROUPS BEFORE REMOVING THEM (for the log) ---
$Groups     = Get-ADPrincipalGroupMembership $User | Where-Object { $_.Name -ne "Domain Users" }
$GroupNames = $Groups.Name -join "; "

try {
    # 1. Disable the account
    Disable-ADAccount -Identity $User -ErrorAction Stop

    # 2. Scramble the password (20 random characters + "Aa1!" to guarantee it meets Windows' rules)
    $RandomPassword = (-join ((33..126) | Get-Random -Count 20 | ForEach-Object { [char]$_ })) + "Aa1!"
    Set-ADAccountPassword -Identity $User -Reset -NewPassword (ConvertTo-SecureString $RandomPassword -AsPlainText -Force) -ErrorAction Stop

    # 3. Remove from every group except Domain Users (every account must keep that one)
    if ($Groups) {
        Remove-ADPrincipalGroupMembership -Identity $User -MemberOf $Groups -Confirm:$false -ErrorAction Stop
    }

    # 4. Stamp the reason on the account
    Set-ADUser -Identity $User -Description "Offboarded $Today by $env:USERNAME - Ticket $Ticket" -ErrorAction Stop

    # 5. Move to Disabled Users
    Move-ADObject -Identity $User.DistinguishedName -TargetPath $DisabledOU -ErrorAction Stop

    $Status = "Offboarded"
    Write-Host "SUCCESS: $($User.Name) ($Username) offboarded. Removed from: $GroupNames" -ForegroundColor Green
}
catch {
    $Status = "Failed: $($_.Exception.Message)"
    Write-Host "FAILED partway through: $($_.Exception.Message)" -ForegroundColor Red
}

# --- 6. LOG IT ---
[PSCustomObject]@{
    Date          = $Today
    Name          = $User.Name
    Username      = $Username
    Ticket        = $Ticket
    RemovedGroups = $GroupNames
    PerformedBy   = $env:USERNAME
    Status        = $Status
} | Export-Csv $LogPath -NoTypeInformation -Append
