# pXLabs.PoorAdminsSoftwareMeteringPackage

> 💸 Because your budget said no to Log Analytics...\
> 🛠️ But you still need to know what software your users are running!

## 🧐 What Is This?

**pXLabs.PoorAdminsSoftwareMeteringPackage** is a homemade PowerShell-based software metering solution built for Intune-managed environments that lost traditional metering when moving away from ConfigMgr. It's lightweight, runs silently in the background, and logs application usage to a simple CSV.

Then, because we’re resourceful, we sync the results to **OneDrive**, **SharePoint**, or any other location your budget will tolerate.

This is for all the admins out there that are **"missing our software metering data because we moved to Intune"**. You’re not alone.

---

## 🔍 What It Does

- 🕵️ Tracks process start and stop events (Event IDs 4688 & 4689)
- ⏱ Correlates runtime durations
- 🫼 Filters system and noise processes
- 📋 Outputs usage logs to simple CSV files
- ☁️ Supports syncing results to OneDrive or other paths
- 🛡 Works without Log Analytics, Endpoint Analytics, or any paid plans
- 🧰 Comes with a basic GUI to manage filter rules

---

## 📦 What’s Included

- `Install.ps1`: Installs the background scheduled task. Also supports uninstall via `-Uninstall` switch.
- `Detect.ps1`: Used with Intune detection logic
- `SoftwareMetering.ps1`: The main metering script
- `ProductFilterEditor.ps1`: A GUI editor for managing product/version filters
- `ProductFilters.json`: Customize which apps to include
- `SyncUsageData.ps1`: Onedrive sync routine

---

## 🚀 How It Works

1. **Scheduled Task** runs the metering script hourly (hidden + silent).
2. Script reads filters from `ProductFilters.json` (which you can manage with a built-in GUI).
3. It queries Event Logs for new process starts and stops, pairs them up, calculates runtime, and writes to CSV.
4. CSV is saved to a local path (e.g., `C:\ProgramData\pXLabs\SoftwareMetering\Logs\`).
5. From there? Sync to OneDrive, SharePoint, or grab it with a script. You do you.

---

## 🖼 GUI for Filter Management

Run:

```powershell
.\ProductFilterEditor.ps1
```

This lets you add, remove, or edit software filters. Don't worry, if you forget to type `.exe`, we’ll add it for you.

---

## 🛠 Requirements

- Windows 10 or 11
- PowerShell 5.1+
- Admin rights to install the task
- Event Log auditing enabled for process creation and termination

### Enabling Event Log Auditing

1. Open **Local Security Policy** (`secpol.msc`) or use a GPO
2. Navigate to **Advanced Audit Policy Configuration > System Audit Policies > Detailed Tracking**
3. Enable:
   - **Audit Process Creation**
   - **Audit Process Termination**
4. Run `gpupdate /force` or reboot to apply

---

## 🚡 Create Intune Win32 App

1. Package the scripts:
   - Place all files in a folder (e.g., `SoftwareMeteringPackage`)
   - Use the [Microsoft Win32 Content Prep Tool](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management) to create an `.intunewin` file:

```powershell
IntuneWinAppUtil.exe -c <source_folder> -s Install.ps1 -o <output_folder>
```

2. In Microsoft Intune:
   - Go to **Apps > Windows > Add**
   - Select **App type: Windows app (Win32)**
   - Upload the `.intunewin` file
   - Configure the **install command**:
     ```
     powershell.exe -ExecutionPolicy Bypass -File .\Install.ps1
     ```
   - Set the **detection rule** to use `Detect.ps1`
   - (Optional) To support uninstall, configure:
     ```
     powershell.exe -ExecutionPolicy Bypass -File .\Install.ps1 -Uninstall
     ```
   - Assign to your devices or user group

---

## 📅 Output Format

CSV columns include:

- Timestamp
- ComputerName
- UserName
- Product
- Version
- Runtime (in minutes.seconds)

---

## 🤔 Why This Exists

Because you:

- Moved to Intune and lost metering
- Don't have Microsoft E5 licenses
- Can't enable Log Analytics or Kusto Queries
- Still need to know who's running what (and for how long)

This tool fills that gap.

---
## 🔄 Syncing Usage Logs to OneDrive
To help automate backing up your software metering logs, the install script sets up a scheduled task that runs the `SyncUsageData.ps1` script every 4 hours.

### What it does:

- Moves the current CSV log file (`UsageData.csv`) from the local logs folder (`C:\ProgramData\pXLabs\SoftwareMetering\Logs`) into your OneDrive folder under `SoftwareMetering\`

- Renames the file on move to include the computer name and timestamp, e.g., `COMPUTERNAME-UsageData-2025-05-23_14-30.csv`

- Automatically creates the OneDrive folder if it doesn’t exist

- Cleans up old files in OneDrive older than 30 days for space management

- If OneDrive is not detected (environment variable missing), the script exits silently without error

### How it works:

- The script expects that OneDrive is installed and signed in for the user running the scheduled task

- Files are moved, not copied, so the local `UsageData.csv` resets for fresh logging

- Old historical CSV files in OneDrive are pruned automatically

### Customization:
The `SyncUsageData.ps1` script is provided as a working example to upload logs to OneDrive. You can modify it to sync or upload the CSV files to **any other path, network share, FTP server, cloud storage, or web API endpoint** as your environment and requirements dictate. Just replace the file copy/move logic with your preferred method.



## 📡 Optional Enhancements

- Parse results into Power BI
- Extend for specific departmental apps
- Auto-upload to Azure Blob or FTP

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html). Feel free to modify, share, and contribute!

---

## 🙏 Credits

Built by Jeff Pollock @ pXLabs\
Inspired by real-world IT budgets and for all the admins doing more with less.