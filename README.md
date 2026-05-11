# PowerControl

A Windows tray utility that lets you switch Windows **"Lid, power and sleep button controls"** with a single click.

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
- Switches the app UI between English and Japanese from the tray menu
- Includes three default presets (**Normal Mode / Work Mode / Power Saving Mode**) and supports adding, editing, and deleting custom presets
- Each preset controls the following six settings at once:
  - What happens when the power button is pressed (AC / battery)
  - What happens when the sleep button is pressed (AC / battery)
  - What happens when the lid is closed (AC / battery)
  - Each setting can be set to "Do nothing / Sleep / Hibernate / Shut down"
- When **"Register for startup"** is enabled, the app starts automatically on future logons without a UAC prompt (Task Scheduler + highest privileges)

## Requirements

- Windows 10 / 11
- Administrator privileges (the native executable includes a `requireAdministrator` manifest because `powercfg` changes the active power plan)

## Usage

1. Download this repository as a ZIP file or clone it with `git clone`
2. Build `PowerControl.exe` locally:

   ```cmd
   Build-PowerControl.bat
   ```

3. Double-click `PowerControl.exe`
4. Approve the required UAC prompt, then the tray icon appears
5. Right-click the icon and choose the preset you want

You can also run `PowerControl.bat`. It rebuilds `PowerControl.exe` first so stale local builds are replaced, then starts the native app. The UAC prompt comes from the native app's `requireAdministrator` manifest; the batch file does not self-elevate.

On first launch, `presets.json` (preset definitions) and `state.json` (the most recently applied preset) are generated automatically.

### Language

Open **Language** from the tray menu and choose **English** or **日本語**. The selected language is saved in `state.json`.

### Smart App Control

PowerControl is currently unsigned. On Windows 11 systems with Smart App Control enabled, Windows may block unsigned or low-reputation apps even when they are harmless.

If Smart App Control blocks `PowerControl.exe`, the reliable fix is to sign it with an RSA code-signing certificate from a trusted provider, or with Microsoft's Trusted Signing service. A self-signed certificate is useful for testing, but it is not a dependable Smart App Control distribution solution.

This repository does not include a prebuilt `.exe`, because an unsigned executable downloaded from GitHub is likely to be blocked by Smart App Control.

You can still build the app locally:

```cmd
%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /win32manifest:PowerControl.exe.manifest /out:PowerControl.exe /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Runtime.Serialization.dll PowerControl.cs
PowerControl.exe
```

For distribution to other Smart App Control protected devices, sign `PowerControl.exe` before publishing it.

### Code Signing

Install the Windows SDK so `signtool.exe` is available, then build and sign the app locally.

Sign with a `.pfx` code-signing certificate:

```powershell
.\Build-PowerControl.bat
.\Sign-PowerControl.ps1 -PfxPath C:\path\to\codesign.pfx
```

Sign with a certificate already installed in the Windows certificate store:

```powershell
.\Build-PowerControl.bat
.\Sign-PowerControl.ps1 -CertificateThumbprint YOUR_CERT_THUMBPRINT
```

The signing script timestamps the signature with DigiCert's timestamp server by default and verifies the result with `signtool verify /pa /v`.

Do not commit certificates, private keys, or passwords. This repository ignores common certificate file formats such as `.pfx`, `.p12`, `.cer`, `.crt`, `.pvk`, and `.spc`.

### Legacy PowerShell Version

The legacy PowerShell version is still included. If Windows blocks it because the files were downloaded from the internet, unblock the files once and launch it again:

```powershell
cd path\to\PowerControl
Unblock-File .\PowerControl.ps1
Unblock-File .\PowerControl.bat
.\PowerControl.bat
```

The legacy PowerShell launcher uses `RemoteSigned`. It does not use `ExecutionPolicy Bypass`.

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
PowerControl.cs      Source for the native Windows tray app
PowerControl.exe.manifest
                     Requires administrator privileges at launch
Build-PowerControl.bat
                     Builds PowerControl.exe with the .NET Framework C# compiler
Sign-PowerControl.ps1
                     Signs and verifies PowerControl.exe with signtool.exe
PowerControl.ps1     Legacy PowerShell version (tray app + WPF preset editor window)
PowerControl.bat     Launcher batch file (rebuilds and starts the native app)
presets.json         Preset definitions (generated automatically on first launch)
state.json           Most recently applied preset name and language (generated automatically)
```

## License

MIT
