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

        private static readonly Dictionary<int, string> ActionNames = new Dictionary<int, string>
        {
            { 0, "Do nothing" },
            { 1, "Sleep" },
            { 2, "Hibernate" },
            { 3, "Shut down" }
        };

        private static string AppDir;
        private static string PresetsPath;
        private static string StatePath;
        private static NotifyIcon NotifyIcon;

        [STAThread]
        private static void Main()
        {
            AppDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            PresetsPath = Path.Combine(AppDir, "presets.json");
            StatePath = Path.Combine(AppDir, "state.json");

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
            ShowBalloonTip("PowerControl", "Running in the task tray. Right-click for the menu.");

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
                        name = "Normal Mode",
                        description = "Power button, sleep button, and lid close all put the PC to sleep",
                        power = new ActionPair { ac = 1, dc = 1 },
                        sleep = new ActionPair { ac = 1, dc = 1 },
                        lid = new ActionPair { ac = 1, dc = 1 }
                    },
                    new Preset
                    {
                        name = "Work Mode",
                        description = "Do nothing for all actions (for presentations and long-running work)",
                        power = new ActionPair { ac = 0, dc = 0 },
                        sleep = new ActionPair { ac = 0, dc = 0 },
                        lid = new ActionPair { ac = 0, dc = 0 }
                    },
                    new Preset
                    {
                        name = "Power Saving Mode",
                        description = "Sleep for all actions (battery saving)",
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
                MessageBox.Show("Failed to load presets.json. Restoring default presets.\n" + ex.Message, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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
            SaveJson(StatePath, state);
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

            throw new InvalidOperationException("Could not get the GUID of the active power plan.");
        }

        private static void ApplyPreset(Preset preset)
        {
            ValidatePreset(preset);
            string scheme = GetActiveSchemeGuid();
            SetPowerValue(scheme, GuidPower, preset.power.ac, preset.power.dc);
            SetPowerValue(scheme, GuidSleep, preset.sleep.ac, preset.sleep.dc);
            SetPowerValue(scheme, GuidLid, preset.lid.ac, preset.lid.dc);
            RunProcess("powercfg.exe", "/setactive " + scheme, false);
            SaveState(new State { lastPreset = preset.name });
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
                throw new InvalidOperationException("Preset action values must be between 0 and 3.");
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
                    throw new InvalidOperationException(fileName + " failed with exit code " + process.ExitCode + ".\n" + output);
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

            ToolStripMenuItem header = new ToolStripMenuItem(state.lastPreset == null ? "Current: (none)" : "Current: " + state.lastPreset)
            {
                Enabled = false
            };
            menu.Items.Add(header);
            menu.Items.Add(new ToolStripSeparator());

            foreach (Preset preset in data.presets)
            {
                Preset presetRef = preset;
                ToolStripMenuItem item = new ToolStripMenuItem(preset.name)
                {
                    Checked = preset.name == state.lastPreset,
                    ToolTipText = preset.description
                };
                item.Click += delegate
                {
                    try
                    {
                        ApplyPreset(presetRef);
                        ShowBalloonTip("PowerControl", "Applied preset '" + presetRef.name + "'.");
                        RefreshTrayMenu();
                    }
                    catch (Exception ex)
                    {
                        MessageBox.Show("Failed to apply preset:\n" + ex.Message, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                };
                menu.Items.Add(item);
            }

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem settings = new ToolStripMenuItem("Preset settings...");
            settings.Click += delegate
            {
                using (SettingsForm form = new SettingsForm(LoadPresets(), ActionNames))
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
                            ShowBalloonTip("PowerControl", "Applied preset '" + form.ApplyPreset.name + "'.");
                        }
                        catch (Exception ex)
                        {
                            MessageBox.Show("Failed to apply preset:\n" + ex.Message, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        }
                    }
                }
                RefreshTrayMenu();
            };
            menu.Items.Add(settings);

            ToolStripMenuItem autoStart = new ToolStripMenuItem("Register for startup")
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
                    MessageBox.Show("Failed to update startup setting:\n" + ex.Message, "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            };
            menu.Items.Add(autoStart);

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem exit = new ToolStripMenuItem("Exit");
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

        private static void ShowBalloonTip(string title, string text)
        {
            NotifyIcon.BalloonTipTitle = title;
            NotifyIcon.BalloonTipText = text;
            NotifyIcon.ShowBalloonTip(2500);
        }
    }

    internal sealed class SettingsForm : Form
    {
        private readonly Dictionary<int, string> actionNames;
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

        public SettingsForm(PresetConfig config, Dictionary<int, string> actionNames)
        {
            this.Config = config;
            this.actionNames = actionNames;
            InitializeComponent();
            LoadPresetsList();
        }

        private void InitializeComponent()
        {
            Text = "PowerControl Settings";
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
            Label presetsLabel = new Label { Text = "Presets", Dock = DockStyle.Top, Font = new Font(Font, FontStyle.Bold), Height = 24 };
            FlowLayoutPanel presetButtons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 34 };
            Button add = new Button { Text = "Add", Width = 60 };
            Button rename = new Button { Text = "Rename", Width = 68 };
            Button delete = new Button { Text = "Delete", Width = 60 };
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

            AddFullRow(fields, "Description", true);
            descriptionText.Dock = DockStyle.Fill;
            fields.Controls.Add(descriptionText, 0, fields.RowCount - 1);
            fields.SetColumnSpan(descriptionText, 2);

            AddFullRow(fields, "Plugged in", true);
            AddActionRow(fields, "When I press the power button", powerAc);
            AddActionRow(fields, "When I press the sleep button", sleepAc);
            AddActionRow(fields, "When I close the lid", lidAc);

            AddFullRow(fields, "On battery", true);
            AddActionRow(fields, "When I press the power button", powerDc);
            AddActionRow(fields, "When I press the sleep button", sleepDc);
            AddActionRow(fields, "When I close the lid", lidDc);

            FlowLayoutPanel bottom = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.RightToLeft,
                Dock = DockStyle.Fill
            };
            Button cancel = new Button { Text = "Cancel", Width = 80 };
            Button save = new Button { Text = "Save", Width = 80 };
            Button saveApply = new Button { Text = "Save and Apply", Width = 120 };
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
                    combo.Items.Add(actionNames[i]);
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
            presetsList.DisplayMember = "name";
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
            string name = Prompt.Show("Enter a preset name", "Add", "New Preset");
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

            string name = Prompt.Show("New name", "Rename", preset.name);
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
                MessageBox.Show("At least one preset is required.", "PowerControl", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (MessageBox.Show("Delete preset '" + preset.name + "'?", "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
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

                ok.Text = "OK";
                ok.Left = 232;
                ok.Top = 78;
                ok.Width = 75;
                ok.DialogResult = DialogResult.OK;

                cancel.Text = "Cancel";
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

    [DataContract]
    internal sealed class PresetConfig
    {
        [DataMember]
        public List<Preset> presets { get; set; }
    }

    [DataContract]
    internal sealed class Preset
    {
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
    }
}
