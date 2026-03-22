#Requires -Version 5.0
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Dark title bar on Windows 10 1903+ / Windows 11
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DwmApi {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
}
"@ -ErrorAction SilentlyContinue

# ── State ─────────────────────────────────────────────────────────────────────
$script:reportDir   = "$env:USERPROFILE\Desktop\SystemReport"
$script:scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:outputQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:reportType  = ''

# ── XAML ──────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
  xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
  xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Title="System Report Generator"
  Height="590" Width="680"
  MinHeight="520" MinWidth="580"
  WindowStartupLocation="CenterScreen"
  ResizeMode="CanMinimize"
  Background="#06060f"
  FontFamily="Segoe UI"
  Foreground="#e0e0e0">

  <Grid Margin="26 22 26 18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- HEADER -->
    <StackPanel Grid.Row="0" HorizontalAlignment="Center" Margin="0 0 0 22">
      <TextBlock Text="System Report Generator"
                 FontSize="26" FontWeight="Bold" HorizontalAlignment="Center"
                 Margin="0 0 0 7">
        <TextBlock.Foreground>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#00d4ff" Offset="0"/>
            <GradientStop Color="#7850ff" Offset="1"/>
          </LinearGradientBrush>
        </TextBlock.Foreground>
      </TextBlock>
      <TextBlock x:Name="subTitle"
                 Foreground="#3a3a5a" FontSize="12" HorizontalAlignment="Center"
                 Text="Generate detailed reports about your PC"/>
    </StackPanel>

    <!-- CARDS -->
    <Grid Grid.Row="1" Margin="0 0 0 16">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="14"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- System Report Card -->
      <Border Grid.Column="0" Background="#0d0d22" CornerRadius="14"
              BorderBrush="#1c1c3a" BorderThickness="1" Padding="22 18">
        <StackPanel>
          <TextBlock FontSize="30" FontFamily="Segoe UI Emoji"
                     HorizontalAlignment="Center" Margin="0 0 0 9">&#x1F5A5;</TextBlock>
          <TextBlock Text="System Report" FontSize="14" FontWeight="SemiBold"
                     Foreground="#f0f0f0" HorizontalAlignment="Center" Margin="0 0 0 6"/>
          <TextBlock Foreground="#3d3d5e" FontSize="11" HorizontalAlignment="Center"
                     TextAlignment="Center" TextWrapping="Wrap" Margin="0 0 0 16"
                     Text="Hardware, OS, Security, Storage&#x0A;Network, Battery, BIOS &amp; more"/>
          <Button x:Name="btnSystem" Content="Generate Report"
                  Height="36" Cursor="Hand" FontWeight="SemiBold" FontSize="12"
                  Foreground="#04040c">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border x:Name="bd" CornerRadius="8">
                  <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                      <GradientStop Color="#00d4ff" Offset="0"/>
                      <GradientStop Color="#7850ff" Offset="1"/>
                    </LinearGradientBrush>
                  </Border.Background>
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="bd" Property="Opacity" Value="0.82"/>
                  </Trigger>
                  <Trigger Property="IsEnabled" Value="False">
                    <Setter TargetName="bd" Property="Opacity" Value="0.22"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </StackPanel>
      </Border>

      <!-- Software Report Card -->
      <Border Grid.Column="2" Background="#0d0d22" CornerRadius="14"
              BorderBrush="#1c1c3a" BorderThickness="1" Padding="22 18">
        <StackPanel>
          <TextBlock FontSize="30" FontFamily="Segoe UI Emoji"
                     HorizontalAlignment="Center" Margin="0 0 0 9">&#x1F4E6;</TextBlock>
          <TextBlock Text="Software Report" FontSize="14" FontWeight="SemiBold"
                     Foreground="#f0f0f0" HorizontalAlignment="Center" Margin="0 0 0 6"/>
          <TextBlock Foreground="#3d3d5e" FontSize="11" HorizontalAlignment="Center"
                     TextAlignment="Center" TextWrapping="Wrap" Margin="0 0 0 16"
                     Text="All installed programs with version,&#x0A;publisher, date &amp; live search"/>
          <Button x:Name="btnSoftware" Content="Generate Report"
                  Height="36" Cursor="Hand" FontWeight="SemiBold" FontSize="12"
                  Foreground="#04040c">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border x:Name="bd" CornerRadius="8">
                  <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                      <GradientStop Color="#00d4ff" Offset="0"/>
                      <GradientStop Color="#7850ff" Offset="1"/>
                    </LinearGradientBrush>
                  </Border.Background>
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="bd" Property="Opacity" Value="0.82"/>
                  </Trigger>
                  <Trigger Property="IsEnabled" Value="False">
                    <Setter TargetName="bd" Property="Opacity" Value="0.22"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </StackPanel>
      </Border>
    </Grid>

    <!-- PROGRESS -->
    <Grid x:Name="progressPanel" Grid.Row="2" Margin="0 0 0 12" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Grid Grid.Row="0" Margin="0 0 0 6">
        <TextBlock x:Name="statusText" Foreground="#666" FontSize="11"/>
        <TextBlock x:Name="progressPct" Foreground="#00d4ff" FontSize="11"
                   HorizontalAlignment="Right" FontWeight="Medium"/>
      </Grid>
      <ProgressBar x:Name="progressBar" Grid.Row="1"
                   Height="6" Maximum="100" Value="0" BorderThickness="0">
        <ProgressBar.Style>
          <Style TargetType="ProgressBar">
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ProgressBar">
                  <Grid>
                    <Border Background="#0f0f26" CornerRadius="3" Height="6"/>
                    <Border x:Name="PART_Track" CornerRadius="3" Height="6" Background="Transparent"/>
                    <Border x:Name="PART_Indicator" HorizontalAlignment="Left" CornerRadius="3" Height="6">
                      <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                          <GradientStop Color="#00d4ff" Offset="0"/>
                          <GradientStop Color="#7850ff" Offset="1"/>
                        </LinearGradientBrush>
                      </Border.Background>
                    </Border>
                  </Grid>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </ProgressBar.Style>
      </ProgressBar>
    </Grid>

    <!-- LOG -->
    <Border Grid.Row="3" Background="#070715" CornerRadius="10"
            BorderBrush="#121228" BorderThickness="1" Margin="0 0 0 14">
      <ScrollViewer x:Name="logScroll" VerticalScrollBarVisibility="Auto">
        <TextBox x:Name="logBox"
                 IsReadOnly="True" Background="Transparent" BorderThickness="0"
                 Foreground="#484868"
                 FontFamily="Cascadia Code, Consolas, Courier New"
                 FontSize="11" TextWrapping="Wrap" AcceptsReturn="True"
                 Margin="14" CaretBrush="Transparent"
                 SelectionBrush="#00d4ff"
                 Text="Ready - click Generate Report above to begin."/>
      </ScrollViewer>
    </Border>

    <!-- OPEN BUTTONS -->
    <Grid Grid.Row="4">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="10"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="btnOpenSystem" Grid.Column="0"
              Content="Open System Report"
              Height="34" Cursor="Hand" FontSize="12" IsEnabled="False">
        <Button.Template>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="9" Background="#0a0a1c"
                    BorderBrush="#1c1c3a" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="#00d4ff"/>
                <Setter Property="Foreground" Value="#00d4ff"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#252540"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#101022"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Button.Template>
      </Button>
      <Button x:Name="btnOpenSoftware" Grid.Column="2"
              Content="Open Software Report"
              Height="34" Cursor="Hand" FontSize="12" IsEnabled="False">
        <Button.Template>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="9" Background="#0a0a1c"
                    BorderBrush="#1c1c3a" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="#00d4ff"/>
                <Setter Property="Foreground" Value="#00d4ff"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#252540"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#101022"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Button.Template>
      </Button>
    </Grid>

  </Grid>
