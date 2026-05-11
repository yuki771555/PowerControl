#Requires -Version 5.1
<#
PowerControl.ps1
タスクトレイ常駐型「電源ボタン / スリープボタン / カバー」動作切替アプリ
#>

# ----- 自己昇格 (管理者権限) -----
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    exit
}

# ----- アセンブリ -----
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ----- 定数 -----
$Script:SUB_BUTTONS = '4f971e89-eebd-4455-a8de-9e59040e7347'
$Script:GUID_POWER  = '7648efa3-dd9c-4e3e-b566-50f929386280'  # 電源ボタン
$Script:GUID_SLEEP  = '96996bc0-ad50-47ec-923b-6f41874dd9eb'  # スリープボタン
$Script:GUID_LID    = '5ca83367-6e45-459f-a27b-476b1d01c936'  # カバーを閉じる

$Script:ACTION_NAMES = @{
    0 = '何もしない'
    1 = 'スリープ'
    2 = '休止状態'
    3 = 'シャットダウン'
}

$Script:ScriptDir   = Split-Path -Parent $PSCommandPath
$Script:PresetsPath = Join-Path $Script:ScriptDir 'presets.json'
$Script:StatePath   = Join-Path $Script:ScriptDir 'state.json'
$Script:TaskName    = 'PowerControlAutoStart'

