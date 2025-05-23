<#
.SYNOPSIS
    This script installs the pXLabs Software Metering package by creating scheduled tasks and copying necessary files.

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

param (
    [switch]$Uninstall
)

function Get-FileMD5 {
    param ($Path)
    if (Test-Path $Path) {
        $hash = Get-FileHash -Algorithm MD5 -Path $Path
        return $hash.Hash
    }
    return $null
}

$taskFolder = "pXLabs"
$taskNameCollection = "Collect Software Metering Data"
$taskNameSync = "Sync Software Metering Data to OneDrive"
$scriptPath = "C:\ProgramData\pXLabs\SoftwareMetering\MeteringScript.ps1"
$SyncScriptPath = "C:\ProgramData\pXLabs\SoftwareMetering\SyncUsageData.ps1"

$programFolder = Split-Path $scriptPath

if ($Uninstall) {
    Write-Output "Running uninstall..."

    if (Get-ScheduledTask -TaskName $taskName -TaskPath "\$taskFolder\" -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName "$taskNameCollection" -TaskPath "\$taskFolder\" -Confirm:$false -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "$taskNameSync" -TaskPath "\$taskFolder\" -Confirm:$false -ErrorAction SilentlyContinue
        #Write-Output "Scheduled task removed."
    }

    try {
        $taskService = New-Object -ComObject "Schedule.Service"
        $taskService.Connect()
        $rootFolder = $taskService.GetFolder("\")
        $pxlabsFolder = $rootFolder.GetFolder($taskFolder)
        if ($pxlabsFolder.GetTasks(0).Count -eq 0) {
            $rootFolder.DeleteFolder($taskFolder, 0)
            #Write-Output "Empty Task Scheduler folder '$taskFolder' deleted."
        }
    } catch {
        Write-Output "Could not delete Task Scheduler folder (may not exist or may not be empty)."
    }

    if (Test-Path "$programFolder") {
        Remove-Item -Path "$programFolder" -Recurse -Force -ErrorAction SilentlyContinue
        #Write-Output "Program folder removed."
    }

    exit 0
}

if (-not (Test-Path "$programFolder\Logs")) {
    New-Item -Path "$programFolder\Logs" -ItemType Directory -Force | Out-Null
}

"MeteringScript.ps1","ProductFilterEditor.ps1","ProductFilters.json","SyncUsageData.ps1" | ForEach-Object {
    Copy-Item -Path "$PSScriptRoot\$_" -Destination $programFolder -Force
}

$filterFileHash = (Get-FileHash -Algorithm MD5 -Path "$programFolder\ProductFilters.json").Hash
$RegPath = "SOFTWARE\pXLabs\SoftwareMetering"

$regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
$subKey = $regKey.CreateSubKey($RegPath)

$subKey.SetValue("FilterFileHash", $filterFileHash, [Microsoft.Win32.RegistryValueKind]::String)

$subKey.Close()
$regKey.Close()

$schedService = New-Object -ComObject "Schedule.Service"
$schedService.Connect()
$rootFolder = $schedService.GetFolder("\")
try {
    $rootFolder.GetFolder($taskFolder) | Out-Null
} catch {
    $rootFolder.CreateFolder($taskFolder) | Out-Null
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Once -At "12:00AM" -RepetitionInterval (New-TimeSpan -Hours 1) #-RepetitionDuration (New-TimeSpan -Days 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal
Register-ScheduledTask -TaskPath "\$taskFolder" -TaskName "$taskNameCollection" -InputObject $task -Force | Out-Null

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$syncScriptPath`""
$Trigger = New-ScheduledTaskTrigger -Once -At "12:00AM" -RepetitionInterval (New-TimeSpan -Hours 4) #-RepetitionDuration (New-TimeSpan -Days 1)
Register-ScheduledTask -TaskName "$taskNameSync" -Action $Action -Trigger $Trigger -TaskPath "\$TaskFolder\" -Description "Sync metering CSV to OneDrive" -RunLevel Highest -Force | Out-Null

