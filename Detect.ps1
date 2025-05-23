<#
.SYNOPSIS
    This script is used to detect the installation of the pXLabs Software Metering package.
    It does this by checking the hash of the installed ProductFilters.json file against a value stored in the registry.

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

$installedPath = "C:\ProgramData\pXLabs\SoftwareMetering\ProductFilters.json"

function Get-FileMD5 {
    param ($Path)
    if (Test-Path $Path) {
        $hash = Get-FileHash -Algorithm MD5 -Path $Path
        return $hash.Hash
    }
    return $null
}

$installedHash = (Get-FileHash -Algorithm MD5 -Path $installedPath).Hash

$RegPath = "SOFTWARE\pXLabs\SoftwareMetering"
$ValueName = "FilterFileHash"

$regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
$subKey = $regKey.OpenSubKey($RegPath)

if ($subKey) {
    $expectedHash = $subKey.GetValue($ValueName)
    $subKey.Close()
} 

$regKey.Close()

# Ensure both files exist
if ($expectedHash -and $installedHash) {
    if ($expectedHash -eq $installedHash) {
        Write-Output "Detection successful"
        exit 0
    } else {
        Write-Output "File hash mismatch"
        exit 1
    }
}

# File missing
exit 1
