#Requires -Version 5.1
<#
PowerControl.ps1
Task tray app for switching power button, sleep button, and lid close actions
#>

# ----- Self elevation (administrator privileges) -----
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'RemoteSigned', '-File', "`"$PSCommandPath`"")
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit
}

# ----- Single instance guard -----
$createdNew = $false
$Script:SingleInstanceMutex = New-Object System.Threading.Mutex($true, 'Global\PowerControl_SingleInstance_2A7C', [ref]$createdNew)
if (-not $createdNew) { exit }

# ----- Assemblies -----
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ----- Constants -----
$Script:SUB_BUTTONS = '4f971e89-eebd-4455-a8de-9e59040e7347'
$Script:GUID_POWER  = '7648efa3-dd9c-4e3e-b566-50f929386280'  # Power button
$Script:GUID_SLEEP  = '96996bc0-ad50-47ec-923b-6f41874dd9eb'  # Sleep button
$Script:GUID_LID    = '5ca83367-6e45-459f-a27b-476b1d01c936'  # Lid close

$Script:ACTION_NAMES = @{
    0 = 'Do nothing'
    1 = 'Sleep'
    2 = 'Hibernate'
    3 = 'Shut down'
}

$Script:ScriptDir   = Split-Path -Parent $PSCommandPath
$Script:PresetsPath = Join-Path $Script:ScriptDir 'presets.json'
$Script:StatePath   = Join-Path $Script:ScriptDir 'state.json'
$Script:TaskName    = 'PowerControlAutoStart'

# ----- Preset loading and saving -----
function Get-DefaultPresets {
    [PSCustomObject]@{
        presets = @(
            [PSCustomObject]@{
                name        = 'Normal Mode'
                description = 'Power button, sleep button, and lid close all put the PC to sleep'
                power = [PSCustomObject]@{ ac = 1; dc = 1 }
                sleep = [PSCustomObject]@{ ac = 1; dc = 1 }
                lid   = [PSCustomObject]@{ ac = 1; dc = 1 }
            },
            [PSCustomObject]@{
                name        = 'Work Mode'
                description = 'Do nothing for all actions (for presentations and long-running work)'
                power = [PSCustomObject]@{ ac = 0; dc = 0 }
                sleep = [PSCustomObject]@{ ac = 0; dc = 0 }
                lid   = [PSCustomObject]@{ ac = 0; dc = 0 }
            },
            [PSCustomObject]@{
                name        = 'Power Saving Mode'
                description = 'Sleep for all actions (battery saving)'
                power = [PSCustomObject]@{ ac = 1; dc = 1 }
                sleep = [PSCustomObject]@{ ac = 1; dc = 1 }
                lid   = [PSCustomObject]@{ ac = 1; dc = 1 }
            }
        )
    }
}

function Load-Presets {
    if (-not (Test-Path $Script:PresetsPath)) {
        $defaults = Get-DefaultPresets
        Save-Presets $defaults
        return $defaults
    }
    try {
        return (Get-Content -LiteralPath $Script:PresetsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to load presets.json. Restoring default presets.`n$_", 'PowerControl', 'OK', 'Warning') | Out-Null
        $defaults = Get-DefaultPresets
        Save-Presets $defaults
        return $defaults
    }
}

function Save-Presets($obj) {
    $json = $obj | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $Script:PresetsPath -Value $json -Encoding UTF8
}

function Load-State {
    if (-not (Test-Path $Script:StatePath)) { return [PSCustomObject]@{ lastPreset = $null } }
    try { return (Get-Content -LiteralPath $Script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return [PSCustomObject]@{ lastPreset = $null } }
}

function Save-State($obj) {
    ($obj | ConvertTo-Json -Depth 3) | Set-Content -LiteralPath $Script:StatePath -Encoding UTF8
}

# ----- powercfg logic -----
$Script:PowerCfg = Join-Path ([Environment]::GetFolderPath('System')) 'powercfg.exe'

function Invoke-PowerCfg {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = & $Script:PowerCfg @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg.exe failed (exit $LASTEXITCODE): $($output -join "`n")"
    }
    return $output
}

