<#
.SYNOPSIS
    This script scans for process start and termination events for products listed in the ProductFilters.json file
    and logs them to a CSV file. It also monitors the state of running processes and filters them.

.DESCRIPTION
    This script is part of the pXLabs.PoorAdminsSoftwareMeteringPackage.
    Created to provide lightweight software metering for Intune-managed systems.

.AUTHOR
    Jeff Pollock (@ pXLabs)

.LICENSE
    GNU General Public License v3.0

.LAST UPDATED
    2025-05-23

.NOTES
    This script is intended for use in environments where traditional metering tools are unavailable or unaffordable.
#>

$ProgramFolder = "C:\ProgramData\pXLabs\SoftwareMetering"
$filterPath = Join-path $ProgramFolder "ProductFilters.json"
$StateFile = Join-path $ProgramFolder "Logs\ProcessState.json"
$exportRegistryPath = Join-path $ProgramFolder "Logs\ExportedSessions.json"
$csvPath = Join-path $ProgramFolder "Logs\UsageData.csv"
$retentionDays = 30

$filtersJson = Get-Content $filterPath -Raw
$filters = $FiltersJson | ConvertFrom-Json
$processState = @()

function Confirm-Array($inputObject) {
    if ($null -eq $inputObject) {
        return @()
    } elseif ($inputObject -is [System.Array]) {
        return $inputObject
    } elseif ($inputObject -is [System.Collections.IEnumerable]) {
        return @($inputObject)
    } else {
        return @($inputObject)
    }
}

function MatchesFilter {
    param (
        [string]$exePath,
        [hashtable]$filterMap
    )

    if (-not $exePath) { return $false }
    $exeName = [System.IO.Path]::GetFileName($exePath).ToLower()

    if (-not $filterMap.ContainsKey($exeName)) {
        return $false
    }

    try {
        $version = (Get-Item $exePath).VersionInfo.ProductVersion
    } catch {
        $version = ""
    }

    foreach ($versionPattern in $filterMap[$exeName]) {
        if ($versionPattern -eq "*" -or $version -like $versionPattern) {
            return $true
        }
    }
    return $false
}
    
function Get-EventData {
    param ($processEvent, $isStart)

    $xml = [xml]$processEvent.ToXml()
    $data = $xml.Event.EventData.Data
    $dict = @{}
    foreach ($d in $data) {
        $dict[$d.Name] = $d.'#text'
    }

    $rawPid = if ($isStart) { $dict["NewProcessId"] } else { $dict["ProcessId"] }

    if ([string]::IsNullOrWhiteSpace($rawPid)) {
        return $null
    }

    try {
        if ($rawPid -match '^0x[0-9a-fA-F]+$') {
            $pidDec = [convert]::ToInt32($rawPid, 16)
        } else {
            $pidDec = [int]$rawPid
        }
    } catch {
        return $null
    }

    $exePath = if ($isStart) { $dict["NewProcessName"] } else { $null }
    $user = $dict["SubjectUserName"]

    return @{ PID = "$pidDec"; ExePath = $exePath; User = $user }
}    

# Load or initialize state with safe array handling
if (Test-Path $StateFile) {
    $jsonContent = Get-Content $StateFile -Raw

    if ([string]::IsNullOrWhiteSpace($jsonContent)) {
        $processState = @()
    } else {
        $deserialized = $jsonContent | ConvertFrom-Json

        if ($null -eq $deserialized) {
            $processState = @()
        } else {
            # Ensure it's an array
            if ($deserialized -isnot [System.Collections.IEnumerable]) {
                $processState = @($deserialized)
            } else {
                $processState = $deserialized
            }
        }
    }
} else {
    $processState = @()
    $directory = Split-Path $StateFile
    if (-not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
}

# Normalize filters into a map for quick lookup
$filterMap = @{}
    
foreach ($entry in $filters) {
    $product = $entry.Product.ToLower()
    $version = [string]$entry.Version

    if (-not $filterMap.ContainsKey($product)) {
        $filterMap[$product] = @($version)
    } else {
        $existing = $filterMap[$product]

        # Ensure actual array, not wrapped PSObject
        if ($existing -is [System.Management.Automation.PSObject]) {
            $existing = @($existing | ForEach-Object { $_ })
        }

        $filterMap[$product] = @($existing) + @($version)
    }
}

# Define time window conservatively for start events (avoid missing recent ones)
$lastRunTime = (Get-Date).AddMinutes(-60)

# Get 'process start' and 'terminated process' events
$startEvents = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4688; StartTime = $lastRunTime } -ErrorAction SilentlyContinue
$endEvents = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4689; StartTime = $lastRunTime } -ErrorAction SilentlyContinue
    
