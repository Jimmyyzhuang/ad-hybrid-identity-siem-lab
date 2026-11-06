# ===== New-Employee.ps1 (v2) =====
# Onboards one new employee, with safety checks before creating anything.

# --- CHANGE THESE FOR EACH NEW HIRE ---
$FirstName  = "Alex"
$LastName   = "Rivera"
$Department = "IT"
$Password   = "LabUser2026!"

# --- SETTINGS (rarely change) ---
$Domain           = "jzhuanglaboutlook.onmicrosoft.com"
$ValidDepartments = @("IT", "HR", "Sales", "Finance")

# --- BUILD THE DETAILS ---
$CleanLast = $LastName -replace "[^a-zA-Z]", ""      # O'Brien -> OBrien
$Username  = ($FirstName.Substring(0,1) + $CleanLast).ToLower()
$FullName  = "$FirstName $LastName"
$OUPath    = "OU=$Department,OU=Employees,OU=JimmyLab,DC=corp,DC=jimmylab,DC=local"
$Group     = "SG-$Department"

# --- CHECK 1: Is the department real? ---
if ($Department -notin $ValidDepartments) {
    Write-Host "STOPPED: '$Department' is not a valid department. Use one of: $($ValidDepartments -join ', ')" -ForegroundColor Red
    return
}

# --- CHECK 2: Is the username already taken? ---
$Existing = Get-ADUser -Filter "SamAccountName -eq '$Username'"
if ($Existing) {
    Write-Host "STOPPED: The username '$Username' is already used by $($Existing.Name)." -ForegroundColor Red
    return
}

# --- CREATE THE ACCOUNT (and catch any other problem) ---
try {
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

    New-ADUser -Name $FullName -GivenName $FirstName -Surname $LastName -SamAccountName $Username -UserPrincipalName "$Username@$Domain" -Path $OUPath -AccountPassword $SecurePassword -Enabled $true -ErrorAction Stop

    Add-ADGroupMember -Identity $Group -Members $Username -ErrorAction Stop

    Write-Host "SUCCESS: Created $FullName ($Username) in $Department and added to $Group" -ForegroundColor Green
}
catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}