# ----- プリセット読み書き -----
function Get-DefaultPresets {
    [PSCustomObject]@{
        presets = @(
            [PSCustomObject]@{
                name        = '通常モード'
                description = '電源/スリープボタンでスリープ、カバーは何もしない'
                power = [PSCustomObject]@{ ac = 1; dc = 1 }
                sleep = [PSCustomObject]@{ ac = 1; dc = 1 }
                lid   = [PSCustomObject]@{ ac = 0; dc = 0 }
            },
            [PSCustomObject]@{
                name        = '作業中モード'
                description = '全部「何もしない」（プレゼン・長時間作業向け）'
                power = [PSCustomObject]@{ ac = 0; dc = 0 }
                sleep = [PSCustomObject]@{ ac = 0; dc = 0 }
                lid   = [PSCustomObject]@{ ac = 0; dc = 0 }
            },
            [PSCustomObject]@{
                name        = '省電力モード'
                description = '全部スリープ（バッテリー節約）'
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
        [System.Windows.Forms.MessageBox]::Show("presets.json の読み込みに失敗しました。既定値に戻します。`n$_", 'PowerControl', 'OK', 'Warning') | Out-Null
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

# ----- powercfg ロジック -----
function Get-ActiveSchemeGuid {
    $out = & powercfg.exe /getactivescheme 2>&1
    $match = [regex]::Match([string]::Join("`n", $out), '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    if ($match.Success) { return $match.Groups[1].Value }
    throw 'アクティブな電源プランの GUID を取得できませんでした。'
}

function Apply-Preset($preset) {
    $scheme = Get-ActiveSchemeGuid
    $pairs = @(
        @{ guid = $Script:GUID_POWER; ac = [int]$preset.power.ac; dc = [int]$preset.power.dc },
        @{ guid = $Script:GUID_SLEEP; ac = [int]$preset.sleep.ac; dc = [int]$preset.sleep.dc },
        @{ guid = $Script:GUID_LID;   ac = [int]$preset.lid.ac;   dc = [int]$preset.lid.dc }
    )
    foreach ($p in $pairs) {
        & powercfg.exe /setacvalueindex $scheme $Script:SUB_BUTTONS $p.guid $p.ac | Out-Null
        & powercfg.exe /setdcvalueindex $scheme $Script:SUB_BUTTONS $p.guid $p.dc | Out-Null
    }
    & powercfg.exe /setactive $scheme | Out-Null

    $state = Load-State
    $state | Add-Member -NotePropertyName lastPreset -NotePropertyValue $preset.name -Force
    Save-State $state
}

# ----- タスクスケジューラ登録 -----
function Test-AutoStart {
    try {
        $t = Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction Stop
        return $null -ne $t
    } catch { return $false }
}

function Enable-AutoStart {
    $batPath = Join-Path $Script:ScriptDir 'PowerControl.bat'
    $action = New-ScheduledTaskAction -Execute $batPath
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $Script:TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Disable-AutoStart {
    Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

# ----- WPF 設定ウィンドウ -----
$Script:SettingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PowerControl 設定" Width="720" Height="560" WindowStartupLocation="CenterScreen">
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
            <TextBlock DockPanel.Dock="Top" Text="プリセット" FontWeight="Bold" Margin="0,0,0,6"/>
            <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,6,0,0">
                <Button x:Name="BtnAdd"    Content="追加"    Width="60" Margin="0,0,4,0"/>
                <Button x:Name="BtnRename" Content="名前変更" Width="68" Margin="0,0,4,0"/>
                <Button x:Name="BtnDelete" Content="削除"    Width="60"/>
            </StackPanel>
            <ListBox x:Name="LstPresets"/>
        </DockPanel>

        <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="PnlEditor">
                <TextBlock Text="説明" FontWeight="Bold" Margin="0,0,0,4"/>
                <TextBox x:Name="TxtDescription" Margin="0,0,0,12"/>

                <Border BorderBrush="Gray" BorderThickness="0,0,0,1" Margin="0,0,0,8" Padding="0,0,0,4">
                    <TextBlock Text="電源に接続" FontWeight="Bold"/>
                </Border>
                <Grid Margin="0,0,0,12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="180"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Row="0" Grid.Column="0" Text="電源ボタンを押すと、PC が"  VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="0" Grid.Column="1" x:Name="CbPowerAc" Margin="0,4"/>
                    <TextBlock Grid.Row="1" Grid.Column="0" Text="スリープ ボタンを押すと、PC が" VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="1" Grid.Column="1" x:Name="CbSleepAc" Margin="0,4"/>
                    <TextBlock Grid.Row="2" Grid.Column="0" Text="カバーを閉じると、PC が" VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="2" Grid.Column="1" x:Name="CbLidAc"   Margin="0,4"/>
                </Grid>

                <Border BorderBrush="Gray" BorderThickness="0,0,0,1" Margin="0,0,0,8" Padding="0,0,0,4">
                    <TextBlock Text="バッテリー駆動" FontWeight="Bold"/>
                </Border>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="180"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Row="0" Grid.Column="0" Text="電源ボタンを押すと、PC が"  VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="0" Grid.Column="1" x:Name="CbPowerDc" Margin="0,4"/>
                    <TextBlock Grid.Row="1" Grid.Column="0" Text="スリープ ボタンを押すと、PC が" VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="1" Grid.Column="1" x:Name="CbSleepDc" Margin="0,4"/>
                    <TextBlock Grid.Row="2" Grid.Column="0" Text="カバーを閉じると、PC が" VerticalAlignment="Center" Margin="0,4"/>
                    <ComboBox Grid.Row="2" Grid.Column="1" x:Name="CbLidDc"   Margin="0,4"/>
                </Grid>
            </StackPanel>
        </ScrollViewer>

        <StackPanel Grid.Row="1" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="BtnSaveApply" Content="保存して適用" Width="120" Margin="0,0,8,0"/>
            <Button x:Name="BtnSave"      Content="保存"        Width="80"  Margin="0,0,8,0"/>
            <Button x:Name="BtnCancel"    Content="キャンセル"  Width="80"/>
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

    # ローカル可変コピーを作る
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
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('プリセット名を入力してください', '追加', '新しいプリセット')
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
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('新しい名前', '名前変更', $p.name)
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $p.name = $name
        $ctl.LstPresets.Items.Refresh()
    })
    $ctl.BtnDelete.Add_Click({
        $p = $ctl.LstPresets.SelectedItem; if ($null -eq $p) { return }
        if ($list.Count -le 1) {
            [System.Windows.MessageBox]::Show('最低 1 つのプリセットが必要です。', 'PowerControl') | Out-Null
            return
        }
        $r = [System.Windows.MessageBox]::Show("プリセット「$($p.name)」を削除しますか？", '確認', 'YesNo', 'Question')
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

# ----- トレイ UI -----
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
    $header.Text = if ($current) { "現在: $current" } else { '現在: (未適用)' }
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
                Show-BalloonTip 'PowerControl' "プリセット「$($presetRef.name)」を適用しました。"
                Refresh-TrayMenu
            } catch {
                [System.Windows.Forms.MessageBox]::Show("適用に失敗しました:`n$_", 'PowerControl', 'OK', 'Error') | Out-Null
            }
        }.GetNewClosure())
        [void]$menu.Items.Add($mi)
    }

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miSettings = New-Object System.Windows.Forms.ToolStripMenuItem
    $miSettings.Text = 'プリセット設定...'
    $miSettings.Add_Click({
        $r = Show-SettingsWindow
        if ($r.Result -eq 'saveApply' -and $r.ApplyPreset) {
            try {
                Apply-Preset $r.ApplyPreset
                Show-BalloonTip 'PowerControl' "プリセット「$($r.ApplyPreset.name)」を適用しました。"
            } catch {
                [System.Windows.Forms.MessageBox]::Show("適用に失敗しました:`n$_", 'PowerControl', 'OK', 'Error') | Out-Null
            }
        }
        Refresh-TrayMenu
    })
    [void]$menu.Items.Add($miSettings)

    $miAuto = New-Object System.Windows.Forms.ToolStripMenuItem
    $miAuto.Text = 'スタートアップに登録'
    $miAuto.Checked = Test-AutoStart
    $miAuto.Add_Click({
        try {
            if (Test-AutoStart) { Disable-AutoStart }
            else { Enable-AutoStart }
            Refresh-TrayMenu
        } catch {
            [System.Windows.Forms.MessageBox]::Show("スタートアップ設定に失敗しました:`n$_", 'PowerControl', 'OK', 'Error') | Out-Null
        }
    })
    [void]$menu.Items.Add($miAuto)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $miExit = New-Object System.Windows.Forms.ToolStripMenuItem
    $miExit.Text = '終了'
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

# 左クリックでもメニューを開けるようにする (右クリックは ContextMenuStrip の標準動作)
$Script:NotifyIcon.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $mi = [System.Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [System.Reflection.BindingFlags]'NonPublic,Instance')
        if ($mi) { $mi.Invoke($Script:NotifyIcon, $null) }
    }
})

# 起動完了通知
Show-BalloonTip 'PowerControl' 'タスクトレイで動作中です（右クリックでメニュー）。'

# ----- メッセージループ -----
[System.Windows.Forms.Application]::Run($Script:AppContext)