function Get-ActiveSchemeGuid {
    $out = Invoke-PowerCfg /getactivescheme
    $match = [regex]::Match([string]::Join("`n", $out), '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    if ($match.Success) { return $match.Groups[1].Value }
    throw 'Could not get the GUID of the active power plan.'
}

function Test-ActionValue([int]$value) {
    if ($value -lt 0 -or $value -gt 3) {
        throw "Preset action values must be between 0 and 3 (got $value)."
    }
}

function Apply-Preset($preset) {
    $scheme = Get-ActiveSchemeGuid
    $pairs = @(
        @{ guid = $Script:GUID_POWER; ac = [int]$preset.power.ac; dc = [int]$preset.power.dc },
        @{ guid = $Script:GUID_SLEEP; ac = [int]$preset.sleep.ac; dc = [int]$preset.sleep.dc },
        @{ guid = $Script:GUID_LID;   ac = [int]$preset.lid.ac;   dc = [int]$preset.lid.dc }
    )
    foreach ($p in $pairs) {
        Test-ActionValue $p.ac
        Test-ActionValue $p.dc
        Invoke-PowerCfg /setacvalueindex $scheme $Script:SUB_BUTTONS $p.guid $p.ac | Out-Null
        Invoke-PowerCfg /setdcvalueindex $scheme $Script:SUB_BUTTONS $p.guid $p.dc | Out-Null
    }
    Invoke-PowerCfg /setactive $scheme | Out-Null

    $state = Load-State
    $state | Add-Member -NotePropertyName lastPreset -NotePropertyValue $preset.name -Force
    Save-State $state
}

# ----- Task Scheduler registration -----
function Test-AutoStart {
    try {
        $t = Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction Stop
        return $null -ne $t
    } catch { return $false }
}

function Enable-AutoStart {
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $argument = '-NoProfile -STA -ExecutionPolicy RemoteSigned -File "{0}"' -f $PSCommandPath
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $Script:TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Disable-AutoStart {
    Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

# ----- WPF settings window -----
$Script:SettingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PowerControl Settings" Width="720" Height="560" WindowStartupLocation="CenterScreen">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="220"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <DockPanel Grid.Column="0" Margin="0,0,8,0">
            <TextBlock DockPanel.Dock="Top" Text="Presets" FontWeight="Bold" Margin="0,0,0,6"/>
            <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,6,0,0">
                <Button x:Name="BtnAdd"    Content="Add"    Width="60" Margin="0,0,4,0"/>
                <Button x:Name="BtnRename" Content="Rename" Width="68" Margin="0,0,4,0"/>
                <Button x:Name="BtnDelete" Content="Delete" Width="60"/>
            </StackPanel>
            <ListBox x:Name="LstPresets"/>
        </DockPanel>

        <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="PnlEditor">
                <TextBlock Text="Description" FontWeight="Bold" Margin="0,0,0,4"/>
                <TextBox x:Name="TxtDescription" Margin="0,0,0,12"/>

                <Border BorderBrush="Gray" BorderThickness="0,0,0,1" Margin="0,0,0,8" Padding="0,0,0,4">
                    <TextBlock Text="Plugged in" FontWeight="Bold"/>
                </Border>
                <Grid Margin="0,0,0,12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="180"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Row="0" Grid.Column="0" Text="When I press the power button"  VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="0" Grid.Column="1" x:Name="CbPowerAc" Margin="0,4"/>
                    <TextBlock Grid.Row="1" Grid.Column="0" Text="When I press the sleep button" VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="1" Grid.Column="1" x:Name="CbSleepAc" Margin="0,4"/>
                    <TextBlock Grid.Row="2" Grid.Column="0" Text="When I close the lid" VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="2" Grid.Column="1" x:Name="CbLidAc"   Margin="0,4"/>
                </Grid>

                <Border BorderBrush="Gray" BorderThickness="0,0,0,1" Margin="0,0,0,8" Padding="0,0,0,4">
                    <TextBlock Text="On battery" FontWeight="Bold"/>
                </Border>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="180"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Row="0" Grid.Column="0" Text="When I press the power button"  VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="0" Grid.Column="1" x:Name="CbPowerDc" Margin="0,4"/>
                    <TextBlock Grid.Row="1" Grid.Column="0" Text="When I press the sleep button" VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="1" Grid.Column="1" x:Name="CbSleepDc" Margin="0,4"/>
                    <TextBlock Grid.Row="2" Grid.Column="0" Text="When I close the lid" VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="2" Grid.Column="1" x:Name="CbLidDc"   Margin="0,4"/>
                </Grid>
            </StackPanel>
        </ScrollViewer>

        <StackPanel Grid.Row="1" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="BtnSaveApply" Content="Save and Apply" Width="120" Margin="0,0,8,0"/>
            <Button x:Name="BtnSave"      Content="Save"           Width="80"  Margin="0,0,8,0"/>
            <Button x:Name="BtnCancel"    Content="Cancel"         Width="80"/>
        </StackPanel>
    </Grid>
</Window>
'@

function Show-SettingsWindow {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$Script:SettingsXaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $ctl = @{}
    foreach ($n in 'LstPresets','BtnAdd','BtnRename','BtnDelete','TxtDescription',
                   'CbPowerAc','CbSleepAc','CbLidAc','CbPowerDc','CbSleepDc','CbLidDc',
                   'BtnSave','BtnSaveApply','BtnCancel') {
        $ctl[$n] = $window.FindName($n)
    }

    foreach ($cb in @($ctl.CbPowerAc, $ctl.CbSleepAc, $ctl.CbLidAc, $ctl.CbPowerDc, $ctl.CbSleepDc, $ctl.CbLidDc)) {
        $cb.ItemsSource = 0..3 | ForEach-Object { $Script:ACTION_NAMES[$_] }
    }

    # Create a local mutable copy
    $data = Load-Presets
    $list = New-Object System.Collections.ArrayList
    foreach ($p in $data.presets) { [void]$list.Add($p) }
    $ctl.LstPresets.ItemsSource = $list
    $ctl.LstPresets.DisplayMemberPath = 'name'
    if ($list.Count -gt 0) { $ctl.LstPresets.SelectedIndex = 0 }

    $Script:SuppressEditorUpdate = $false

    $loadEditor = {
        $p = $ctl.LstPresets.SelectedItem
        if ($null -eq $p) { return }
        $Script:SuppressEditorUpdate = $true
        $ctl.TxtDescription.Text = [string]$p.description
        $ctl.CbPowerAc.SelectedIndex = [int]$p.power.ac
        $ctl.CbSleepAc.SelectedIndex = [int]$p.sleep.ac
        $ctl.CbLidAc.SelectedIndex   = [int]$p.lid.ac
        $ctl.CbPowerDc.SelectedIndex = [int]$p.power.dc
        $ctl.CbSleepDc.SelectedIndex = [int]$p.sleep.dc
        $ctl.CbLidDc.SelectedIndex   = [int]$p.lid.dc
        $Script:SuppressEditorUpdate = $false
    }

    $commitEditor = {
        if ($Script:SuppressEditorUpdate) { return }
        $p = $ctl.LstPresets.SelectedItem
        if ($null -eq $p) { return }
        $p.description = $ctl.TxtDescription.Text
        $p.power.ac = $ctl.CbPowerAc.SelectedIndex
        $p.sleep.ac = $ctl.CbSleepAc.SelectedIndex
        $p.lid.ac   = $ctl.CbLidAc.SelectedIndex
        $p.power.dc = $ctl.CbPowerDc.SelectedIndex
        $p.sleep.dc = $ctl.CbSleepDc.SelectedIndex
        $p.lid.dc   = $ctl.CbLidDc.SelectedIndex
    }

    $ctl.LstPresets.Add_SelectionChanged({ & $loadEditor })
    $ctl.TxtDescription.Add_TextChanged({ & $commitEditor })
    foreach ($cb in @($ctl.CbPowerAc, $ctl.CbSleepAc, $ctl.CbLidAc, $ctl.CbPowerDc, $ctl.CbSleepDc, $ctl.CbLidDc)) {
        $cb.Add_SelectionChanged({ & $commitEditor })
    }

    $ctl.BtnAdd.Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Enter a preset name', 'Add', 'New Preset')
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $new = [PSCustomObject]@{
            name = $name; description = ''
            power = [PSCustomObject]@{ ac = 0; dc = 0 }
            sleep = [PSCustomObject]@{ ac = 0; dc = 0 }
            lid   = [PSCustomObject]@{ ac = 0; dc = 0 }
        }
        [void]$list.Add($new)
        $ctl.LstPresets.Items.Refresh()
        $ctl.LstPresets.SelectedItem = $new
    })
    $ctl.BtnRename.Add_Click({
        $p = $ctl.LstPresets.SelectedItem; if ($null -eq $p) { return }
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('New name', 'Rename', $p.name)
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $p.name = $name
        $ctl.LstPresets.Items.Refresh()
    })
    $ctl.BtnDelete.Add_Click({
        $p = $ctl.LstPresets.SelectedItem; if ($null -eq $p) { return }
        if ($list.Count -le 1) {
            [System.Windows.MessageBox]::Show('At least one preset is required.', 'PowerControl') | Out-Null
            return
        }
        $r = [System.Windows.MessageBox]::Show("Delete preset '$($p.name)'?", 'Confirm', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        $list.Remove($p)
        $ctl.LstPresets.Items.Refresh()
        if ($list.Count -gt 0) { $ctl.LstPresets.SelectedIndex = 0 }
    })

    Add-Type -AssemblyName Microsoft.VisualBasic

    $Script:DialogResult = $null

    $ctl.BtnSave.Add_Click({
        & $commitEditor
        $data.presets = $list.ToArray()
        Save-Presets $data
        $Script:DialogResult = 'save'
        $window.Close()
    })
    $ctl.BtnSaveApply.Add_Click({
        & $commitEditor
        $data.presets = $list.ToArray()
        Save-Presets $data
        $Script:DialogResult = 'saveApply'
        $Script:ApplyPreset = $ctl.LstPresets.SelectedItem
        $window.Close()
    })
    $ctl.BtnCancel.Add_Click({
        $Script:DialogResult = 'cancel'
        $window.Close()
    })

    & $loadEditor
    [void]$window.ShowDialog()

    return @{
        Result = $Script:DialogResult
        ApplyPreset = $Script:ApplyPreset
    }
}

# ----- Tray UI -----
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$Script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$Script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$Script:NotifyIcon.Text = 'PowerControl'

$Script:AppContext = New-Object System.Windows.Forms.ApplicationContext

function Show-BalloonTip($title, $text) {
    $Script:NotifyIcon.BalloonTipTitle = $title
    $Script:NotifyIcon.BalloonTipText  = $text
    $Script:NotifyIcon.ShowBalloonTip(2500)
}

function Build-TrayMenu {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $data = Load-Presets
    $state = Load-State
    $current = $state.lastPreset

    $header = New-Object System.Windows.Forms.ToolStripMenuItem
    $header.Text = if ($current) { "Current: $current" } else { 'Current: (none)' }
    $header.Enabled = $false
    [void]$menu.Items.Add($header)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    foreach ($p in $data.presets) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem
        $mi.Text = $p.name
        $mi.Checked = ($p.name -eq $current)
        if ($p.description) { $mi.ToolTipText = $p.description }
        $presetRef = $p
        $mi.Add_Click({
            try {
                Apply-Preset $presetRef
                Show-BalloonTip 'PowerControl' "Applied preset '$($presetRef.name)'."
                Refresh-TrayMenu
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Failed to apply preset:`n$_", 'PowerControl', 'OK', 'Error') | Out-Null
            }
        }.GetNewClosure())
        [void]$menu.Items.Add($mi)
    }

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miSettings = New-Object System.Windows.Forms.ToolStripMenuItem
    $miSettings.Text = 'Preset settings...'
    $miSettings.Add_Click({
        $r = Show-SettingsWindow
        if ($r.Result -eq 'saveApply' -and $r.ApplyPreset) {
            try {
                Apply-Preset $r.ApplyPreset
                Show-BalloonTip 'PowerControl' "Applied preset '$($r.ApplyPreset.name)'."
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Failed to apply preset:`n$_", 'PowerControl', 'OK', 'Error') | Out-Null
            }
        }
        Refresh-TrayMenu
    })
    [void]$menu.Items.Add($miSettings)

    $miAuto = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAuto.Text = 'Register for startup'
    $miAuto.Checked = Test-AutoStart
    $miAuto.Add_Click({
        try {
            if (Test-AutoStart) { Disable-AutoStart }
            else { Enable-AutoStart }
            Refresh-TrayMenu
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to update startup setting:`n$_", 'PowerControl', 'OK', 'Error') | Out-Null
        }
    })
    [void]$menu.Items.Add($miAuto)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miExit = New-Object System.Windows.Forms.ToolStripMenuItem
    $miExit.Text = 'Exit'
    $miExit.Add_Click({
        $Script:NotifyIcon.Visible = $false
        $Script:NotifyIcon.Dispose()
        [System.Windows.Forms.Application]::Exit()
    })
    [void]$menu.Items.Add($miExit)

    return $menu
}

function Refresh-TrayMenu {
    $old = $Script:NotifyIcon.ContextMenuStrip
    $Script:NotifyIcon.ContextMenuStrip = Build-TrayMenu
    if ($old) { $old.Dispose() }
}

Refresh-TrayMenu
$Script:NotifyIcon.Visible = $true

# Open the menu on left-click too (right-click is handled by ContextMenuStrip)
$Script:NotifyIcon.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $mi = [System.Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [System.Reflection.BindingFlags]'NonPublic,Instance')
        if ($mi) { $mi.Invoke($Script:NotifyIcon, $null) }
    }
})

# Startup notification
Show-BalloonTip 'PowerControl' 'Running in the task tray. Right-click for the menu.'

# ----- Message loop -----
[System.Windows.Forms.Application]::Run($Script:AppContext)
