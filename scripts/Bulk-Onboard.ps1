# ===== Bulk-Onboard.ps1 =====
# Reads new hires from a CSV file and onboards each one, with safety checks.
# Saves a report showing who was created, skipped, or failed.

# --- SETTINGS ---
$CsvPath          = "C:\Scripts\NewHires.csv"
$ReportPath       = "C:\Scripts\Onboarding-Report.csv"
$Domain           = "jzhuanglaboutlook.onmicrosoft.com"
$TempPassword     = "Welcome2026!"
$ValidDepartments = @("IT", "HR", "Sales", "Finance")

# --- LOAD THE LIST ---
$NewHires = Import-Csv $CsvPath
$Results  = @()     # empty list that will collect what happened to each person

Write-Host "Found $($NewHires.Count) new hires. Starting..." -ForegroundColor Cyan

# --- PROCESS EACH PERSON, ONE AT A TIME ---
foreach ($Hire in $NewHires) {

    # Pull this person's info from their row (Trim removes stray spaces)
    $FirstName  = $Hire.FirstName.Trim()
    $LastName   = $Hire.LastName.Trim()
    $Department = $Hire.Department.Trim()

    # Build their details, same as lesson 4
    $CleanLast = $LastName -replace "[^a-zA-Z]", ""
    $Username  = ($FirstName.Substring(0,1) + $CleanLast).ToLower()
    $FullName  = "$FirstName $LastName"
    $OUPath    = "OU=$Department,OU=Employees,OU=JimmyLab,DC=corp,DC=jimmylab,DC=local"
    $Group     = "SG-$Department"

    # Check 1: is the department real?
    if ($Department -notin $ValidDepartments) {
        $Status = "Skipped"
        $Note   = "Invalid department '$Department'"
    }
    # Check 2: is the username taken?
    elseif (Get-ADUser -Filter "SamAccountName -eq '$Username'") {
        $Status = "Skipped"
        $Note   = "Username '$Username' already exists"
    }
    # Passed both checks, so create them
    else {
        try {
            $SecurePassword = ConvertTo-SecureString $TempPassword -AsPlainText -Force

            New-ADUser -Name $FullName -GivenName $FirstName -Surname $LastName -SamAccountName $Username -UserPrincipalName "$Username@$Domain" -Path $OUPath -AccountPassword $SecurePassword -Enabled $true -ChangePasswordAtLogon $true -ErrorAction Stop

            Add-ADGroupMember -Identity $Group -Members $Username -ErrorAction Stop

            $Status = "Created"
            $Note   = "Added to $Group"
        }
        catch {
            $Status = "Failed"
            $Note   = $_.Exception.Message
        }
    }

    # Show the result on screen in a matching color
    $Color = switch ($Status) { "Created" {"Green"} "Skipped" {"Yellow"} "Failed" {"Red"} }
    Write-Host "$Status : $FullName ($Username) - $Note" -ForegroundColor $Color

    # Add a row to the report
    $Results += [PSCustomObject]@{
        Name       = $FullName
        Username   = $Username
        Department = $Department
        Status     = $Status
        Note       = $Note
    }
}

# --- SAVE THE REPORT ---
$Results | Export-Csv $ReportPath -NoTypeInformation
Write-Host "Done. Report saved to $ReportPath" -ForegroundColor Cyan
