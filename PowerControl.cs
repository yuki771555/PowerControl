using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace PowerControl
{
    internal static class Program
    {
        private const string SubButtons = "4f971e89-eebd-4455-a8de-9e59040e7347";
        private const string GuidPower = "7648efa3-dd9c-4e3e-b566-50f929386280";
        private const string GuidSleep = "96996bc0-ad50-47ec-923b-6f41874dd9eb";
        private const string GuidLid = "5ca83367-6e45-459f-a27b-476b1d01c936";
        private const string TaskName = "PowerControlAutoStart";

        private static string AppDir;
        private static string PresetsPath;
        private static string StatePath;
        private static NotifyIcon NotifyIcon;
        internal static string CurrentLanguage = "en";

        [STAThread]
        private static void Main()
        {
            try
            {
                MainCore();
            }
            catch (Exception ex)
            {
                MessageBox.Show("PowerControl failed to start:\n" + ex, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static void MainCore()
        {
            AppDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            PresetsPath = Path.Combine(AppDir, "presets.json");
            StatePath = Path.Combine(AppDir, "state.json");
            CurrentLanguage = NormalizeLanguage(LoadState().language);

            if (!IsAdministrator())
            {
                RelaunchAsAdministrator();
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            NotifyIcon = new NotifyIcon
            {
                Icon = SystemIcons.Application,
                Text = "PowerControl",
                Visible = true
            };
            RefreshTrayMenu();
            NotifyIcon.MouseUp += NotifyIconMouseUp;
            ShowBalloonTip("PowerControl", L.T("StartupBalloon"));

            Application.Run(new ApplicationContext());

            NotifyIcon.Visible = false;
            NotifyIcon.Dispose();
        }

        private static bool IsAdministrator()
        {
            WindowsIdentity identity = WindowsIdentity.GetCurrent();
            WindowsPrincipal principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        private static void RelaunchAsAdministrator()
        {
            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = Application.ExecutablePath,
                UseShellExecute = true,
                Verb = "runas"
            };
            Process.Start(startInfo);
        }

        private static PresetConfig GetDefaultPresets()
        {
            return new PresetConfig
            {
                presets = new List<Preset>
                {
                    new Preset
                    {
                        key = "normal",
                        name = L.T("NormalMode"),
                        description = L.T("NormalModeDescription"),
                        power = new ActionPair { ac = 1, dc = 1 },
                        sleep = new ActionPair { ac = 1, dc = 1 },
                        lid = new ActionPair { ac = 1, dc = 1 }
                    },
                    new Preset
                    {
                        key = "work",
                        name = L.T("WorkMode"),
                        description = L.T("WorkModeDescription"),
                        power = new ActionPair { ac = 0, dc = 0 },
                        sleep = new ActionPair { ac = 0, dc = 0 },
                        lid = new ActionPair { ac = 0, dc = 0 }
                    },
                    new Preset
                    {
                        key = "powerSaving",
                        name = L.T("PowerSavingMode"),
                        description = L.T("PowerSavingModeDescription"),
                        power = new ActionPair { ac = 1, dc = 1 },
                        sleep = new ActionPair { ac = 1, dc = 1 },
                        lid = new ActionPair { ac = 1, dc = 1 }
                    }
                }
            };
        }

        private static PresetConfig LoadPresets()
        {
            if (!File.Exists(PresetsPath))
            {
                PresetConfig defaults = GetDefaultPresets();
                SaveJson(PresetsPath, defaults);
                return defaults;
            }

            try
            {
                return LoadJson<PresetConfig>(PresetsPath);
            }
            catch (Exception ex)
            {
                MessageBox.Show(L.T("FailedLoadPresets") + "\n" + ex.Message, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                PresetConfig defaults = GetDefaultPresets();
                SaveJson(PresetsPath, defaults);
                return defaults;
            }
        }

        private static State LoadState()
        {
            if (!File.Exists(StatePath))
            {
                return new State();
            }

            try
            {
                return LoadJson<State>(StatePath);
            }
            catch
            {
                return new State();
            }
        }

        private static void SaveState(State state)
        {
            state.language = NormalizeLanguage(state.language);
            SaveJson(StatePath, state);
        }

        private static string NormalizeLanguage(string language)
        {
            return string.Equals(language, "ja", StringComparison.OrdinalIgnoreCase) ? "ja" : "en";
        }

        internal static string PresetDisplayName(Preset preset)
        {
            string key = GetPresetKey(preset);
            return key == null ? preset.name : L.T(key + "Name");
        }

        internal static string PresetDisplayDescription(Preset preset)
        {
            string key = GetPresetKey(preset);
            return key == null ? preset.description : L.T(key + "Description");
        }

        private static string GetPresetKey(Preset preset)
        {
            if (preset == null)
            {
                return null;
            }
            if (!string.IsNullOrWhiteSpace(preset.key))
            {
                return preset.key;
            }

            if (preset.name == "Normal Mode" || preset.name == "通常モード")
            {
                return "normal";
            }
            if (preset.name == "Work Mode" || preset.name == "作業中モード")
            {
                return "work";
            }
            if (preset.name == "Power Saving Mode" || preset.name == "省電力モード")
            {
                return "powerSaving";
            }

            return null;
        }

        private static T LoadJson<T>(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            {
                DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(T));
                return (T)serializer.ReadObject(stream);
            }
        }

        private static void SaveJson<T>(string path, T value)
        {
            DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(T));
            using (MemoryStream stream = new MemoryStream())
            {
                serializer.WriteObject(stream, value);
                string json = Encoding.UTF8.GetString(stream.ToArray());
                File.WriteAllText(path, PrettyJson(json), Encoding.UTF8);
            }
        }

        private static string PrettyJson(string json)
        {
            StringBuilder output = new StringBuilder();
            int indent = 0;
            bool inString = false;

            for (int i = 0; i < json.Length; i++)
            {
                char c = json[i];
                if (c == '"' && (i == 0 || json[i - 1] != '\\'))
                {
                    inString = !inString;
                }

                if (!inString && (c == '{' || c == '['))
                {
                    output.Append(c).AppendLine();
                    indent++;
                    output.Append(new string(' ', indent * 2));
                }
                else if (!inString && (c == '}' || c == ']'))
                {
                    output.AppendLine();
                    indent--;
                    output.Append(new string(' ', indent * 2)).Append(c);
                }
                else if (!inString && c == ',')
                {
                    output.Append(c).AppendLine();
                    output.Append(new string(' ', indent * 2));
                }
                else if (!inString && c == ':')
                {
                    output.Append(": ");
                }
                else
                {
                    output.Append(c);
                }
            }

            return output.ToString();
        }

        private static string GetActiveSchemeGuid()
        {
            string output = RunProcess("powercfg.exe", "/getactivescheme", true);
            Match match = Regex.Match(output, "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})");
            if (match.Success)
            {
                return match.Groups[1].Value;
            }

            throw new InvalidOperationException(L.T("CouldNotGetScheme"));
        }

        private static void ApplyPreset(Preset preset)
        {
            ValidatePreset(preset);
            string scheme = GetActiveSchemeGuid();
            SetPowerValue(scheme, GuidPower, preset.power.ac, preset.power.dc);
            SetPowerValue(scheme, GuidSleep, preset.sleep.ac, preset.sleep.dc);
            SetPowerValue(scheme, GuidLid, preset.lid.ac, preset.lid.dc);
            RunProcess("powercfg.exe", "/setactive " + scheme, false);
            State state = LoadState();
            state.lastPreset = preset.name;
            state.language = CurrentLanguage;
            SaveState(state);
        }

        private static void ValidatePreset(Preset preset)
        {
            ValidateAction(preset.power.ac);
            ValidateAction(preset.power.dc);
            ValidateAction(preset.sleep.ac);
            ValidateAction(preset.sleep.dc);
            ValidateAction(preset.lid.ac);
            ValidateAction(preset.lid.dc);
        }

        private static void ValidateAction(int value)
        {
            if (value < 0 || value > 3)
            {
                throw new InvalidOperationException(L.T("InvalidActionValue"));
            }
        }

        private static void SetPowerValue(string scheme, string guid, int ac, int dc)
        {
            RunProcess("powercfg.exe", "/setacvalueindex " + scheme + " " + SubButtons + " " + guid + " " + ac, false);
            RunProcess("powercfg.exe", "/setdcvalueindex " + scheme + " " + SubButtons + " " + guid + " " + dc, false);
        }

        private static bool TestAutoStart()
        {
            return RunProcessExitCode("schtasks.exe", "/Query /TN \"" + TaskName + "\"") == 0;
        }

        private static void EnableAutoStart()
        {
            string exePath = Application.ExecutablePath;
            string args = "/Create /TN \"" + TaskName + "\" /SC ONLOGON /TR \"\\\"" + exePath + "\\\"\" /RL HIGHEST /F";
            RunProcess("schtasks.exe", args, true);
        }

        private static void DisableAutoStart()
        {
            RunProcess("schtasks.exe", "/Delete /TN \"" + TaskName + "\" /F", true);
        }

        private static string RunProcess(string fileName, string arguments, bool captureOutput)
        {
            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = captureOutput,
                RedirectStandardError = captureOutput
            };

            using (Process process = Process.Start(startInfo))
            {
                string output = captureOutput ? process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd() : string.Empty;
                process.WaitForExit();
                if (process.ExitCode != 0)
                {
                    throw new InvalidOperationException(string.Format(L.T("ProcessFailed"), fileName, process.ExitCode) + "\n" + output);
                }

                return output;
            }
        }

        private static int RunProcessExitCode(string fileName, string arguments)
        {
            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }

        private static void RefreshTrayMenu()
        {
            ContextMenuStrip oldMenu = NotifyIcon.ContextMenuStrip;
            NotifyIcon.ContextMenuStrip = BuildTrayMenu();
            if (oldMenu != null)
            {
                oldMenu.Dispose();
            }
        }

        private static ContextMenuStrip BuildTrayMenu()
        {
            ContextMenuStrip menu = new ContextMenuStrip();
            PresetConfig data = LoadPresets();
            State state = LoadState();

            ToolStripMenuItem header = new ToolStripMenuItem(state.lastPreset == null ? L.T("CurrentNone") : L.T("CurrentPrefix") + PresetDisplayName(new Preset { name = state.lastPreset }))
            {
                Enabled = false
            };
            menu.Items.Add(header);
            menu.Items.Add(new ToolStripSeparator());

            foreach (Preset preset in data.presets)
            {
                Preset presetRef = preset;
                ToolStripMenuItem item = new ToolStripMenuItem(PresetDisplayName(preset))
                {
                    Checked = preset.name == state.lastPreset,
                    ToolTipText = PresetDisplayDescription(preset)
                };
                item.Click += delegate
                {
                    try
                    {
                        ApplyPreset(presetRef);
                        ShowBalloonTip("PowerControl", string.Format(L.T("AppliedPreset"), PresetDisplayName(presetRef)));
                        RefreshTrayMenu();
                    }
                    catch (Exception ex)
                    {
                        MessageBox.Show(L.T("FailedApplyPreset") + "\n" + ex.Message, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                };
                menu.Items.Add(item);
            }

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem settings = new ToolStripMenuItem(L.T("PresetSettings"));
            settings.Click += delegate
            {
                using (SettingsForm form = new SettingsForm(LoadPresets()))
                {
                    DialogResult result = form.ShowDialog();
                    if (result == DialogResult.OK || result == DialogResult.Yes)
                    {
                        SaveJson(PresetsPath, form.Config);
                    }

                    if (result == DialogResult.Yes && form.ApplyPreset != null)
                    {
                        try
                        {
                            ApplyPreset(form.ApplyPreset);
                            ShowBalloonTip("PowerControl", string.Format(L.T("AppliedPreset"), PresetDisplayName(form.ApplyPreset)));
                        }
                        catch (Exception ex)
                        {
                            MessageBox.Show(L.T("FailedApplyPreset") + "\n" + ex.Message, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        }
                    }
                }
                RefreshTrayMenu();
            };
            menu.Items.Add(settings);

            ToolStripMenuItem autoStart = new ToolStripMenuItem(L.T("RegisterStartup"))
            {
                Checked = TestAutoStart()
            };
            autoStart.Click += delegate
            {
                try
                {
                    if (TestAutoStart())
                    {
                        DisableAutoStart();
                    }
                    else
                    {
                        EnableAutoStart();
                    }
                    RefreshTrayMenu();
                }
                catch (Exception ex)
                {
                    MessageBox.Show(L.T("FailedStartup") + "\n" + ex.Message, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            };
            menu.Items.Add(autoStart);

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem language = new ToolStripMenuItem(L.T("Language"));
            ToolStripMenuItem english = new ToolStripMenuItem("English") { Checked = CurrentLanguage == "en" };
            ToolStripMenuItem japanese = new ToolStripMenuItem("日本語") { Checked = CurrentLanguage == "ja" };
            english.Click += delegate { SetLanguage("en"); };
            japanese.Click += delegate { SetLanguage("ja"); };
            language.DropDownItems.Add(english);
            language.DropDownItems.Add(japanese);
            menu.Items.Add(language);

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem exit = new ToolStripMenuItem(L.T("Exit"));
            exit.Click += delegate
            {
                NotifyIcon.Visible = false;
                Application.Exit();
            };
            menu.Items.Add(exit);

            return menu;
        }

        private static void NotifyIconMouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                System.Reflection.MethodInfo method = typeof(NotifyIcon).GetMethod("ShowContextMenu", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
                if (method != null)
                {
                    method.Invoke(NotifyIcon, null);
                }
            }
        }

        private static void SetLanguage(string language)
        {
            CurrentLanguage = NormalizeLanguage(language);
            State state = LoadState();
            state.language = CurrentLanguage;
            SaveState(state);
            RefreshTrayMenu();
            ShowBalloonTip("PowerControl", L.T("LanguageChanged"));
        }

        private static void ShowBalloonTip(string title, string text)
        {
            NotifyIcon.BalloonTipTitle = title;
            NotifyIcon.BalloonTipText = text;
            NotifyIcon.ShowBalloonTip(2500);
        }
    }

    internal sealed class SettingsForm : Form
    {
        private readonly ListBox presetsList = new ListBox();
        private readonly TextBox descriptionText = new TextBox();
        private readonly ComboBox powerAc = new ComboBox();
        private readonly ComboBox sleepAc = new ComboBox();
        private readonly ComboBox lidAc = new ComboBox();
        private readonly ComboBox powerDc = new ComboBox();
        private readonly ComboBox sleepDc = new ComboBox();
        private readonly ComboBox lidDc = new ComboBox();
        private bool suppressUpdate;

        public PresetConfig Config { get; private set; }
        public Preset ApplyPreset { get; private set; }

        public SettingsForm(PresetConfig config)
        {
            this.Config = config;
            InitializeComponent();
            LoadPresetsList();
        }

        private void InitializeComponent()
        {
            Text = L.T("SettingsTitle");
            StartPosition = FormStartPosition.CenterScreen;
            Width = 720;
            Height = 560;

            TableLayoutPanel root = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 2,
                RowCount = 2,
                Padding = new Padding(12)
            };
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 220));
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
            Controls.Add(root);

            Panel left = new Panel { Dock = DockStyle.Fill, Padding = new Padding(0, 0, 8, 0) };
            Label presetsLabel = new Label { Text = L.T("Presets"), Dock = DockStyle.Top, Font = new Font(Font, FontStyle.Bold), Height = 24 };
            FlowLayoutPanel presetButtons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 34 };
            Button add = new Button { Text = L.T("Add"), Width = 60 };
            Button rename = new Button { Text = L.T("Rename"), Width = 68 };
            Button delete = new Button { Text = L.T("Delete"), Width = 60 };
            presetButtons.Controls.Add(add);
            presetButtons.Controls.Add(rename);
            presetButtons.Controls.Add(delete);
            presetsList.Dock = DockStyle.Fill;
            left.Controls.Add(presetsList);
            left.Controls.Add(presetButtons);
            left.Controls.Add(presetsLabel);
            root.Controls.Add(left, 0, 0);

            Panel editor = new Panel { Dock = DockStyle.Fill, AutoScroll = true };
            root.Controls.Add(editor, 1, 0);

            TableLayoutPanel fields = new TableLayoutPanel
            {
                Dock = DockStyle.Top,
                ColumnCount = 2,
                AutoSize = true
            };
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180));
            editor.Controls.Add(fields);

            AddFullRow(fields, L.T("Description"), true);
            descriptionText.Dock = DockStyle.Fill;
            fields.Controls.Add(descriptionText, 0, fields.RowCount - 1);
            fields.SetColumnSpan(descriptionText, 2);

            AddFullRow(fields, L.T("PluggedIn"), true);
            AddActionRow(fields, L.T("PowerButtonLabel"), powerAc);
            AddActionRow(fields, L.T("SleepButtonLabel"), sleepAc);
            AddActionRow(fields, L.T("LidLabel"), lidAc);

            AddFullRow(fields, L.T("OnBattery"), true);
            AddActionRow(fields, L.T("PowerButtonLabel"), powerDc);
            AddActionRow(fields, L.T("SleepButtonLabel"), sleepDc);
            AddActionRow(fields, L.T("LidLabel"), lidDc);

            FlowLayoutPanel bottom = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.RightToLeft,
                Dock = DockStyle.Fill
            };
            Button cancel = new Button { Text = L.T("Cancel"), Width = 80 };
            Button save = new Button { Text = L.T("Save"), Width = 80 };
            Button saveApply = new Button { Text = L.T("SaveApply"), Width = 120 };
            bottom.Controls.Add(cancel);
            bottom.Controls.Add(save);
            bottom.Controls.Add(saveApply);
            root.Controls.Add(bottom, 0, 1);
            root.SetColumnSpan(bottom, 2);

            foreach (ComboBox combo in new[] { powerAc, sleepAc, lidAc, powerDc, sleepDc, lidDc })
            {
                combo.DropDownStyle = ComboBoxStyle.DropDownList;
                for (int i = 0; i <= 3; i++)
                {
                    combo.Items.Add(L.ActionName(i));
                }
                combo.SelectedIndexChanged += delegate { CommitEditor(); };
            }

            presetsList.SelectedIndexChanged += delegate { LoadEditor(); };
            descriptionText.TextChanged += delegate { CommitEditor(); };
            add.Click += delegate { AddPreset(); };
            rename.Click += delegate { RenamePreset(); };
            delete.Click += delegate { DeletePreset(); };
            cancel.Click += delegate { DialogResult = DialogResult.Cancel; Close(); };
            save.Click += delegate { CommitEditor(); DialogResult = DialogResult.OK; Close(); };
            saveApply.Click += delegate { CommitEditor(); ApplyPreset = presetsList.SelectedItem as Preset; DialogResult = DialogResult.Yes; Close(); };
        }

        private static void AddFullRow(TableLayoutPanel table, string text, bool bold)
        {
            table.RowCount++;
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
            Label label = new Label
            {
                Text = text,
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.BottomLeft,
                Font = bold ? new Font(SystemFonts.DefaultFont, FontStyle.Bold) : SystemFonts.DefaultFont
            };
            table.Controls.Add(label, 0, table.RowCount - 1);
            table.SetColumnSpan(label, 2);
        }

        private static void AddActionRow(TableLayoutPanel table, string labelText, ComboBox combo)
        {
            table.RowCount++;
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            Label label = new Label { Text = labelText, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft };
            combo.Dock = DockStyle.Fill;
            table.Controls.Add(label, 0, table.RowCount - 1);
            table.Controls.Add(combo, 1, table.RowCount - 1);
        }

        private void LoadPresetsList()
        {
            presetsList.DataSource = null;
            presetsList.DataSource = Config.presets;
            presetsList.DisplayMember = "displayName";
            if (Config.presets.Count > 0)
            {
                presetsList.SelectedIndex = 0;
            }
        }

        private void LoadEditor()
        {
            Preset preset = presetsList.SelectedItem as Preset;
            if (preset == null)
            {
                return;
            }

            suppressUpdate = true;
            descriptionText.Text = preset.description ?? string.Empty;
            powerAc.SelectedIndex = preset.power.ac;
            sleepAc.SelectedIndex = preset.sleep.ac;
            lidAc.SelectedIndex = preset.lid.ac;
            powerDc.SelectedIndex = preset.power.dc;
            sleepDc.SelectedIndex = preset.sleep.dc;
            lidDc.SelectedIndex = preset.lid.dc;
            suppressUpdate = false;
        }

        private void CommitEditor()
        {
            if (suppressUpdate)
            {
                return;
            }

            Preset preset = presetsList.SelectedItem as Preset;
            if (preset == null)
            {
                return;
            }

            preset.description = descriptionText.Text;
            preset.power.ac = Math.Max(0, powerAc.SelectedIndex);
            preset.sleep.ac = Math.Max(0, sleepAc.SelectedIndex);
            preset.lid.ac = Math.Max(0, lidAc.SelectedIndex);
            preset.power.dc = Math.Max(0, powerDc.SelectedIndex);
            preset.sleep.dc = Math.Max(0, sleepDc.SelectedIndex);
            preset.lid.dc = Math.Max(0, lidDc.SelectedIndex);
        }

        private void AddPreset()
        {
            string name = Prompt.Show(L.T("EnterPresetName"), L.T("Add"), L.T("NewPreset"));
            if (string.IsNullOrWhiteSpace(name))
            {
                return;
            }

            Preset preset = new Preset
            {
                name = name,
                description = string.Empty,
                power = new ActionPair(),
                sleep = new ActionPair(),
                lid = new ActionPair()
            };
            Config.presets.Add(preset);
            LoadPresetsList();
            presetsList.SelectedItem = preset;
        }

        private void RenamePreset()
        {
            Preset preset = presetsList.SelectedItem as Preset;
            if (preset == null)
            {
                return;
            }

            string name = Prompt.Show(L.T("NewName"), L.T("Rename"), preset.name);
            if (string.IsNullOrWhiteSpace(name))
            {
                return;
            }

            preset.name = name;
            LoadPresetsList();
            presetsList.SelectedItem = preset;
        }

        private void DeletePreset()
        {
            Preset preset = presetsList.SelectedItem as Preset;
            if (preset == null)
            {
                return;
            }

            if (Config.presets.Count <= 1)
            {
                MessageBox.Show(L.T("AtLeastOnePreset"), "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (MessageBox.Show(string.Format(L.T("DeletePreset"), Program.PresetDisplayName(preset)), L.T("Confirm"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
            {
                return;
            }

            Config.presets.Remove(preset);
            LoadPresetsList();
        }
    }

    internal static class Prompt
    {
        public static string Show(string text, string caption, string defaultValue)
        {
            using (Form form = new Form())
            using (Label label = new Label())
            using (TextBox input = new TextBox())
            using (Button ok = new Button())
            using (Button cancel = new Button())
            {
                form.Text = caption;
                form.StartPosition = FormStartPosition.CenterParent;
                form.Width = 420;
                form.Height = 150;
                form.FormBorderStyle = FormBorderStyle.FixedDialog;
                form.MaximizeBox = false;
                form.MinimizeBox = false;

                label.Text = text;
                label.Left = 12;
                label.Top = 12;
                label.Width = 380;

                input.Text = defaultValue;
                input.Left = 12;
                input.Top = 40;
                input.Width = 380;

                ok.Text = L.T("OK");
                ok.Left = 232;
                ok.Top = 78;
                ok.Width = 75;
                ok.DialogResult = DialogResult.OK;

                cancel.Text = L.T("Cancel");
                cancel.Left = 317;
                cancel.Top = 78;
                cancel.Width = 75;
                cancel.DialogResult = DialogResult.Cancel;

                form.Controls.Add(label);
                form.Controls.Add(input);
                form.Controls.Add(ok);
                form.Controls.Add(cancel);
                form.AcceptButton = ok;
                form.CancelButton = cancel;

                return form.ShowDialog() == DialogResult.OK ? input.Text : string.Empty;
            }
        }
    }

    internal static class L
    {
        private static readonly Dictionary<string, string[]> Text = new Dictionary<string, string[]>
        {
            { "StartupBalloon", new[] { "Running in the task tray. Right-click for the menu.", "タスクトレイで動作中です。右クリックでメニューを開けます。" } },
            { "NormalMode", new[] { "Normal Mode", "通常モード" } },
            { "normalName", new[] { "Normal Mode", "通常モード" } },
            { "NormalModeDescription", new[] { "Power button, sleep button, and lid close all put the PC to sleep", "電源ボタン、スリープボタン、カバーを閉じる操作はすべてスリープにします" } },
            { "normalDescription", new[] { "Power button, sleep button, and lid close all put the PC to sleep", "電源ボタン、スリープボタン、カバーを閉じる操作はすべてスリープにします" } },
            { "WorkMode", new[] { "Work Mode", "作業中モード" } },
            { "workName", new[] { "Work Mode", "作業中モード" } },
            { "WorkModeDescription", new[] { "Do nothing for all actions (for presentations and long-running work)", "すべて「何もしない」にします（プレゼンや長時間作業向け）" } },
            { "workDescription", new[] { "Do nothing for all actions (for presentations and long-running work)", "すべて「何もしない」にします（プレゼンや長時間作業向け）" } },
            { "PowerSavingMode", new[] { "Power Saving Mode", "省電力モード" } },
            { "powerSavingName", new[] { "Power Saving Mode", "省電力モード" } },
            { "PowerSavingModeDescription", new[] { "Sleep for all actions (battery saving)", "すべてスリープにします（バッテリー節約）" } },
            { "powerSavingDescription", new[] { "Sleep for all actions (battery saving)", "すべてスリープにします（バッテリー節約）" } },
            { "FailedLoadPresets", new[] { "Failed to load presets.json. Restoring default presets.", "presets.json の読み込みに失敗しました。既定のプリセットに戻します。" } },
            { "CouldNotGetScheme", new[] { "Could not get the GUID of the active power plan.", "アクティブな電源プランの GUID を取得できませんでした。" } },
            { "InvalidActionValue", new[] { "Preset action values must be between 0 and 3.", "プリセットの動作値は 0 から 3 の間である必要があります。" } },
            { "ProcessFailed", new[] { "{0} failed with exit code {1}.", "{0} が終了コード {1} で失敗しました。" } },
            { "CurrentNone", new[] { "Current: (none)", "現在: (未適用)" } },
            { "CurrentPrefix", new[] { "Current: ", "現在: " } },
            { "AppliedPreset", new[] { "Applied preset '{0}'.", "プリセット「{0}」を適用しました。" } },
            { "FailedApplyPreset", new[] { "Failed to apply preset:", "プリセットの適用に失敗しました:" } },
            { "PresetSettings", new[] { "Preset settings...", "プリセット設定..." } },
            { "RegisterStartup", new[] { "Register for startup", "スタートアップに登録" } },
            { "FailedStartup", new[] { "Failed to update startup setting:", "スタートアップ設定の更新に失敗しました:" } },
            { "Language", new[] { "Language", "言語" } },
            { "LanguageChanged", new[] { "Language changed.", "言語を切り替えました。" } },
            { "Exit", new[] { "Exit", "終了" } },
            { "SettingsTitle", new[] { "PowerControl Settings", "PowerControl 設定" } },
            { "Presets", new[] { "Presets", "プリセット" } },
            { "Add", new[] { "Add", "追加" } },
            { "Rename", new[] { "Rename", "名前変更" } },
            { "Delete", new[] { "Delete", "削除" } },
            { "Description", new[] { "Description", "説明" } },
            { "PluggedIn", new[] { "Plugged in", "電源に接続" } },
            { "OnBattery", new[] { "On battery", "バッテリー駆動" } },
            { "PowerButtonLabel", new[] { "When I press the power button", "電源ボタンを押したとき" } },
            { "SleepButtonLabel", new[] { "When I press the sleep button", "スリープボタンを押したとき" } },
            { "LidLabel", new[] { "When I close the lid", "カバーを閉じたとき" } },
            { "Cancel", new[] { "Cancel", "キャンセル" } },
            { "Save", new[] { "Save", "保存" } },
            { "SaveApply", new[] { "Save and Apply", "保存して適用" } },
            { "EnterPresetName", new[] { "Enter a preset name", "プリセット名を入力してください" } },
            { "NewPreset", new[] { "New Preset", "新しいプリセット" } },
            { "NewName", new[] { "New name", "新しい名前" } },
            { "AtLeastOnePreset", new[] { "At least one preset is required.", "最低 1 つのプリセットが必要です。" } },
            { "DeletePreset", new[] { "Delete preset '{0}'?", "プリセット「{0}」を削除しますか？" } },
            { "Confirm", new[] { "Confirm", "確認" } },
            { "OK", new[] { "OK", "OK" } }
        };

        public static string T(string key)
        {
            string[] values;
            if (!Text.TryGetValue(key, out values))
            {
                return key;
            }

            return Program.CurrentLanguage == "ja" ? values[1] : values[0];
        }

        public static string ActionName(int value)
        {
            switch (value)
            {
                case 0:
                    return Program.CurrentLanguage == "ja" ? "何もしない" : "Do nothing";
                case 1:
                    return Program.CurrentLanguage == "ja" ? "スリープ" : "Sleep";
                case 2:
                    return Program.CurrentLanguage == "ja" ? "休止状態" : "Hibernate";
                case 3:
                    return Program.CurrentLanguage == "ja" ? "シャットダウン" : "Shut down";
                default:
                    return value.ToString();
            }
        }
    }

    [DataContract]
    internal sealed class PresetConfig
    {
        [DataMember]
        public List<Preset> presets { get; set; }
    }

    [DataContract]
    internal sealed class Preset
    {
        public string displayName
        {
            get { return Program.PresetDisplayName(this); }
        }

        [DataMember(EmitDefaultValue = false)]
        public string key { get; set; }

        [DataMember]
        public string name { get; set; }

        [DataMember]
        public string description { get; set; }

        [DataMember]
        public ActionPair power { get; set; }

        [DataMember]
        public ActionPair sleep { get; set; }

        [DataMember]
        public ActionPair lid { get; set; }
    }

    [DataContract]
    internal sealed class ActionPair
    {
        [DataMember]
        public int ac { get; set; }

        [DataMember]
        public int dc { get; set; }
    }

    [DataContract]
    internal sealed class State
    {
        [DataMember(EmitDefaultValue = false)]
        public string lastPreset { get; set; }

        [DataMember(EmitDefaultValue = false)]
        public string language { get; set; }
    }
}