</Window>
'@

# ── Load window ───────────────────────────────────────────────────────────────
$reader             = New-Object System.Xml.XmlNodeReader($xaml)
$script:window      = [System.Windows.Markup.XamlReader]::Load($reader)

$script:btnSystem        = $script:window.FindName('btnSystem')
$script:btnSoftware      = $script:window.FindName('btnSoftware')
$script:btnOpenSystem    = $script:window.FindName('btnOpenSystem')
$script:btnOpenSoftware  = $script:window.FindName('btnOpenSoftware')
$script:progressPanel    = $script:window.FindName('progressPanel')
$script:progressBar      = $script:window.FindName('progressBar')
$script:progressPct      = $script:window.FindName('progressPct')
$script:statusText       = $script:window.FindName('statusText')
$script:logBox           = $script:window.FindName('logBox')
$script:logScroll        = $script:window.FindName('logScroll')

# Personalise subtitle
$script:window.FindName('subTitle').Text = "Computer: $env:COMPUTERNAME   User: $env:USERNAME"

# Dark title bar
$script:window.Add_SourceInitialized({
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
        $v = 1
        [DwmApi]::DwmSetWindowAttribute($hwnd, 20, [ref]$v, 4) | Out-Null
    } catch {}
})

# ── DispatcherTimer — drains the output queue on the UI thread ────────────────
# NOTE: ShowDialog() blocks the calling thread, so .NET event handlers
# (add_OutputDataReceived etc.) never run. We use a Runspace to read stdout
# on a background thread and push lines into a ConcurrentQueue. The
# DispatcherTimer runs on the WPF dispatcher (UI thread) and safely drains it.