# Add new start events
foreach ($event in $startEvents) {
    $eventData = Get-EventData -processEvent $event -isStart $true
    if ($null -ne $eventData -and (MatchesFilter -exePath $eventData.ExePath -filterMap $filterMap)) {
        if (-not ($processState | Where-Object { $_.PID -eq $eventData.PID })) {
            $version = ""
            try {
                $version = (Get-Item $eventData.ExePath).VersionInfo.ProductVersion
            } catch { continue }
                
            if ($processState -isnot [System.Collections.IList]) {
                $processState = @($processState)
            }

            $processState += [PSCustomObject]@{
                PID        = $eventData.PID
                Executable = [System.IO.Path]::GetFileName($eventData.ExePath)
                Version    = $version
                StartTime  = $event.TimeCreated.ToLocalTime()
                User       = $eventData.User
            }
        }
    }
}

    
$exportedKeys = @{}
if (Test-Path $exportRegistryPath) {
    $temp = Get-Content $exportRegistryPath -Raw | ConvertFrom-Json
    foreach ($entry in $temp.PSObject.Properties) {
        $exportedKeys[$entry.Name] = $entry.Value
    }
}

$completedSessions = @()

foreach ($event in $endEvents) {        
    $eventData = Get-EventData -processEvent $event -isStart $false
    if ($null -eq $eventData) { continue }

    $startEntry = $processState | Where-Object {
        $_.PID -eq $eventData.PID -and $_.User -eq $eventData.User
    } | Sort-Object StartTime | Select-Object -First 1

    if ($startEntry) {            
        $startTime = [datetime]$startEntry.StartTime.ToLocalTime()
        $endTime = $event.TimeCreated.ToLocalTime()
        $duration = $endTime - $startTime
            
        $sessionKey = "$($eventData.PID)_$($startTime.ToString("o"))_$($eventData.User)"
            
        if (-not $exportedKeys.ContainsKey($sessionKey)) {
            $completedSessions += [PSCustomObject]@{
                PID          = $eventData.PID
                Executable   = $startEntry.Executable
                Version      = $startEntry.Version
                Computername = $env:COMPUTERNAME
                User         = $startEntry.User
                StartTime    = $startTime
                EndTime      = $endTime
                Duration     = [math]::Round($duration.TotalMinutes, 2)
            }
            $exportedKeys[$sessionKey] = $endTime.ToString("o")                
        }

        $processState = Confirm-Array ($processState | Where-Object {
                !($_.PID -eq $eventData.PID -and ([datetime]$_.StartTime -eq $startTime))
        })
    }
}

# Clean up stale processes
$maxLifetime = [TimeSpan]::FromHours(24)
$currentTime = Get-Date

$processState = Confirm-Array ($processState | Where-Object {
    $pidInt = 0
    [int]::TryParse($_.PID, [ref]$pidInt) | Out-Null
    $stillRunning = Get-Process -Id $pidInt -ErrorAction SilentlyContinue
    $age = $currentTime - ([datetime]$_.StartTime)
    return $stillRunning -and $age -lt $maxLifetime
})

# Add currently running, untracked filtered processes
$existingPIDs = [System.Collections.Generic.HashSet[string]]::new()
$processState | ForEach-Object { [void]$existingPIDs.Add($_.PID) }

$targetNames = $filterMap.Keys
Get-Process | Where-Object {
    $targetNames -contains ($_.Name + ".exe").ToLower()
} | ForEach-Object {
    $proc = $_
    $exePath = $null
    try {
        $exePath = $_.Path
    } catch { return }

    if ($exePath -and (MatchesFilter -exePath $exePath -filterMap $filterMap)) {
        $procId = "$($proc.Id)"
        if (-not $existingPIDs.Contains($procId)) {
            $version = ""
            try {
                $version = (Get-Item $exePath).VersionInfo.ProductVersion
            } catch { continue }

            $user = try {
                $wmi = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)"
                $owner = $wmi | Invoke-CimMethod -MethodName GetOwner
                if ($owner.ReturnValue -eq 0) { $owner.User } else { $env:USERNAME }
            } catch {
                $env:USERNAME
            }

            if ($null -eq $processState) {
                $processState = @()
            } elseif (-not ($processState -is [System.Array])) {
                $processState = @($processState)
            }

            $processState += [PSCustomObject]@{
                PID        = $procId
                Executable = $proc.Name + ".exe"
                Version    = $version
                StartTime  = $proc.StartTime
                User       = $user
            }
        }
    }
}

$processState | ConvertTo-Json -Depth 3 | Set-Content -Encoding utf8 $StateFile    

if ($completedSessions.Count -gt 0) {
    if (-not (Test-Path -Path (Split-Path $csvPath))) {
        New-Item -Path (Split-Path $csvPath) -ItemType Directory -Force | Out-Null
    } 

    # Remove duplicates from completedSessions array by session key
    $completedSessions = $completedSessions | Sort-Object PID, StartTime, User -Unique
    $completedSessions | Export-Csv -Path $csvPath -NoTypeInformation -Append
                
    $cutoffDate = (Get-Date).AddDays(-$retentionDays)

    $cleanedExportedKeys = @{}
    foreach ($key in $exportedKeys.Keys) {
        $endTime = $exportedKeys[$key] -as [datetime]
        if ($endTime -and $endTime -gt $cutoffDate) {
            $cleanedExportedKeys[$key] = $exportedKeys[$key]
        }
    }
    $exportedKeys = $cleanedExportedKeys
    $exportedKeys | ConvertTo-Json -Depth 3 | Set-Content -Encoding utf8 $exportRegistryPath
}