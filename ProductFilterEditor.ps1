<#
.SYNOPSIS
    This script creates a GUI interface for managing product filters for the pXLabs Software Metering package.
    It allows users to add, modify, and delete filters for software metering.

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

Add-Type -AssemblyName PresentationFramework

function Get-ScriptDirectory {
	[OutputType([string])]
	param ()
	if ($null -ne $hostinvocation) {
		Split-Path $hostinvocation.MyCommand.path
	} else {
		Split-Path $script:MyInvocation.MyCommand.Path
	}
}

[string]$ScriptDirectory = Get-ScriptDirectory
$filterPath = Join-Path $ScriptDirectory "ProductFilters.json"

if (Test-Path $filterPath) {
    try {
        $script:FilterEntries = Get-Content -Path $filterPath -Raw | ConvertFrom-Json
        if ($script:FilterEntries -isnot [System.Collections.IEnumerable]) {
            $script:FilterEntries = @($script:FilterEntries)
        }
    } catch {
        $script:FilterEntries = @()
    }
} else {
    $script:FilterEntries = @()
}

function Save-Filters {
    $filters | ConvertTo-Json -Depth 3 | Set-Content -Path $filterPath -Encoding UTF8
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="pXLabs Software Metering Product Filters" Height="400" Width="500" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,5">
            <TextBlock Text="Product:" VerticalAlignment="Center" Width="60"/>
            <TextBox x:Name="ProductNameBox" Width="150" Margin="5,0,10,0"/>
            <TextBlock Text="Version:" VerticalAlignment="Center" Width="60"/>
            <TextBox x:Name="VersionBox" Width="150"/>
        </StackPanel>

        <Button x:Name="AddButton" Content="Add Filter" Grid.Row="1" Width="100" Height="25" Margin="0,0,0,5" HorizontalAlignment="Left"/>

        <ListBox x:Name="FilterList" Grid.Row="2" Margin="0,0,0,5"/>

        <StackPanel Orientation="Horizontal" Grid.Row="3" HorizontalAlignment="Right">
            <Button x:Name="ModifyButton" Content="Modify" Width="80" Height="30" Margin="0,0,10,0"/>
            <Button x:Name="DeleteButton" Content="Delete" Width="80" Height="30" Margin="0,0,10,0"/>
            <Button x:Name="SaveButton" Content="Save and Close" Width="120" Height="30"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$ProductNameBox = $window.FindName("ProductNameBox")
$VersionBox = $window.FindName("VersionBox")
$AddButton = $window.FindName("AddButton")
$FilterList = $window.FindName("FilterList")
$SaveButton = $window.FindName("SaveButton")
$DeleteButton = $window.FindName("DeleteButton")
$ModifyButton = $window.FindName("ModifyButton")

$FilterList.Add_MouseDoubleClick({
    $selectedIndex = $FilterList.SelectedIndex
    if ($selectedIndex -ge 0) {
        $entry = $script:FilterEntries[$selectedIndex]

        $ProductNameBox.Text = $entry.Product
        $VersionBox.Text = $entry.Version

        $script:FilterEntries = $script:FilterEntries | Where-Object { $_ -ne $entry }
        $FilterList.Items.RemoveAt($selectedIndex)
    }
})


# Populate ListBox
$script:FilterEntries | ForEach-Object {
    $FilterList.Items.Add("$($_.Product) | $($_.Version)") | Out-Null
}

$AddEntry = {
    $product = $ProductNameBox.Text.Trim()
    if (-not $product.ToLower().EndsWith(".exe")) {
        $product += ".exe"
    }
    $version = $VersionBox.Text.Trim()
    if ($product -and $version) {
        $entry = [PSCustomObject]@{
            Product = $product
            Version = $version
        }

        # Ensure $script:FilterEntries is an array before adding
        if (-not $script:FilterEntries -or $script:FilterEntries.Count -eq 0) {
            $script:FilterEntries = @()
        }

        $script:FilterEntries += $entry
        $FilterList.Items.Add("$product | $version")
        $ProductNameBox.Clear()
        $VersionBox.Clear()
    }
}

$AddButton.Add_Click({
    $AddEntry.Invoke()
})

$VersionBox.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq 'Enter') {
        $AddEntry.Invoke()
        # Prevent ding sound after Enter press
        $e.Handled = $true
    }
})

$ModifyButton.Add_Click({
    $selectedIndex = $FilterList.SelectedIndex
    if ($selectedIndex -ge 0) {
        $entry = $script:FilterEntries[$selectedIndex]
        $ProductNameBox.Text = $entry.Product
        $VersionBox.Text = $entry.Version

        $FilterList.Items.RemoveAt($selectedIndex)
        $script:FilterEntries = @($script:FilterEntries | Where-Object { $_ -ne $entry })
    } else {
        [System.Windows.MessageBox]::Show("Please select a filter to modify.", "No Selection", "OK", "Warning")
    }
})

$DeleteButton.Add_Click({
    $selectedIndex = $FilterList.SelectedIndex
    if ($selectedIndex -ge 0) {
        $entryToRemove = $script:FilterEntries[$selectedIndex]
        $script:FilterEntries = @($script:FilterEntries | Where-Object { $_ -ne $entryToRemove })
        $FilterList.Items.RemoveAt($selectedIndex)
    } else {
        [System.Windows.MessageBox]::Show("Please select a filter to delete.", "No Selection", "OK", "Warning")
    }
})


$SaveButton.Add_Click({
    try {
        if (-not $script:FilterEntries) {
            throw "No filter entries to save."
        }

        $json = $script:FilterEntries | ConvertTo-Json -Depth 3
        Set-Content -Path $filterPath -Value $json -Encoding UTF8

        if ($Window) {
            $Window.Close()
        } 
    } catch {
        [System.Windows.MessageBox]::Show("Failed to save filters.`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
})

$window.ShowDialog() | Out-Null