$script:drainTimer          = New-Object System.Windows.Threading.DispatcherTimer
$script:drainTimer.Interval = [TimeSpan]::FromMilliseconds(100)

$script:drainTimer.Add_Tick({
    $line = $null
    while ($script:outputQueue.TryDequeue([ref]$line)) {

        if ($line -eq '__DONE__') {
            $script:drainTimer.Stop()
            $script:progressBar.Value = 100
            $script:progressPct.Text  = '100%'
            $script:statusText.Text   = 'Done'
            $script:logBox.AppendText("`n[OK] Report saved to: $script:reportDir`n")
            $script:logScroll.ScrollToBottom()
            $script:btnSystem.IsEnabled   = $true
            $script:btnSoftware.IsEnabled = $true
            if ($script:reportType -eq 'system') {
                $script:btnOpenSystem.IsEnabled = $true
            } else {
                $script:btnOpenSoftware.IsEnabled = $true
            }
            break
        }

        # Strip ANSI colour codes that powershell.exe may emit
        $clean = ($line -replace '\x1b\[[0-9;]*[mGKHFABCDJ]', '').Trim()
        if ($clean) {
            $script:logBox.AppendText($clean + "`n")
            $script:logScroll.ScrollToBottom()
            $script:statusText.Text = $clean

            # Parse [n/m] step markers for progress (e.g. "[2/6]")
            if ($clean -match '\[(\d+)/(\d+)\]') {
                $pct = [math]::Round([int]$Matches[1] / [int]$Matches[2] * 88)
                $script:progressBar.Value = $pct
                $script:progressPct.Text  = "$pct%"
            }
        }
    }
})

# ── Start-Report ──────────────────────────────────────────────────────────────
function Start-Report ([string]$type) {
    $scriptFile = if ($type -eq 'system') { 'SystemReport.ps1' } else { 'SoftwareReport.ps1' }
    $scriptPath = Join-Path $script:scriptDir $scriptFile

    if (-not (Test-Path $scriptPath)) {
        [System.Windows.MessageBox]::Show(
            "Script not found:`n$scriptPath", 'Error',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error)
        return
    }

    $script:reportType  = $type
    $script:outputQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    # Reset UI
    $script:logBox.Text                 = ''
    $script:progressBar.Value           = 0
    $script:progressPct.Text            = '0%'
    $script:statusText.Text             = 'Starting...'
    $script:progressPanel.Visibility    = 'Visible'
    $script:btnSystem.IsEnabled         = $false
    $script:btnSoftware.IsEnabled       = $false

    # Capture references — these are passed into the runspace via SetVariable,
    # so the runspace thread can safely enqueue without touching PowerShell state.
    $capturedQueue = $script:outputQueue
    $capturedPath  = $scriptPath

    # Runspace runs on its own thread, spawns powershell.exe, reads its stdout
    # synchronously, and pushes lines into the ConcurrentQueue.
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('queue', $capturedQueue)
    $rs.SessionStateProxy.SetVariable('scriptPath', $capturedPath)

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript({
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName               = 'powershell.exe'
            $psi.Arguments              = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true

            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            $proc.Start() | Out-Null

            while (-not $proc.StandardOutput.EndOfStream) {
                $ln = $proc.StandardOutput.ReadLine()
                if ($null -ne $ln) { $queue.Enqueue($ln) }
            }
            $proc.WaitForExit()
        } finally {
            $queue.Enqueue('__DONE__')
        }
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
    $script:drainTimer.Start()
}

# ── Button handlers ───────────────────────────────────────────────────────────
$script:btnSystem.Add_Click({   Start-Report 'system'   })
$script:btnSoftware.Add_Click({ Start-Report 'software' })

$script:btnOpenSystem.Add_Click({
    $f = Join-Path $script:reportDir 'SystemReport.html'
    if (Test-Path $f) { Start-Process $f }
})
$script:btnOpenSoftware.Add_Click({
    $f = Join-Path $script:reportDir 'SoftwareReport.html'
    if (Test-Path $f) { Start-Process $f }
})

# Enable open buttons if reports already exist
if (Test-Path (Join-Path $script:reportDir 'SystemReport.html'))   { $script:btnOpenSystem.IsEnabled   = $true }
if (Test-Path (Join-Path $script:reportDir 'SoftwareReport.html')) { $script:btnOpenSoftware.IsEnabled = $true }

# ── Show ──────────────────────────────────────────────────────────────────────
$script:window.ShowDialog() | Out-Null
