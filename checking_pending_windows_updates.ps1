param (
    [string[]]$ComputerNames = @($env:COMPUTERNAME),
    [string]$OutputFile = "PendingUpdates_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    [switch]$TestWinRMOnly,
    [switch]$UseLocalWUAPI
)

# Initialize results array
$Results = @()

Write-Host "Windows Update Check - Minimal Version" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Target computer(s): $($ComputerNames -join ', ')"
Write-Host "Mode: $(if($TestWinRMOnly){"WinRM Test Only"}elseif($UseLocalWUAPI){"Local WU API"}else{"Default"})"
Write-Host "Output file: $OutputFile"
Write-Host "==================================" -ForegroundColor Cyan

foreach ($Computer in $ComputerNames) {
    Write-Host "Processing $Computer..." -ForegroundColor Cyan
    
    # Check if computer is online
    if (-not (Test-Connection -ComputerName $Computer -Count 1 -Quiet)) {
        Write-Warning "$Computer is not reachable."
        $Results += [PSCustomObject]@{
            ComputerName = $Computer
            Status = "Offline"
            Error = "Cannot connect to computer"
            PendingUpdates = "Unknown"
        }
        continue
    }
    
    # If only testing WinRM connectivity
    if ($TestWinRMOnly) {
        try {
            $WinRMTest = Invoke-Command -ComputerName $Computer -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
            Write-Host "  WinRM connectivity to $Computer successful. Remote name: $WinRMTest" -ForegroundColor Green
            $Results += [PSCustomObject]@{
                ComputerName = $Computer
                Status = "Online"
                Error = $null
                PendingUpdates = "WinRM Test Only"
            }
        }
        catch {
            Write-Warning "  WinRM connection to $Computer failed - $($_.Exception.Message)"
            $Results += [PSCustomObject]@{
                ComputerName = $Computer
                Status = "Error"
                Error = "WinRM connection failed - $($_.Exception.Message)"
                PendingUpdates = "Unknown"
            }
        }
        continue
    }
    
    # If using direct COM method
    if ($UseLocalWUAPI) {
        try {
            # Create COM object for Windows Update
            $UpdateSession = [activator]::CreateInstance([type]::GetTypeFromProgID("Microsoft.Update.Session", $Computer))
            
            if ($null -eq $UpdateSession) {
                throw "Failed to create Microsoft.Update.Session COM object"
            }
            
            $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
            $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and IsHidden=0")
            $PendingCount = $SearchResult.Updates.Count
            
            $Results += [PSCustomObject]@{
                ComputerName = $Computer
                Status = "Online"
                Error = $null
                PendingUpdates = $PendingCount
            }
            
            if ($PendingCount -gt 0) {
                Write-Host "  $Computer has $PendingCount pending updates" -ForegroundColor Yellow
            } else {
                Write-Host "  $Computer has no pending updates" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "  Error checking updates using DCOM on $Computer - $($_.Exception.Message)"
            $Results += [PSCustomObject]@{
                ComputerName = $Computer
                Status = "Error"
                Error = "DCOM Error - $($_.Exception.Message)"
                PendingUpdates = "Unknown"
            }
        }
        continue
    }
    
    # Standard method using WinRM
    try {
        Write-Host "  Attempting to connect to $Computer via WinRM..." -ForegroundColor Cyan
        $UpdateInfo = Invoke-Command -ComputerName $Computer -ScriptBlock {
            try {
                Write-Output "Starting Windows Update check on local machine..."
                
                # Create COM object for Windows Update
                $UpdateSession = New-Object -ComObject Microsoft.Update.Session
                
                if ($null -eq $UpdateSession) {
                    throw "Failed to create Windows Update Session"
                }
                
                $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
                
                # Search for pending updates
                $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and IsHidden=0")
                $UpdateCount = $SearchResult.Updates.Count
                
                return @{
                    Status = "Success"
                    Count = $UpdateCount
                    Error = $null
                }
            }
            catch {
                return @{
                    Status = "Error"
                    Count = "Unknown"
                    Error = $_.Exception.Message
                }
            }
        } -ErrorAction SilentlyContinue -ErrorVariable RemoteError
        
        if ($RemoteError) {
            Write-Warning "  Remote error on $Computer - $($RemoteError.Message)"
            $Results += [PSCustomObject]@{
                ComputerName = $Computer
                Status = "Error"
                Error = "Remote error - $($RemoteError.Message)"
                PendingUpdates = "Unknown"
            }
        }
        elseif ($null -eq $UpdateInfo) {
            Write-Warning "  No response from $Computer"
            $Results += [PSCustomObject]@{
                ComputerName = $Computer
                Status = "Error"
                Error = "No response received"
                PendingUpdates = "Unknown"
            }
        }
        elseif ($UpdateInfo.Status -eq "Success") {
            $Results += [PSCustomObject]@{
                ComputerName = $Computer
                Status = "Online"
                Error = $null
                PendingUpdates = $UpdateInfo.Count
            }
            
            if ($UpdateInfo.Count -gt 0) {
                Write-Host "  $Computer has $($UpdateInfo.Count) pending updates" -ForegroundColor Yellow
            } else {
                Write-Host "  $Computer has no pending updates" -ForegroundColor Green
            }
        }
        else {
            Write-Warning "  Error checking updates on $Computer - $($UpdateInfo.Error)"
            $Results += [PSCustomObject]@{
                ComputerName = $Computer
                Status = "Error"
                Error = $UpdateInfo.Error
                PendingUpdates = "Unknown"
            }
        }
    }
    catch {
        Write-Warning "  Error processing $Computer - $($_.Exception.Message)"
        $Results += [PSCustomObject]@{
            ComputerName = $Computer
            Status = "Error"
            Error = $_.Exception.Message
            PendingUpdates = "Unknown"
        }
    }
}

# Export results to CSV
$Results | Export-Csv -Path $OutputFile -NoTypeInformation

# Display summary
$UpdateSummary = $Results | Group-Object -Property PendingUpdates | Select-Object Name, Count
Write-Host "`nUpdate Summary:" -ForegroundColor Cyan
$UpdateSummary | ForEach-Object {
    if ($_.Name -eq "0") {
        Write-Host "  $($_.Count) computer(s) have no pending updates." -ForegroundColor Green
    }
    elseif ($_.Name -eq "Unknown") {
        Write-Host "  $($_.Count) computer(s) could not be checked." -ForegroundColor Red
    }
    else {
        Write-Host "  $($_.Count) computer(s) have $($_.Name) pending updates." -ForegroundColor Yellow
    }
}

Write-Host "`nResults exported to $OutputFile" -ForegroundColor Green

# Show troubleshooting tips if errors encountered
if ($Results | Where-Object { $_.Status -eq "Error" }) {
    Write-Host "`nTroubleshooting Tips:" -ForegroundColor Yellow
    Write-Host "=====================" -ForegroundColor Yellow
    Write-Host "1. Verify WinRM is properly configured on remote computers:"
    Write-Host "   - Run as administrator: winrm quickconfig"
    Write-Host "   - Test connectivity: Test-WSMan -ComputerName COMPUTER_NAME"
    Write-Host ""
    Write-Host "2. Try testing WinRM connectivity only:"
    Write-Host "   - .\check-updates-minimal.ps1 -ComputerNames COMPUTER_NAME -TestWinRMOnly"
    Write-Host ""
    Write-Host "3. Try alternative connection method (DCOM/RPC):"
    Write-Host "   - .\check-updates-minimal.ps1 -ComputerNames COMPUTER_NAME -UseLocalWUAPI"
    Write-Host ""
    Write-Host "4. Check Windows Update service status on remote computers:"
    Write-Host "   - Invoke-Command -ComputerName COMPUTER_NAME -ScriptBlock { Get-Service wuauserv }"
    Write-Host ""
    Write-Host "5. Check permissions (ensure you have admin rights on remote computers)"
    Write-Host "   - Run PowerShell as administrator"
    Write-Host "   - Verify your account is in the Administrators group on remote computers"
    Write-Host "=====================" -ForegroundColor Yellow
}
