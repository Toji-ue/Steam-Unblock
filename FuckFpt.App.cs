using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace FuckFptDesktop
{
    static class Program
    {
        internal static readonly string Payload = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "FuckFptDesktop");
        internal static readonly uint ShowMessage = RegisterWindowMessage("FuckFpt.Desktop.Show.v1");
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string name);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        [STAThread]
        static void Main()
        {
            Forms.Application.EnableVisualStyles();
            bool created;
            using (var mutex = new Mutex(true, "Local\\FuckFpt.Desktop.v1", out created))
            {
                if (!created) { PostMessage(new IntPtr(0xffff), ShowMessage, IntPtr.Zero, IntPtr.Zero); return; }
                try { ExtractPayload(); new Application().Run(new MainWindow()); }
                catch (Exception ex) { MessageBox.Show(ex.Message, "Không mở được Fuck FPT", MessageBoxButton.OK, MessageBoxImage.Error); }
                finally { mutex.ReleaseMutex(); }
            }
        }

        static void ExtractPayload()
        {
            var admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            if (Directory.Exists(Payload))
            {
                if ((File.GetAttributes(Payload) & FileAttributes.ReparsePoint) != 0) throw new IOException("Thư mục ứng dụng là liên kết. Không tiếp tục.");
                var existing = Directory.GetAccessControl(Payload);
                var owner = existing.GetOwner(typeof(SecurityIdentifier));
                if (!owner.Equals(admins) && !owner.Equals(system)) throw new IOException("Thư mục ứng dụng không thuộc Administrators/SYSTEM.");
                foreach (FileSystemAccessRule rule in existing.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                    if (rule.AccessControlType == AccessControlType.Allow && !rule.IdentityReference.Equals(admins) && !rule.IdentityReference.Equals(system) &&
                        (rule.FileSystemRights & (FileSystemRights.Write | FileSystemRights.Delete | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership)) != 0)
                        throw new IOException("Quyền ghi thư mục ứng dụng không an toàn.");
            }
            else
            {
                var acl = new DirectorySecurity();
                acl.SetAccessRuleProtection(true, false); acl.SetOwner(admins);
                foreach (var sid in new[] { admins, system })
                    acl.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
                acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null), FileSystemRights.ReadAndExecute,
                    InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
                Directory.CreateDirectory(Payload, acl);
            }
            string vendor = Path.Combine(Payload, "vendor");
            if (Directory.Exists(vendor) && (File.GetAttributes(vendor) & FileAttributes.ReparsePoint) != 0) throw new IOException("Thư mục vendor là liên kết.");
            Directory.CreateDirectory(vendor);
            foreach (string name in new[] { "FuckFpt.psm1", "AppWorker.ps1", "steam-domains.txt", "manifest.json", "goodbyedpi-0.2.3rc3-2.zip" })
            {
                string destination = Path.Combine(name.EndsWith(".zip", StringComparison.Ordinal) ? vendor : Payload, name);
                string temp = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
                try
                {
                    using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("Payload." + name))
                    {
                        if (input == null) throw new IOException("Thiếu tài nguyên: " + name);
                        using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write)) input.CopyTo(output);
                    }
                    if (File.Exists(destination)) File.Replace(temp, destination, null); else File.Move(temp, destination);
                }
                finally { if (File.Exists(temp)) File.Delete(temp); }
            }
        }
    }

    static class Backend
    {
        static readonly object sync = new object();
        static Process current;
        static bool halted;

        // Kills the running worker and refuses new ones (except Stop) until Halt(false); used by exit.
        internal static void Halt(bool on)
        {
            lock (sync) { halted = on; if (on) Kill(current); }
        }
        internal static void KillCurrent() { lock (sync) Kill(current); }
        static string Tail(Task<string> stream) { return stream.Wait(1000) ? stream.Result : ""; }
        static void Kill(Process process)
        {
            try { if (process != null) process.Kill(); }
            catch (InvalidOperationException) { } catch (Win32Exception) { }
        }

        // progress receives each live log line from the worker, on a background thread.
        internal static Dictionary<string, object> Run(string action, Action<string> progress)
        {
            if (!new[] { "Status", "Diagnose", "Start", "Stop", "Restart" }.Contains(action)) throw new ArgumentException("Lệnh không hợp lệ.");
            var info = new ProcessStartInfo {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
                Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + Path.Combine(Program.Payload, "AppWorker.ps1") + "\" -Action " + action,
                UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
                WorkingDirectory = Program.Payload
            };
            using (var process = new Process { StartInfo = info })
            {
                lock (sync)
                {
                    if (halted && action != "Stop") throw new OperationCanceledException("Đã hủy vì ứng dụng đang thoát.");
                    process.Start(); current = process;
                }
                try
                {
                    // Read up to the JSON line, never to EOF: GoodbyeDPI started by the worker inherits this pipe and keeps it open.
                    Task<string> stdout = Task.Run(() => {
                        string line;
                        while ((line = process.StandardOutput.ReadLine()) != null)
                        {
                            if (line.StartsWith("{\"Ok\":", StringComparison.Ordinal)) return line;
                            progress(line);
                        }
                        return null;
                    });
                    Task<string> stderr = process.StandardError.ReadToEndAsync();
                    // Start tries two profiles with network probes; 10 minutes is far beyond a healthy run.
                    if (!process.WaitForExit(10 * 60 * 1000)) { Kill(process); throw new TimeoutException("Bộ xử lý không phản hồi sau 10 phút; đã dừng. Chạy Tắt / phục hồi để kiểm tra."); }
                    if (!stdout.Wait(5000) || stdout.Result == null) throw new IOException("Không nhận được trạng thái từ bộ xử lý. " + Tail(stderr));
                    var parsed = new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024 }.Deserialize<Dictionary<string, object>>(stdout.Result);
                    if (process.ExitCode != 0 && Flag(parsed, "Ok")) throw new IOException("Bộ xử lý thoát bất thường. " + Tail(stderr));
                    return parsed;
                }
                finally { lock (sync) current = null; }
            }
        }
        internal static string Text(Dictionary<string, object> data, string name)
        { object value; return data != null && data.TryGetValue(name, out value) && value != null ? Convert.ToString(value, CultureInfo.InvariantCulture) : ""; }
        internal static bool Flag(Dictionary<string, object> data, string name)
        { object value; return data != null && data.TryGetValue(name, out value) && value is bool && (bool)value; }
        internal static Dictionary<string, object> Object(Dictionary<string, object> data, string name)
        { object value; return data != null && data.TryGetValue(name, out value) ? value as Dictionary<string, object> : null; }
        internal static string Milliseconds(Dictionary<string, object> data, string name)
        { double seconds; return double.TryParse(Text(data, name), NumberStyles.Float, CultureInfo.InvariantCulture, out seconds) && seconds > 0 ? (seconds * 1000).ToString("0", CultureInfo.InvariantCulture) : "—"; }
    }

    sealed class MainWindow : Window
    {
        const string Layout = @"
<Grid xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' Margin='28,22,28,20'>
  <Grid.Resources>
    <SolidColorBrush x:Key='Card' Color='#181B22'/>
    <SolidColorBrush x:Key='Line' Color='#262A33'/>
    <SolidColorBrush x:Key='Muted' Color='#8B93A1'/>
    <Style x:Key='Btn' TargetType='Button'>
      <Setter Property='Foreground' Value='#E6E8EB'/>
      <Setter Property='Background' Value='#20242C'/>
      <Setter Property='BorderBrush' Value='#2E333D'/>
      <Setter Property='FontSize' Value='14'/>
      <Setter Property='Padding' Value='18,9'/>
      <Setter Property='Margin' Value='0,0,10,0'/>
      <Setter Property='Cursor' Value='Hand'/>
      <Setter Property='Template'>
        <Setter.Value>
          <ControlTemplate TargetType='Button'>
            <Border x:Name='b' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='1' CornerRadius='10' Padding='{TemplateBinding Padding}'>
              <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='Background' Value='#2A2F39'/></Trigger>
              <Trigger Property='IsPressed' Value='True'><Setter TargetName='b' Property='Background' Value='#323845'/></Trigger>
              <Trigger Property='IsEnabled' Value='False'><Setter Property='Opacity' Value='0.4'/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key='Power' TargetType='Button'>
      <Setter Property='Cursor' Value='Hand'/>
      <Setter Property='Template'>
        <Setter.Value>
          <ControlTemplate TargetType='Button'>
            <Grid>
              <Ellipse Fill='{TemplateBinding BorderBrush}' Opacity='0.16' Margin='-12'/>
              <Ellipse x:Name='e' Fill='{TemplateBinding Background}' Stroke='{TemplateBinding BorderBrush}' StrokeThickness='2'/>
              <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property='IsMouseOver' Value='True'><Setter TargetName='e' Property='Opacity' Value='0.86'/></Trigger>
              <Trigger Property='IsPressed' Value='True'><Setter TargetName='e' Property='Opacity' Value='0.72'/></Trigger>
              <Trigger Property='IsEnabled' Value='False'><Setter Property='Opacity' Value='0.5'/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Grid.Resources>
  <Grid.RowDefinitions>
    <RowDefinition Height='Auto'/><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/>
    <RowDefinition Height='*'/><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/>
  </Grid.RowDefinitions>
  <DockPanel Margin='0,0,0,18'>
    <TextBlock Text='FUCK FPT' FontSize='26' FontWeight='Bold' Foreground='#E6E8EB'/>
    <TextBlock x:Name='network' Foreground='{StaticResource Muted}' FontSize='12' VerticalAlignment='Center' HorizontalAlignment='Right' TextTrimming='CharacterEllipsis' Margin='24,0,0,0'/>
  </DockPanel>
  <Border Grid.Row='1' Background='{StaticResource Card}' BorderBrush='{StaticResource Line}' BorderThickness='1' CornerRadius='16' Padding='28,24'>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width='*'/><ColumnDefinition Width='Auto'/></Grid.ColumnDefinitions>
      <StackPanel VerticalAlignment='Center'>
        <StackPanel Orientation='Horizontal'>
          <Ellipse x:Name='dot' Width='10' Height='10' Fill='#8B93A1' Margin='0,0,10,0' VerticalAlignment='Center'/>
          <TextBlock x:Name='state' Text='Đang đọc trạng thái…' FontSize='22' FontWeight='SemiBold' Foreground='#E6E8EB'/>
        </StackPanel>
        <TextBlock x:Name='detail' Foreground='{StaticResource Muted}' FontSize='13' Margin='20,8,0,0' TextWrapping='Wrap'/>
        <StackPanel Orientation='Horizontal' Margin='20,22,0,0'>
          <Button x:Name='probe' Style='{StaticResource Btn}' Content='Kiểm tra kết nối'/>
          <Button x:Name='restart' Style='{StaticResource Btn}' Content='Khởi động lại'/>
        </StackPanel>
      </StackPanel>
      <StackPanel Grid.Column='1' Margin='24,0,8,0' VerticalAlignment='Center'>
        <Grid Width='164' Height='164'>
          <Ellipse x:Name='spinner' Stroke='#22C55E' StrokeThickness='4' StrokeDashArray='26 100' StrokeDashCap='Round' RenderTransformOrigin='0.5,0.5' Visibility='Collapsed'>
            <Ellipse.RenderTransform><RotateTransform/></Ellipse.RenderTransform>
          </Ellipse>
          <Button x:Name='power' Style='{StaticResource Power}' Width='132' Height='132' Background='#20242C' BorderBrush='#2E333D' AutomationProperties.Name='Bật hoặc tắt kết nối'>
            <TextBlock Text='&#xE7E8;' FontFamily='Segoe MDL2 Assets' FontSize='44' Foreground='#FFFFFF'/>
          </Button>
        </Grid>
        <TextBlock x:Name='powerCaption' Foreground='{StaticResource Muted}' FontSize='12' HorizontalAlignment='Center' Margin='0,16,0,0'/>
      </StackPanel>
    </Grid>
  </Border>
  <TextBlock x:Name='report' Grid.Row='2' Margin='2,22,0,12' Foreground='{StaticResource Muted}' FontSize='12' TextWrapping='Wrap' Text='Chưa có phép đo · ứng dụng sẽ tự kiểm tra khi mở'/>
  <ScrollViewer Grid.Row='3' VerticalScrollBarVisibility='Auto'>
    <WrapPanel x:Name='cards'/>
  </ScrollViewer>
  <TextBlock x:Name='activity' Grid.Row='4' Margin='2,10,0,8' Foreground='{StaticResource Muted}' FontSize='12'/>
  <Border Grid.Row='5' Background='{StaticResource Card}' BorderBrush='{StaticResource Line}' BorderThickness='1' CornerRadius='12' Padding='14,10,6,8'>
    <DockPanel>
      <TextBlock DockPanel.Dock='Top' Text='LOG' FontSize='11' FontWeight='SemiBold' Foreground='{StaticResource Muted}' Margin='2,0,0,6'/>
      <TextBox x:Name='log' Height='150' IsReadOnly='True' TextWrapping='NoWrap' VerticalScrollBarVisibility='Auto' HorizontalScrollBarVisibility='Auto'
               Background='Transparent' BorderThickness='0' Foreground='#C9CED6' FontFamily='Consolas' FontSize='12' AutomationProperties.Name='Log thao tác'/>
    </DockPanel>
  </Border>
</Grid>";

        static readonly Brush TextBrush = Hex("#E6E8EB"), MutedBrush = Hex("#8B93A1"), CardBrush = Hex("#181B22"), LineBrush = Hex("#262A33"),
            Green = Hex("#22C55E"), Red = Hex("#EF4444"), Orange = Hex("#F59E0B"), IdleFill = Hex("#20242C"), IdleLine = Hex("#3A404C");
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

        readonly Button power, probe, restart;
        readonly TextBlock state, detail, network, report, activity, powerCaption;
        readonly System.Windows.Shapes.Ellipse dot, spinner;
        readonly WrapPanel cards;
        readonly TextBox log;
        readonly Forms.NotifyIcon tray = new Forms.NotifyIcon();
        readonly Forms.ToolStripMenuItem trayStart = new Forms.ToolStripMenuItem("Bật kết nối"), trayStop = new Forms.ToolStripMenuItem("Tắt / phục hồi"), trayRestart = new Forms.ToolStripMenuItem("Khởi động lại");
        readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        // One worker at a time. User actions wait for a background poll instead of being dropped.
        readonly SemaphoreSlim gate = new SemaphoreSlim(1, 1);
        bool userBusy, backgroundBusy, preempted, exiting, allowClose, running, recovery, staleReport;
        DateTime operationBegan, lastStatus = DateTime.MinValue;
        string actionText = "", lastReportAt = "";

        static Brush Hex(string color) { var brush = (SolidColorBrush)new BrushConverter().ConvertFromString(color); brush.Freeze(); return brush; }

        internal MainWindow()
        {
            Title = "Fuck FPT"; Width = 1000; Height = 760; MinWidth = 840; MinHeight = 640;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = Hex("#0F1115"); Foreground = TextBrush; FontFamily = new FontFamily("Segoe UI");
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("App.ico"))
                Icon = System.Windows.Media.Imaging.BitmapFrame.Create(stream, System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
            var root = (FrameworkElement)XamlReader.Parse(Layout);
            Content = root;
            power = (Button)root.FindName("power"); probe = (Button)root.FindName("probe"); restart = (Button)root.FindName("restart");
            state = (TextBlock)root.FindName("state"); detail = (TextBlock)root.FindName("detail"); network = (TextBlock)root.FindName("network");
            report = (TextBlock)root.FindName("report"); activity = (TextBlock)root.FindName("activity"); powerCaption = (TextBlock)root.FindName("powerCaption");
            dot = (System.Windows.Shapes.Ellipse)root.FindName("dot"); cards = (WrapPanel)root.FindName("cards"); log = (TextBox)root.FindName("log");
            spinner = (System.Windows.Shapes.Ellipse)root.FindName("spinner");

            var menu = new Forms.ContextMenuStrip();
            menu.Items.Add("Mở Fuck FPT", null, delegate { ShowWindow(); });
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.AddRange(new Forms.ToolStripItem[] { trayStart, trayStop, trayRestart });
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("Thoát…", null, delegate { RequestExit(); });
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("App.ico")) tray.Icon = new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize);
            tray.Text = "Fuck FPT"; tray.ContextMenuStrip = menu; tray.Visible = true;
            tray.DoubleClick += delegate { ShowWindow(); };

            power.Click += async delegate { await Operate(running || recovery ? "Stop" : "Start", false); };
            probe.Click += async delegate { await Operate("Diagnose", false); };
            restart.Click += async delegate { await Operate("Restart", false); };
            trayStart.Click += async delegate { await Operate("Start", false); };
            trayStop.Click += async delegate { await Operate("Stop", false); };
            trayRestart.Click += async delegate { await Operate("Restart", false); };
            ContentRendered += async delegate { if (await Check("Status")) await Check("Diagnose"); };
            Closed += delegate { timer.Stop(); tray.Visible = false; tray.Dispose(); };
            timer.Tick += async delegate {
                if (userBusy || exiting) activity.Text = actionText + " · " + ((int)(DateTime.UtcNow - operationBegan).TotalSeconds) + " giây";
                else if ((DateTime.UtcNow - lastStatus).TotalSeconds >= 15) await Check("Status");
            };
            timer.Start(); ApplyLook(); UpdateButtons();
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            var source = (HwndSource)PresentationSource.FromVisual(this);
            source.AddHook(Hook);
            int dark = 1; DwmSetWindowAttribute(source.Handle, 20, ref dark, 4); // dark title bar; ignored on older Windows
        }
        IntPtr Hook(IntPtr window, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
        { if ((uint)message == Program.ShowMessage) ShowWindow(); return IntPtr.Zero; }

        protected override void OnStateChanged(EventArgs e)
        {
            if (WindowState == WindowState.Minimized)
            {
                Hide();
                tray.ShowBalloonTip(1800, "Fuck FPT đang ở khay hệ thống", "Nhấp đúp biểu tượng để mở lại. Kết nối được giữ nguyên.", Forms.ToolTipIcon.Info);
            }
            base.OnStateChanged(e);
        }
        protected override void OnClosing(CancelEventArgs e)
        {
            // Defer: Show() and dialogs are illegal while WPF is still inside Closing.
            if (!allowClose) { e.Cancel = true; Dispatcher.BeginInvoke(new Action(RequestExit)); }
            base.OnClosing(e);
        }
        void ShowWindow() { Show(); if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal; Activate(); }

        // Exit is always allowed: confirm, kill any in-flight worker, then Stop reverts DNS/driver via the state journal.
        async void RequestExit()
        {
            if (exiting) return;
            ShowWindow();
            if (MessageBox.Show(this, "Bạn muốn thoát Fuck FPT?\nKết nối sẽ tắt và DNS riêng sẽ được hoàn tác.", "Xác nhận thoát",
                MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
            exiting = true; operationBegan = DateTime.UtcNow; actionText = "Đang tắt và hoàn tác DNS trước khi thoát";
            activity.Text = actionText; UpdateButtons();
            Backend.Halt(true);
            Log("▶ " + actionText);
            await gate.WaitAsync();
            try
            {
                var result = await Task.Run(() => Backend.Run("Stop", LiveLog));
                if (Backend.Flag(result, "Ok")) { allowClose = true; Close(); return; }
                Log("✗ Chưa hoàn tác được");
            }
            catch (Exception ex) { Log("✗ " + ex.Message); }
            finally { gate.Release(); }
            Backend.Halt(false); exiting = false; UpdateButtons();
            activity.Text = "Chưa thoát · chưa hoàn tác xong, xem chi tiết";
            MessageBox.Show(this, "Chưa hoàn tác được. Ứng dụng vẫn mở để bạn xem lỗi và thử Tắt / phục hồi.", "Chưa thoát", MessageBoxButton.OK, MessageBoxImage.Warning);
        }

        async Task<bool> Operate(string action, bool quiet)
        {
            if (userBusy || exiting) return false;
            userBusy = true; operationBegan = DateTime.UtcNow;
            actionText = Describe(action);
            if (!quiet) activity.Text = actionText;
            UpdateButtons();
            // A background check is read-only, so a click cancels it instead of waiting behind it.
            if (backgroundBusy) { preempted = true; Backend.KillCurrent(); }
            await gate.WaitAsync();
            try { return !exiting && await Execute(action, quiet); }
            finally { gate.Release(); userBusy = false; UpdateButtons(); }
        }
        // Status/Diagnose that never disable the buttons; used at startup and for the periodic refresh.
        async Task<bool> Check(string action)
        {
            if (userBusy || exiting || !gate.Wait(0)) return false;
            backgroundBusy = true; preempted = false;
            if (action == "Diagnose") activity.Text = "Đang kiểm tra kết nối nền · bạn vẫn bấm được các nút";
            try
            {
                bool ok = await Execute(action, true);
                if (ok && action == "Diagnose" && !preempted) activity.Text = "Đã kiểm tra · " + DateTime.Now.ToString("HH:mm:ss");
                return ok && !preempted;
            }
            finally { backgroundBusy = false; gate.Release(); }
        }
        static string Describe(string action)
        {
            return action == "Start" ? "Đang bật và xác nhận kết nối" : action == "Stop" ? "Đang tắt và hoàn tác DNS" : action == "Restart" ? "Đang khởi động lại kết nối" : action == "Diagnose" ? "Đang kiểm tra DNS / TCP / TLS" : "Đang cập nhật trạng thái";
        }
        void Log(string line)
        {
            log.AppendText((log.Text.Length > 0 ? "\r\n" : "") + "[" + DateTime.Now.ToString("HH:mm:ss") + "] " + line);
            if (log.Text.Length > 60000) log.Text = log.Text.Substring(log.Text.Length - 40000); // keep the box responsive on long sessions
            log.ScrollToEnd();
        }
        void LiveLog(string line) { Dispatcher.BeginInvoke(new Action(() => Log(line))); }

        async Task<bool> Execute(string action, bool quiet)
        {
            bool logged = action != "Status"; // the 15 s refresh would flood the log
            if (logged) Log("▶ " + Describe(action));
            try
            {
                var result = await Task.Run(() => Backend.Run(action, LiveLog));
                if (action == "Stop") staleReport = true;
                if (action == "Diagnose" || action == "Start" || action == "Restart") staleReport = false;
                Render(result);
                bool ok = Backend.Flag(result, "Ok");
                string message = Backend.Text(result, "Message");
                if (logged || !ok) Log(ok ? "✓ Hoàn tất" : "✗ Chưa hoàn tất" + (logged ? "" : ": " + message));
                if (!quiet) activity.Text = ok ? "Hoàn tất · " + DateTime.Now.ToString("HH:mm:ss") : "Chưa hoàn tất · xem log";
                if (!ok && !quiet) { ShowWindow(); MessageBox.Show(this, message, "Chưa thực hiện được", MessageBoxButton.OK, MessageBoxImage.Warning); }
                return ok;
            }
            catch (Exception ex)
            {
                if (exiting) return false; // worker killed on purpose by exit
                if (quiet && preempted) { if (logged) Log("· Đã dừng kiểm tra nền để chạy thao tác của bạn"); return false; }
                Log("✗ " + ex.Message);
                activity.Text = "Không đọc được kết quả · trạng thái hiển thị có thể đã cũ";
                if (!quiet) { ShowWindow(); MessageBox.Show(this, ex.Message, "Lỗi xử lý", MessageBoxButton.OK, MessageBoxImage.Error); }
                return false;
            }
            finally { lastStatus = DateTime.UtcNow; }
        }

        void UpdateButtons()
        {
            bool idle = !userBusy && !exiting;
            power.IsEnabled = probe.IsEnabled = restart.IsEnabled = trayRestart.Enabled = idle;
            trayStart.Enabled = idle && !running && !recovery;
            trayStop.Enabled = idle && (running || recovery);
            if (idle) ApplyLook(); else powerCaption.Text = actionText + "…";
            bool spin = !idle;
            if ((spinner.Visibility == Visibility.Visible) == spin) return; // restarting the animation would make it jump
            spinner.Visibility = spin ? Visibility.Visible : Visibility.Collapsed;
            spinner.RenderTransform.BeginAnimation(RotateTransform.AngleProperty, spin ? new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1.1)) { RepeatBehavior = RepeatBehavior.Forever } : null);
        }
        void ApplyLook()
        {
            Brush accent = recovery ? Orange : running ? Green : null;
            power.Background = accent ?? IdleFill; power.BorderBrush = accent ?? IdleLine; dot.Fill = accent ?? MutedBrush;
            powerCaption.Text = recovery ? "Cần phục hồi · bấm để phục hồi" : running ? "Đang bật · bấm để tắt" : "Đã tắt · bấm để bật";
            state.Text = recovery ? "Cần phục hồi phiên trước" : running ? "Đang bật kết nối Steam" : "Đã tắt kết nối";
            tray.Text = recovery ? "Fuck FPT · Cần phục hồi" : running ? "Fuck FPT · Đang bật" : "Fuck FPT · Đã tắt";
        }

        void Render(Dictionary<string, object> result)
        {
            var status = Backend.Object(result, "Status");
            if (status == null) throw new IOException("Thiếu trạng thái kết nối; không giả định đã tắt.");
            bool previous = running;
            running = Backend.Flag(status, "ProcessRunning"); recovery = Backend.Flag(status, "RecoveryRequired");
            if (previous != running) staleReport = true;
            detail.Text = running ? "Cấu hình " + Backend.Text(status, "Profile") + "  ·  PID " + Backend.Text(status, "EnginePid") + "  ·  DNS Steam: 1.1.1.1 / 8.8.8.8"
                : recovery ? "Bấm nút nguồn hoặc Khởi động lại để xử lý phiên còn lại." : "Đang dùng DNS hệ thống";
            ApplyLook(); UpdateButtons();
            var networks = NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback && n.GetIPProperties().GatewayAddresses.Count > 0);
            network.Text = string.Join("  |  ", networks.Select(n => n.Name + " · " + string.Join(", ", n.GetIPProperties().UnicastAddresses.Where(a => a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork).Select(a => a.Address.ToString()))).ToArray());
            if (network.Text.Length == 0) network.Text = "Không tìm thấy adapter có gateway hoạt động.";
            var data = Backend.Object(result, "Report");
            if (data == null) return;
            string at = Backend.Text(data, "At");
            if (at != lastReportAt)
            {
                lastReportAt = at; staleReport = false; cards.Children.Clear();
                object rowsObject;
                if (data.TryGetValue("Results", out rowsObject) && rowsObject is IEnumerable) foreach (var item in (IEnumerable)rowsObject)
                {
                    var row = item as Dictionary<string, object>; if (row == null) continue;
                    cards.Children.Add(Card(row));
                }
            }
            DateTimeOffset time;
            report.Text = "Lần đo: " + (DateTimeOffset.TryParse(at, out time) ? time.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss") : at) + (staleReport ? " · cấu hình đã thay đổi, bấm Kiểm tra để đo lại" : " · kết quả web, chưa xác nhận chức năng trong game");
        }

        static UIElement Card(Dictionary<string, object> row)
        {
            string host = Backend.Text(row, "Host"), service = host, dns = Backend.Text(row, "DNS");
            if (host == "store.steampowered.com") service = "Steam Store"; else if (host == "steamcommunity.com") service = "Community";
            else if (host == "help.steampowered.com") service = "Steam Help"; else if (host == "api.steampowered.com") service = "Steam API"; else if (host == "www.microsoft.com") service = "Đối chứng";
            bool pass = Backend.Flag(row, "Pass");
            var badge = new Border { CornerRadius = new CornerRadius(8), Padding = new Thickness(9, 2, 9, 3), VerticalAlignment = VerticalAlignment.Center,
                Background = Hex(pass ? "#173A26" : "#3D1C1C"),
                Child = new TextBlock { Text = pass ? "Đạt" : "Chưa đạt", Foreground = pass ? Green : Red, FontSize = 12, FontWeight = FontWeights.SemiBold } };
            var top = new DockPanel();
            DockPanel.SetDock(badge, Dock.Right); top.Children.Add(badge);
            top.Children.Add(new TextBlock { Text = service, FontSize = 15, FontWeight = FontWeights.SemiBold, Foreground = TextBrush, VerticalAlignment = VerticalAlignment.Center });
            var stack = new StackPanel();
            stack.Children.Add(top);
            stack.Children.Add(new TextBlock { Text = dns.Length > 0 ? dns : "Không phân giải được DNS", Foreground = MutedBrush, FontSize = 12, Margin = new Thickness(0, 8, 0, 10), TextTrimming = TextTrimming.CharacterEllipsis });
            stack.Children.Add(new TextBlock { Foreground = MutedBrush, FontSize = 12,
                Text = "HTTP " + Backend.Text(row, "HTTP") + "  ·  TCP " + Backend.Milliseconds(row, "TcpSeconds") + "  ·  TLS " + Backend.Milliseconds(row, "TlsSeconds") + "  ·  Tổng " + Backend.Milliseconds(row, "TotalSeconds") + " ms" });
            string error = Backend.Text(row, "Error");
            return new Border { Width = 290, Margin = new Thickness(0, 0, 12, 12), Padding = new Thickness(16, 14, 16, 14), CornerRadius = new CornerRadius(12),
                Background = CardBrush, BorderBrush = LineBrush, BorderThickness = new Thickness(1), Child = stack,
                ToolTip = host + "\nIP kết nối: " + Backend.Text(row, "RemoteIP") + (error.Length > 0 ? "\n" + error : "") };
        }
    }
}
