<#
.SYNOPSIS
    This script syncs usage data from the local system to OneDrive.
    It moves the local CSV file to a OneDrive folder and deletes older files.

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

$LocalCsvPath = "C:\ProgramData\pXLabs\SoftwareMetering\Logs\UsageData.csv"
$ComputerName = $env:COMPUTERNAME
$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm"

$OneDriveRoot = $env:OneDrive
if (-not $OneDriveRoot) {
    Write-Output "OneDrive path not detected. Exiting."
    exit 1
}

$OneDriveFolder = Join-Path $OneDriveRoot "SoftwareMetering"
$OneDriveCsv = Join-Path $OneDriveFolder "$ComputerName-UsageData-$TimeStamp.csv"

# Ensure destination directory exists
if (-not (Test-Path $OneDriveFolder)) {
    New-Item -Path $OneDriveFolder -ItemType Directory -Force | Out-Null
}

# Copy file to OneDrive
if (Test-Path $LocalCsvPath) {
    Move-Item -Path $LocalCsvPath -Destination $OneDriveCsv -Force
}

# Delete files older than 30 days
Get-ChildItem -Path $OneDriveFolder -Filter "$ComputerName-UsageData-*.csv" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force
