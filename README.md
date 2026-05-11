# PowerControl

A PowerShell utility that lets you switch Windows **"Lid, power and sleep button controls"** from the task tray with a single click.

## Who This Is For

### People who want Claude Code / Codex to keep running while they move around

AI coding agents such as Claude Code and OpenAI Codex can spend several minutes, or sometimes tens of minutes, thinking, generating code, and running tests on longer tasks.
If your laptop goes to sleep because you closed the lid in the middle of that work, the agent stops too.

With this app:

- **Before leaving**: choose **"Work Mode"** from the tray with one click, so closing the lid does not put the PC to sleep
- **While commuting or moving to a cafe**: Claude Code / Codex keeps working in your bag
- **When you arrive**: open the lid, check the result, and switch back to **"Normal Mode"** when you are done

No more clicking through six separate settings in the Windows Settings app every time.

### Other Use Cases

- Prevent accidental sleep during presentations or recordings
- Use stricter power saving only when running on battery
- Turn off the display while stepping away without stopping the PC

## Features

- Runs in the task tray and switches modes instantly via right-click or left-click
- Includes three default presets (**Normal Mode / Work Mode / Power Saving Mode**) and supports adding, editing, and deleting custom presets
- Each preset controls the following six settings at once:
  - What happens when the power button is pressed (AC / battery)
  - What happens when the sleep button is pressed (AC / battery)
  - What happens when the lid is closed (AC / battery)
  - Each setting can be set to "Do nothing / Sleep / Hibernate / Shut down"
- When **"Register for startup"** is enabled, the app starts automatically on future logons without a UAC prompt (Task Scheduler + highest privileges)

## Requirements

- Windows 10 / 11
- Windows PowerShell 5.1 (included with Windows)
- Administrator privileges (a UAC prompt appears at launch because `powercfg` changes the active power plan)

## Usage

1. Download this repository as a ZIP file or clone it with `git clone`
2. Double-click `PowerControl.bat`
3. Approve the UAC prompt, then the tray icon appears
4. Right-click the icon and choose the preset you want

On first launch, `presets.json` (preset definitions) and `state.json` (the most recently applied preset) are generated automatically.

### If Windows Blocks the Script

If Windows blocks the app because the files were downloaded from the internet, unblock the files once and launch it again:

```powershell
cd path\to\PowerControl
Unblock-File .\PowerControl.ps1
Unblock-File .\PowerControl.bat
.\PowerControl.bat
```

PowerControl uses `RemoteSigned` when launching PowerShell. It does not use `ExecutionPolicy Bypass`.

### Customizing Presets

Open **"Preset settings..."** from the tray menu to edit presets in the GUI. The layout and choices mirror the Windows Settings app, so it should feel familiar.

### Auto Start

Click **"Register for startup"** in the tray menu to register a Task Scheduler task that starts the app automatically when you sign in to Windows. It is registered with `RunLevel=Highest`, so no UAC prompt appears at startup. You can disable it from the same menu.

## How It Works

Internally, the app calls `powercfg.exe` and updates the following three GUID settings under the SUB_BUTTONS subgroup of the currently active power plan, for both AC and DC power.

| Setting | GUID |
|---|---|
| Power button (PBUTTONACTION) | `7648efa3-dd9c-4e3e-b566-50f929386280` |
| Sleep button (SBUTTONACTION) | `96996bc0-ad50-47ec-923b-6f41874dd9eb` |
| Lid close action (LIDACTION) | `5ca83367-6e45-459f-a27b-476b1d01c936` |

Values are `0=Do nothing / 1=Sleep / 2=Hibernate / 3=Shut down`.

On newer versions of Windows, these items are hidden by default in `powercfg /query`, but `/setacvalueindex` and `/setdcvalueindex` still work when the GUIDs are specified directly.

## File Layout

```
PowerControl.ps1     Main script (tray app + WPF preset editor window)
PowerControl.bat     Launcher batch file (runs the .ps1 with -NoProfile / -STA / RemoteSigned)
presets.json         Preset definitions (generated automatically on first launch)
state.json           Most recently applied preset name (generated automatically)
```

## License

MIT
