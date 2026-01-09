<#
.SYNOPSIS
    Enumerates all registered URI protocol handlers on Windows with usage examples.

.DESCRIPTION
    Scans the registry for URL protocol handlers and displays detailed information
    about each handler including the command, executable path, arguments, and programmatic usage.

.PARAMETER ExportPath
    Optional path to export results to a CSV file.

.PARAMETER FilterPattern
    Optional regex pattern to filter URI handlers by name.

.PARAMETER ShowExamples
    Show example usage for each URI handler.

.EXAMPLE
    .\Get-URIHandlers.ps1
    
.EXAMPLE
    .\Get-URIHandlers.ps1 -ExportPath "C:\handlers.csv"
    
.EXAMPLE
    .\Get-URIHandlers.ps1 -FilterPattern "^ms" -ShowExamples
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ExportPath,
    
    [Parameter(Mandatory=$false)]
    [string]$FilterPattern,
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowExamples
)

function Get-FileDescription {
    param([string]$FilePath)
    
    if (Test-Path $FilePath -ErrorAction SilentlyContinue) {
        try {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
            return $versionInfo.FileDescription
        }
        catch {
            return $null
        }
    }
    return $null
}

function Get-URIUsageExamples {
    param([string]$Protocol)
    
    # Common examples based on protocol patterns
    $examples = @{
        'http'      = 'Start-Process "http://example.com"'
        'https'     = 'Start-Process "https://example.com"'
        'mailto'    = 'Start-Process "mailto:user@example.com?subject=Hello"'
        'tel'       = 'Start-Process "tel:+1234567890"'
        'sms'       = 'Start-Process "sms:+1234567890?body=Hello"'
        'callto'    = 'Start-Process "callto:+1234567890"'
        'skype'     = 'Start-Process "skype:username?call"'
        'steam'     = 'Start-Process "steam://rungameid/480"'
        'discord'   = 'Start-Process "discord://"'
        'spotify'   = 'Start-Process "spotify:track:..."'
        'msteams'   = 'Start-Process "msteams://"'
        'zoom'      = 'Start-Process "zoommtg://zoom.us/join?..."'
        'slack'     = 'Start-Process "slack://open"'
    }
    
    # Pattern-based examples
    if ($Protocol -match '^ms-') {
        return "Start-Process `"${Protocol}:`" # Microsoft system protocol"
    }
    
    if ($examples.ContainsKey($Protocol.ToLower())) {
        return $examples[$Protocol.ToLower()]
    }
    
    return "Start-Process `"${Protocol}:...`""
}

function Get-AdditionalRegistryInfo {
    param([string]$RegistryPath)
    
    $info = @{
        DefaultIcon = $null
        FriendlyName = $null
        AppUserModelID = $null
        EditFlags = $null
    }
    
    # Get default icon
    $iconPath = Join-Path $RegistryPath "DefaultIcon"
    if (Test-Path $iconPath) {
        $info.DefaultIcon = (Get-ItemProperty $iconPath -ErrorAction SilentlyContinue).'(default)'
    }
    
    # Get friendly name or app name
    $props = Get-ItemProperty $RegistryPath -ErrorAction SilentlyContinue
    if ($props) {
        $info.FriendlyName = $props.'FriendlyTypeName'
        if (-not $info.FriendlyName) {
            $info.FriendlyName = $props.'(default)'
        }
        $info.AppUserModelID = $props.'AppUserModelID'
        $info.EditFlags = $props.'EditFlags'
    }
    
    return $info
}

function Get-URIHandlers {
    param(
        [string]$Filter,
        [switch]$IncludeExamples
    )
    
    # Check if HKCR: drive exists, create if needed
    if (-not (Test-Path HKCR:)) {
        try {
            New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction Stop | Out-Null
            $driveCreated = $true
        }
        catch {
            Write-Warning "Could not create HKCR: drive. Trying alternative method..."
            $driveCreated = $false
        }
    }
    
    $handlers = [System.Collections.Generic.List[PSCustomObject]]::new()
    $count = 0
    
    Write-Host "Scanning registry for URI handlers..." -ForegroundColor Cyan
    Write-Host ""
    
    Get-ChildItem HKCR: -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        
        # Check if this is a URL protocol handler
        if ($props.PSObject.Properties.Name -contains "URL Protocol") {
            $name = $_.PSChildName
            
            # Apply filter if specified
            if ($Filter -and $name -notmatch $Filter) {
                return
            }
            
            $count++
            
            # Get command from shell\open\command subkey
            $cmdKey = Join-Path $_.PSPath "shell\open\command"
            $command = $null
            
            if (Test-Path $cmdKey) {
                $command = (Get-ItemProperty $cmdKey -ErrorAction SilentlyContinue).'(default)'
            }
            
            # Parse executable and arguments
            $exe = $null
            $args = $null
            
            if ($command) {
                # Handle quoted paths
                if ($command -match '^"([^"]+)"\s*(.*)$') {
                    $exe  = $matches[1]
                    $args = $matches[2].Trim()
                }
                # Handle unquoted paths
                elseif ($command -match '^([^\s]+)\s*(.*)$') {
                    $exe  = $matches[1]
                    $args = $matches[2].Trim()
                }
                else {
                    $exe = $command
                }
            }
            
            # Check if executable exists and get description
            $exeExists = $false
            $fileDescription = $null
            if ($exe -and (Test-Path $exe -ErrorAction SilentlyContinue)) {
                $exeExists = $true
                $fileDescription = Get-FileDescription -FilePath $exe
            }
            
            # Get additional registry information
            $additionalInfo = Get-AdditionalRegistryInfo -RegistryPath $_.PSPath
            
            # Generate usage example
            $usageExample = Get-URIUsageExamples -Protocol $name
            
            # Create handler object
            $handler = [PSCustomObject]@{
                Number          = $count
                Protocol        = $name
                Command         = if ($command) { $command } else { "<none>" }
                Executable      = if ($exe) { $exe } else { "<unknown>" }
                Arguments       = if ($args) { $args } else { "<none>" }
                ExeExists       = $exeExists
                FileDescription = if ($fileDescription) { $fileDescription } else { "<none>" }
                FriendlyName    = if ($additionalInfo.FriendlyName) { $additionalInfo.FriendlyName } else { "<none>" }
                DefaultIcon     = if ($additionalInfo.DefaultIcon) { $additionalInfo.DefaultIcon } else { "<none>" }
                AppUserModelID  = if ($additionalInfo.AppUserModelID) { $additionalInfo.AppUserModelID } else { "<none>" }
                UsageExample    = $usageExample
                RegistryPath    = $_.PSPath
            }
            
            $handlers.Add($handler)
            
            # Display formatted output
            Write-Host ("=" * 80) -ForegroundColor DarkGray
            Write-Host ("URI Handler {0:d4}: {1}" -f $count, $name) -ForegroundColor Yellow
            Write-Host ("  Command        : {0}" -f $handler.Command) -ForegroundColor Gray
            Write-Host ("  Executable     : {0}" -f $handler.Executable) -ForegroundColor $(if ($exeExists) { "Green" } else { "Red" })
            Write-Host ("  Arguments      : {0}" -f $handler.Arguments) -ForegroundColor Gray
            
            if ($fileDescription) {
                Write-Host ("  Description    : {0}" -f $fileDescription) -ForegroundColor Cyan
            }
            
            if ($additionalInfo.FriendlyName -and $additionalInfo.FriendlyName -ne $name) {
                Write-Host ("  Friendly Name  : {0}" -f $additionalInfo.FriendlyName) -ForegroundColor Cyan
            }
            
            if ($additionalInfo.AppUserModelID) {
                Write-Host ("  App Model ID   : {0}" -f $additionalInfo.AppUserModelID) -ForegroundColor Cyan
            }
            
            if (-not $exeExists -and $exe) {
                Write-Host ("  Status         : Executable not found") -ForegroundColor Red
            }
            
            if ($IncludeExamples) {
                Write-Host ""
                Write-Host ("  Programmatic Usage:") -ForegroundColor Magenta
                Write-Host ("    PowerShell   : {0}" -f $usageExample) -ForegroundColor White
                Write-Host ("    C#           : System.Diagnostics.Process.Start(`"{0}:...`");" -f $name) -ForegroundColor White
                Write-Host ("    Python       : import webbrowser; webbrowser.open(`"{0}:...`")" -f $name) -ForegroundColor White
                Write-Host ("    JavaScript   : window.location.href = `"{0}:...`";" -f $name) -ForegroundColor White
                Write-Host ("    Command Line : start {0}:..." -f $name) -ForegroundColor White
            }
            
            Write-Host ""
        }
    }
    
    # Summary
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ("Total URI handlers found: {0}" -f $count) -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    # Cleanup PSDrive if we created it
    if ($driveCreated) {
        Remove-PSDrive -Name HKCR -ErrorAction SilentlyContinue
    }
    
    return $handlers
}

# Main execution
$results = Get-URIHandlers -Filter $FilterPattern -IncludeExamples:$ShowExamples

# Export to CSV if requested
if ($ExportPath -and $results) {
    try {
        $results | Select-Object Number, Protocol, Command, Executable, Arguments, ExeExists, `
                                 FileDescription, FriendlyName, AppUserModelID, UsageExample, RegistryPath | 
                   Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export to CSV: $_"
    }
}

# Optionally show a quick reference
if ($ShowExamples) {
    Write-Host ""
    Write-Host "Quick Reference - Common URI Handler Usage Patterns:" -ForegroundColor Yellow
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "PowerShell:" -ForegroundColor Cyan
    Write-Host '  Start-Process "protocol://path"' -ForegroundColor White
    Write-Host '  [System.Diagnostics.Process]::Start("protocol://path")' -ForegroundColor White
    Write-Host ""
    Write-Host "Command Prompt / Batch:" -ForegroundColor Cyan
    Write-Host '  start protocol://path' -ForegroundColor White
    Write-Host ""
    Write-Host "C# / .NET:" -ForegroundColor Cyan
    Write-Host '  System.Diagnostics.Process.Start("protocol://path");' -ForegroundColor White
    Write-Host '  System.Diagnostics.Process.Start(new ProcessStartInfo("protocol://path") { UseShellExecute = true });' -ForegroundColor White
    Write-Host ""
    Write-Host "Python:" -ForegroundColor Cyan
    Write-Host '  import webbrowser; webbrowser.open("protocol://path")' -ForegroundColor White
    Write-Host '  import subprocess; subprocess.run(["start", "protocol://path"], shell=True)' -ForegroundColor White
    Write-Host ""
    Write-Host "JavaScript (Browser):" -ForegroundColor Cyan
    Write-Host '  window.location.href = "protocol://path";' -ForegroundColor White
    Write-Host '  window.open("protocol://path");' -ForegroundColor White
    Write-Host ""
}
