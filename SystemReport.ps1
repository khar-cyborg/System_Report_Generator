$ErrorActionPreference = 'SilentlyContinue'

$reportDir = "$env:USERPROFILE\Desktop\SystemReport"
$reportFile = "$reportDir\SystemReport.html"
$batteryFile = "$reportDir\battery-report.html"

if (!(Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "    SYSTEM REPORT GENERATOR  v2.0" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host ""

# ---- Battery Report ----
Write-Host "  [1/6] Generating battery report..."
powercfg /batteryreport /output $batteryFile 2>$null

# ---- Collect Core Data ----
Write-Host "  [2/6] Collecting hardware info..."

$cs      = Get-CimInstance Win32_ComputerSystem
$os      = Get-CimInstance Win32_OperatingSystem
$cpu     = Get-CimInstance Win32_Processor | Select-Object -First 1
$bios    = Get-CimInstance Win32_BIOS
$gpus    = Get-CimInstance Win32_VideoController
$disks   = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'
$ramMods = Get-CimInstance Win32_PhysicalMemory
$net     = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled} | Select-Object -First 1

try { $pdisks = Get-PhysicalDisk } catch { $pdisks = $null }
try {
    $av = (Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Select-Object -First 1).displayName
} catch {
    $av = 'Not Detected'
}

# ---- Collect Extended Data ----
Write-Host "  [3/6] Collecting extended system info..."

# Security info
try {
    $firewall = Get-NetFirewallProfile -ErrorAction Stop | Where-Object {$_.Enabled -eq $true} | Select-Object -ExpandProperty Name
    $firewallStatus = if ($firewall) { ($firewall -join ', ') + ' enabled' } else { 'Disabled' }
} catch { $firewallStatus = 'Unknown' }

try {
    $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop).EnableLUA
    $uacStatus = if ($uac -eq 1) { 'Enabled' } else { 'Disabled' }
} catch { $uacStatus = 'Unknown' }

try {
    $bitlocker = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
    $blStatus = if ($bitlocker.ProtectionStatus -eq 'On') { 'On (C:)' } else { 'Off' }
} catch { $blStatus = 'Not Available' }

# Windows Update - last update date
try {
    $lastUpdate = (Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 1)
    $lastUpdateDate = if ($lastUpdate.InstalledOn) { $lastUpdate.InstalledOn.ToString('yyyy-MM-dd') } else { 'Unknown' }
    $lastUpdateKB = $lastUpdate.HotFixID
} catch {
    $lastUpdateDate = 'Unknown'
    $lastUpdateKB = 'N/A'
}

# Startup programs
try {
    $startupItems = Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object Name, Command, Location | Where-Object { $_.Name }
} catch { $startupItems = @() }

# Installed software (all)
try {
    $software = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
                Sort-Object DisplayName |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate -Unique
} catch { $software = @() }

# Audio devices
try {
    $audio = Get-CimInstance Win32_SoundDevice -ErrorAction Stop | Select-Object Name, Status
} catch { $audio = @() }

# USB devices
try {
    $usb = Get-CimInstance Win32_USBControllerDevice -ErrorAction Stop |
           ForEach-Object { [wmi]$_.Dependent } |
           Where-Object { $_.Name } |
           Select-Object Name, DeviceID -First 15
} catch { $usb = @() }

# Power plan
try {
    $powerPlan = (powercfg /getactivescheme 2>$null) -replace '.*:\s*', '' -replace '\s*\(.*', ''
    if (-not $powerPlan) { $powerPlan = 'Unknown' }
} catch { $powerPlan = 'Unknown' }

# Wi-Fi profiles with passwords
try {
    $wifiRaw = netsh wlan show profiles 2>$null
    $wifiProfileNames = ($wifiRaw | Select-String 'All User Profile\s*:\s*(.+)' | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }) | Select-Object -First 20
    $wifiProfiles = @()
    foreach ($wifiName in $wifiProfileNames) {
        $profileDetail = netsh wlan show profile name="$wifiName" key=clear 2>$null
        $passwordLine = $profileDetail | Select-String 'Key Content\s*:\s*(.+)'
        $password = if ($passwordLine) { $passwordLine.Matches.Groups[1].Value.Trim() } else { '<not stored>' }
        $wifiProfiles += [PSCustomObject]@{ Name = $wifiName; Password = $password }
    }
} catch { $wifiProfiles = @() }

# Monitors
try {
    $monitors = Get-CimInstance WmiMonitorID -Namespace root\wmi -ErrorAction Stop | ForEach-Object {
        $name = ($_.UserFriendlyName | Where-Object {$_ -ne 0} | ForEach-Object { [char]$_ }) -join ''
        $mfr  = ($_.ManufacturerName | Where-Object {$_ -ne 0} | ForEach-Object { [char]$_ }) -join ''
        "$mfr $name".Trim()
    }
} catch { $monitors = @() }

# ---- Process Core Data ----
Write-Host "  [4/6] Processing details..."

$compName    = $cs.Name
$userName    = $cs.UserName
$mfr         = $cs.Manufacturer
$modelName   = $cs.Model
$sysType     = $cs.SystemType
$serial      = $bios.SerialNumber
$biosVer     = $bios.SMBIOSBIOSVersion
$biosDate    = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { 'N/A' }
$osName      = $os.Caption
$osVer       = $os.Version
$osBuild     = $os.BuildNumber
$osArch      = $os.OSArchitecture
$installDate = if ($os.InstallDate) { $os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss') } else { 'N/A' }
$lastBoot    = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'N/A' }
$uptime      = if ($os.LastBootUpTime) {
    $ts = New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date)
    "$($ts.Days) days, $($ts.Hours) hrs, $($ts.Minutes) min"
} else { 'N/A' }
$cpuName     = $cpu.Name
$cpuCores    = $cpu.NumberOfCores
$cpuThreads  = $cpu.NumberOfLogicalProcessors
$cpuSpeed    = $cpu.MaxClockSpeed
$ramGB       = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
$gpuList     = ($gpus | ForEach-Object { $_.Name }) -join '<br>'
$gpuDriver   = ($gpus | Select-Object -First 1).DriverVersion
$resH        = ($gpus | Select-Object -First 1).CurrentHorizontalResolution
$resV        = ($gpus | Select-Object -First 1).CurrentVerticalResolution
$resolution  = "$resH x $resV"
$netAdapter  = if ($net) { $net.Description } else { 'N/A' }
$macAddr     = if ($net) { $net.MACAddress } else { 'N/A' }
$ipAddr      = if ($net -and $net.IPAddress) { $net.IPAddress[0] } else { 'N/A' }
$reportDate  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# ---- RAM module rows ----
$ramRows = ''
foreach ($m in $ramMods) {
    $capGB = [math]::Round($m.Capacity / 1GB, 1)
    $spd   = $m.Speed
    $mmfr  = $m.Manufacturer
    $slot  = $m.DeviceLocator
    $ramRows += "<tr><td>$slot</td><td>$mmfr</td><td>$capGB GB</td><td>$spd MHz</td></tr>`n"
}

# ---- Disk rows ----
Write-Host "  [5/6] Building data tables..."
$diskRows = ''
$totalDiskGB = 0
$totalFreeGB = 0
foreach ($d in $disks) {
    $totalGB = [math]::Round($d.Size / 1GB, 2)
    $freeGB  = [math]::Round($d.FreeSpace / 1GB, 2)
    $totalDiskGB += $totalGB
    $totalFreeGB += $freeGB
    $usedPct = if ($d.Size -gt 0) { [math]::Round(($d.Size - $d.FreeSpace) / $d.Size * 100, 1) } else { 0 }
    $barCol  = if ($usedPct -gt 90) { '#ff4757' } elseif ($usedPct -gt 70) { '#ffa502' } else { '#00d4ff' }
    $diskRows += @"
<tr>
<td>$($d.DeviceID)</td>
<td>$($d.VolumeName)</td>
<td>$($d.FileSystem)</td>
<td>$totalGB</td>
<td>$freeGB</td>
<td>
<div class="usage-bar"><div class="usage-fill" style="width:$usedPct%;background:$barCol"></div></div>
<span class="usage-pct">$usedPct%</span>
</td>
</tr>
"@
}

# ---- Physical disks ----
$physHTML = 'N/A'
if ($pdisks) {
    $physHTML = ($pdisks | ForEach-Object {
        "$($_.FriendlyName) ($($_.MediaType), $([math]::Round($_.Size/1GB)) GB)"
    }) -join '<br>'
}

# ---- Startup rows ----
$startupRows = ''
foreach ($s in $startupItems) {
    $cmdShort = if ($s.Command.Length -gt 60) { $s.Command.Substring(0,57) + '...' } else { $s.Command }
    $startupRows += "<tr><td>$($s.Name)</td><td class='cmd-cell'>$cmdShort</td><td>$($s.Location)</td></tr>`n"
}

# ---- Software rows ----
$softwareRows = ''
foreach ($s in $software) {
    $iDate = if ($s.InstallDate) { $s.InstallDate } else { '-' }
    $softwareRows += "<tr><td>$($s.DisplayName)</td><td>$($s.DisplayVersion)</td><td>$($s.Publisher)</td><td>$iDate</td></tr>`n"
}

# ---- Audio rows ----
$audioHTML = ''
if ($audio -and $audio.Count -gt 0) {
    foreach ($a in $audio) {
        $statusBadge = if ($a.Status -eq 'OK') { '<span class="status-ok">OK</span>' } else { '<span class="status-warn">' + $a.Status + '</span>' }
        $audioHTML += "<tr><td>$($a.Name)</td><td>$statusBadge</td></tr>`n"
    }
} else {
    $audioHTML = '<tr><td colspan="2" style="color:#666">No audio devices detected</td></tr>'
}

# ---- USB rows ----
$usbHTML = ''
if ($usb -and $usb.Count -gt 0) {
    foreach ($u in $usb) {
        $usbHTML += "<tr><td>$($u.Name)</td></tr>`n"
    }
} else {
    $usbHTML = '<tr><td style="color:#666">No USB devices detected</td></tr>'
}

# ---- Wi-Fi rows ----
$wifiHTML = ''
if ($wifiProfiles -and $wifiProfiles.Count -gt 0) {
    foreach ($w in $wifiProfiles) {
        $pwdDisplay = if ($w.Password -eq '<not stored>') { '<span style="color:#555;font-style:italic">not stored</span>' } else { "<span class='cmd-cell'>$($w.Password)</span>" }
        $wifiHTML += "<tr><td>$($w.Name)</td><td>$pwdDisplay</td></tr>`n"
    }
} else {
    $wifiHTML = '<tr><td colspan="2" style="color:#666">No saved Wi-Fi profiles</td></tr>'
}

# ---- Monitor list ----
$monitorHTML = if ($monitors -and $monitors.Count -gt 0) { ($monitors -join '<br>') } else { 'N/A' }

# ---- Health summary calculations ----
$overallDiskPct = if ($totalDiskGB -gt 0) { [math]::Round(($totalDiskGB - $totalFreeGB) / $totalDiskGB * 100, 0) } else { 0 }
$diskHealth = if ($overallDiskPct -lt 70) { 'good' } elseif ($overallDiskPct -lt 90) { 'warn' } else { 'crit' }
$ramUsedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
$ramPct = if ($ramGB -gt 0) { [math]::Round($ramUsedGB / $ramGB * 100, 0) } else { 0 }
$ramHealth = if ($ramPct -lt 70) { 'good' } elseif ($ramPct -lt 90) { 'warn' } else { 'crit' }
$uptimeDays = if ($os.LastBootUpTime) { (New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date)).Days } else { 0 }
$uptimeHealth = if ($uptimeDays -lt 7) { 'good' } elseif ($uptimeDays -lt 14) { 'warn' } else { 'crit' }
$securityScore = 0
if ($av -ne 'Not Detected') { $securityScore++ }
if ($firewallStatus -ne 'Disabled' -and $firewallStatus -ne 'Unknown') { $securityScore++ }
if ($uacStatus -eq 'Enabled') { $securityScore++ }
$secHealth = if ($securityScore -eq 3) { 'good' } elseif ($securityScore -ge 2) { 'warn' } else { 'crit' }

Write-Host "  [6/6] Building HTML report..."

# ---- HTML Template ----
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>System Report - $compName</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

* { margin: 0; padding: 0; box-sizing: border-box; }

body {
    font-family: 'Inter', 'Segoe UI', system-ui, sans-serif;
    background: #06060f;
    color: #e0e0e0;
    padding: 20px;
    line-height: 1.6;
}

/* Animated gradient background */
body::before {
    content: '';
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    background:
        radial-gradient(ellipse at 20% 50%, rgba(0, 212, 255, 0.06) 0%, transparent 50%),
        radial-gradient(ellipse at 80% 20%, rgba(120, 80, 255, 0.05) 0%, transparent 50%),
        radial-gradient(ellipse at 50% 80%, rgba(0, 212, 255, 0.03) 0%, transparent 50%);
    pointer-events: none;
    z-index: 0;
}

.container { max-width: 1020px; margin: 0 auto; position: relative; z-index: 1; }

/* Header */
.header {
    text-align: center;
    padding: 40px 20px 30px;
    margin-bottom: 30px;
}
.header h1 {
    font-size: 32px;
    font-weight: 700;
    background: linear-gradient(135deg, #00d4ff, #7850ff);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
    margin-bottom: 8px;
    letter-spacing: -0.5px;
}
.header .sub {
    color: #666;
    font-size: 13px;
    font-weight: 400;
}
.header .machine-id {
    display: inline-block;
    margin-top: 10px;
    background: rgba(0,212,255,0.08);
    border: 1px solid rgba(0,212,255,0.15);
    padding: 5px 16px;
    border-radius: 20px;
    font-size: 12px;
    color: #00d4ff;
    letter-spacing: 0.5px;
}

/* Navigation */
.nav {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    justify-content: center;
    margin-bottom: 30px;
    padding: 0 10px;
}
.nav a {
    display: inline-block;
    padding: 6px 14px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 8px;
    color: #888;
    text-decoration: none;
    font-size: 12px;
    font-weight: 500;
    transition: all 0.2s;
}
.nav a:hover {
    background: rgba(0,212,255,0.1);
    border-color: rgba(0,212,255,0.3);
    color: #00d4ff;
}

/* Health Dashboard */
.health-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 14px;
    margin-bottom: 30px;
}
.health-card {
    background: rgba(18, 18, 42, 0.6);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 14px;
    padding: 20px;
    text-align: center;
    transition: transform 0.2s, border-color 0.2s;
}
.health-card:hover {
    transform: translateY(-2px);
    border-color: rgba(255,255,255,0.12);
}
.health-card .health-icon { font-size: 24px; margin-bottom: 8px; }
.health-card .health-label { font-size: 11px; color: #666; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 6px; }
.health-card .health-value { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
.health-card .health-sub { font-size: 11px; color: #666; }
.health-card.good .health-value { color: #2ed573; }
.health-card.warn .health-value { color: #ffa502; }
.health-card.crit .health-value { color: #ff4757; }
.health-card.good { border-bottom: 2px solid rgba(46,213,115,0.3); }
.health-card.warn { border-bottom: 2px solid rgba(255,165,2,0.3); }
.health-card.crit { border-bottom: 2px solid rgba(255,71,87,0.3); }

/* Sections */
.sec {
    background: rgba(18, 18, 42, 0.5);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 16px;
    padding: 24px 28px;
    margin-bottom: 20px;
    transition: border-color 0.2s;
}
.sec:hover {
    border-color: rgba(255,255,255,0.1);
}
.sec-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    border-bottom: 1px solid rgba(255,255,255,0.06);
    padding-bottom: 14px;
    margin-bottom: 18px;
    cursor: pointer;
    user-select: none;
}
.sec-header h2 {
    font-size: 17px;
    font-weight: 600;
    color: #f0f0f0;
    display: flex;
    align-items: center;
    gap: 10px;
}
.sec-header h2 .sec-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border-radius: 10px;
    font-size: 16px;
}
.sec-header .sec-desc {
    font-size: 12px;
    color: #555;
    font-weight: 400;
}
.sec-header .toggle-icon {
    color: #555;
    font-size: 18px;
    transition: transform 0.3s;
}
.sec.collapsed .sec-body { display: none; }
.sec.collapsed .toggle-icon { transform: rotate(-90deg); }

/* Section icon themes */
.icon-blue { background: rgba(0,212,255,0.12); }
.icon-purple { background: rgba(120,80,255,0.12); }
.icon-green { background: rgba(46,213,115,0.12); }
.icon-orange { background: rgba(255,165,2,0.12); }
.icon-red { background: rgba(255,71,87,0.12); }
.icon-pink { background: rgba(255,107,129,0.12); }
.icon-yellow { background: rgba(255,215,0,0.12); }
.icon-teal { background: rgba(0,206,209,0.12); }

/* Grid layout */
.g { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 30px; }
.i { display: flex; flex-direction: column; padding: 10px 14px; border-radius: 10px; transition: background 0.15s; }
.i:hover { background: rgba(255,255,255,0.02); }
.i .l {
    font-size: 11px;
    color: #666;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    font-weight: 500;
}
.i .v {
    font-size: 15px;
    color: #f0f0f0;
    margin-top: 3px;
    word-break: break-word;
    font-weight: 400;
}
.i .desc {
    font-size: 11px;
    color: #444;
    margin-top: 3px;
    font-style: italic;
    line-height: 1.4;
}
.fw { grid-column: 1 / -1; }

/* Tables */
table { width: 100%; border-collapse: collapse; margin-top: 10px; }
th, td {
    padding: 10px 14px;
    text-align: left;
    border-bottom: 1px solid rgba(255,255,255,0.04);
    font-size: 13px;
}
th {
    color: #888;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    font-weight: 600;
    background: rgba(255,255,255,0.02);
}
td { color: #ccc; }
tr:hover td { background: rgba(255,255,255,0.02); }
.cmd-cell { font-family: 'Cascadia Code', 'Fira Code', monospace; font-size: 11px; color: #888; word-break: break-all; }

/* Usage bar */
.usage-bar {
    display: inline-block;
    background: rgba(255,255,255,0.06);
    border-radius: 4px;
    height: 8px;
    width: 100px;
    vertical-align: middle;
    overflow: hidden;
}
.usage-fill {
    height: 100%;
    border-radius: 4px;
    transition: width 0.5s ease;
}
.usage-pct { font-size: 12px; color: #aaa; margin-left: 8px; }

/* Badges & status */
.badge {
    display: inline-block;
    background: rgba(0,212,255,0.1);
    color: #00d4ff;
    padding: 3px 12px;
    border-radius: 20px;
    font-size: 12px;
    font-weight: 500;
    border: 1px solid rgba(0,212,255,0.15);
}
.status-ok {
    display: inline-block;
    background: rgba(46,213,115,0.1);
    color: #2ed573;
    padding: 2px 10px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 500;
}
.status-warn {
    display: inline-block;
    background: rgba(255,165,2,0.1);
    color: #ffa502;
    padding: 2px 10px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 500;
}
.status-crit {
    display: inline-block;
    background: rgba(255,71,87,0.1);
    color: #ff4757;
    padding: 2px 10px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 500;
}
.status-good { color: #2ed573; }
.status-mid { color: #ffa502; }
.status-bad { color: #ff4757; }

/* Buttons */
.btn {
    display: inline-block;
    margin-top: 15px;
    background: linear-gradient(135deg, #00d4ff, #7850ff);
    color: #fff;
    padding: 10px 25px;
    border-radius: 10px;
    text-decoration: none;
    font-weight: 600;
    font-size: 13px;
    transition: opacity 0.2s, transform 0.2s;
    border: none;
}
.btn:hover { opacity: 0.9; transform: translateY(-1px); }

/* Print button */
.print-btn {
    position: fixed;
    bottom: 24px;
    right: 24px;
    background: rgba(18,18,42,0.9);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255,255,255,0.1);
    color: #aaa;
    padding: 10px 16px;
    border-radius: 12px;
    cursor: pointer;
    font-size: 13px;
    font-family: inherit;
    transition: all 0.2s;
    z-index: 100;
}
.print-btn:hover { border-color: #00d4ff; color: #00d4ff; }

/* Footer */
.ft {
    text-align: center;
    color: #333;
    font-size: 12px;
    margin-top: 40px;
    padding: 20px;
    border-top: 1px solid rgba(255,255,255,0.04);
}

/* Info banner */
.info-banner {
    background: rgba(0,212,255,0.05);
    border: 1px solid rgba(0,212,255,0.1);
    border-radius: 12px;
    padding: 16px 20px;
    margin-bottom: 24px;
    font-size: 13px;
    color: #888;
    line-height: 1.6;
}
.info-banner strong { color: #00d4ff; }

/* Animations */
@keyframes fadeUp {
    from { opacity: 0; transform: translateY(15px); }
    to { opacity: 1; transform: translateY(0); }
}
.sec, .health-card {
    animation: fadeUp 0.4s ease forwards;
    opacity: 0;
}
.sec:nth-child(1) { animation-delay: 0.05s; }
.sec:nth-child(2) { animation-delay: 0.1s; }
.sec:nth-child(3) { animation-delay: 0.15s; }
.sec:nth-child(4) { animation-delay: 0.2s; }
.sec:nth-child(5) { animation-delay: 0.25s; }
.sec:nth-child(6) { animation-delay: 0.3s; }
.sec:nth-child(7) { animation-delay: 0.35s; }
.sec:nth-child(8) { animation-delay: 0.4s; }
.sec:nth-child(9) { animation-delay: 0.45s; }
.sec:nth-child(10) { animation-delay: 0.5s; }
.sec:nth-child(11) { animation-delay: 0.55s; }
.sec:nth-child(12) { animation-delay: 0.6s; }
.sec:nth-child(13) { animation-delay: 0.65s; }
.health-card:nth-child(1) { animation-delay: 0.05s; }
.health-card:nth-child(2) { animation-delay: 0.1s; }
.health-card:nth-child(3) { animation-delay: 0.15s; }
.health-card:nth-child(4) { animation-delay: 0.2s; }

/* Print styles */
@media print {
    body { background: #fff; color: #333; padding: 10px; }
    body::before { display: none; }
    .container { max-width: 100%; }
    .sec { background: #fff; border: 1px solid #ddd; break-inside: avoid; backdrop-filter: none; }
    .sec-header h2 { color: #222; }
    .i .v { color: #333; }
    .i .l { color: #666; }
    .i .desc { color: #999; }
    th { color: #333; background: #f5f5f5; }
    td { color: #444; }
    .nav, .print-btn, .toggle-icon { display: none; }
    .header h1 { -webkit-text-fill-color: #0088aa; }
    .health-card { background: #f9f9f9; backdrop-filter: none; }
    .health-card .health-value { -webkit-text-fill-color: initial; }
    .sec.collapsed .sec-body { display: block !important; }
}

/* Responsive */
@media (max-width: 700px) {
    .g { grid-template-columns: 1fr; }
    .health-grid { grid-template-columns: 1fr 1fr; }
    .nav { gap: 4px; }
    .nav a { padding: 5px 10px; font-size: 11px; }
}
</style>
</head>
<body>

<div class="container">

<!-- Header -->
<div class="header">
    <h1>&#128187; System Report</h1>
    <p class="sub">Generated on $reportDate</p>
    <div class="machine-id">$compName &mdash; $mfr $modelName</div>
</div>

<!-- Info Banner -->
<div class="info-banner">
    <strong>&#128161; New here?</strong> This report shows a complete snapshot of your computer's hardware, software, and security status.
    Each section includes brief descriptions to help you understand what each value means. Click any section header to collapse or expand it.
</div>

<!-- Quick Navigation -->
<div class="nav">
    <a href="#health">Dashboard</a>
    <a href="#device">Device</a>
    <a href="#os">OS</a>
    <a href="#cpu">Processor</a>
    <a href="#ram">Memory</a>
    <a href="#gpu">Graphics</a>
    <a href="#display">Display</a>
    <a href="#storage">Storage</a>
    <a href="#network">Network</a>
    <a href="#security">Security</a>
    <a href="#power">Power</a>
    <a href="#audio">Audio</a>
    <a href="#usb">USB</a>
    <a href="#startup">Startup</a>
    <a href="#software">Software</a>
    <a href="#bios">BIOS</a>
    <a href="#battery">Battery</a>
</div>

<!-- Health Dashboard -->
<div class="health-grid" id="health">
    <div class="health-card $diskHealth">
        <div class="health-icon">&#128449;</div>
        <div class="health-label">Storage</div>
        <div class="health-value">$overallDiskPct%</div>
        <div class="health-sub">used of $([math]::Round($totalDiskGB,0)) GB</div>
    </div>
    <div class="health-card $ramHealth">
        <div class="health-icon">&#128190;</div>
        <div class="health-label">Memory</div>
        <div class="health-value">$ramPct%</div>
        <div class="health-sub">$ramUsedGB of $ramGB GB used</div>
    </div>
    <div class="health-card $uptimeHealth">
        <div class="health-icon">&#9201;</div>
        <div class="health-label">Uptime</div>
        <div class="health-value">$uptimeDays d</div>
        <div class="health-sub">since last reboot</div>
    </div>
    <div class="health-card $secHealth">
        <div class="health-icon">&#128274;</div>
        <div class="health-label">Security</div>
        <div class="health-value">$securityScore/3</div>
        <div class="health-sub">checks passed</div>
    </div>
</div>

<!-- 1. Device Overview -->
<div class="sec" id="device">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-blue">&#127968;</span> Device Overview</h2>
    <span class="sec-desc">Basic identification details about this computer</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i"><span class="l">Computer Name</span><span class="v">$compName</span>
    <span class="desc">The network name assigned to this PC, used to identify it on a local network</span></div>
    <div class="i"><span class="l">Logged-in User</span><span class="v">$userName</span>
    <span class="desc">The Windows account currently signed in</span></div>
    <div class="i"><span class="l">Manufacturer</span><span class="v">$mfr</span>
    <span class="desc">The company that built this computer (e.g., Dell, HP, Lenovo)</span></div>
    <div class="i"><span class="l">Model</span><span class="v">$modelName</span>
    <span class="desc">The specific product model, useful for finding drivers or support</span></div>
    <div class="i"><span class="l">System Type</span><span class="v">$sysType</span>
    <span class="desc">CPU architecture type &mdash; x64 means 64-bit processor</span></div>
    <div class="i"><span class="l">Serial Number</span><span class="v">$serial</span>
    <span class="desc">Unique identifier assigned by the manufacturer, needed for warranty claims</span></div>
</div></div></div>

<!-- 2. Operating System -->
<div class="sec" id="os">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-purple">&#128421;</span> Operating System</h2>
    <span class="sec-desc">Windows version, build info, and system uptime</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i"><span class="l">OS Name</span><span class="v">$osName</span>
    <span class="desc">The edition of Windows installed (Home, Pro, Enterprise, etc.)</span></div>
    <div class="i"><span class="l">Version / Build</span><span class="v">$osVer (Build $osBuild)</span>
    <span class="desc">The version and build number &mdash; important for compatibility and troubleshooting</span></div>
    <div class="i"><span class="l">Architecture</span><span class="v"><span class="badge">$osArch</span></span>
    <span class="desc">64-bit OS can use more than 4 GB RAM and run both 32/64-bit software</span></div>
    <div class="i"><span class="l">Original Install Date</span><span class="v">$installDate</span>
    <span class="desc">When Windows was first installed or last reset on this machine</span></div>
    <div class="i"><span class="l">Last Boot Time</span><span class="v">$lastBoot</span>
    <span class="desc">When the computer was last turned on or restarted</span></div>
    <div class="i"><span class="l">System Uptime</span><span class="v">$uptime</span>
    <span class="desc">How long the PC has been running without a restart. Regular restarts help performance</span></div>
    <div class="i"><span class="l">Antivirus</span><span class="v">$av</span>
    <span class="desc">Active antivirus protection detected by Windows Security Center</span></div>
    <div class="i"><span class="l">Last Windows Update</span><span class="v">$lastUpdateDate ($lastUpdateKB)</span>
    <span class="desc">The most recent Windows patch installed &mdash; keeping updated protects against vulnerabilities</span></div>
</div></div></div>

<!-- 3. Processor -->
<div class="sec" id="cpu">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-orange">&#9881;</span> Processor (CPU)</h2>
    <span class="sec-desc">The brain of your computer &mdash; handles all computing tasks</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i fw"><span class="l">Processor</span><span class="v">$cpuName</span>
    <span class="desc">The CPU model name. Higher generation numbers (e.g., 13th Gen) and i7/i9 tiers mean better performance</span></div>
    <div class="i"><span class="l">Physical Cores</span><span class="v">$cpuCores</span>
    <span class="desc">Number of independent processing units. More cores = better multitasking</span></div>
    <div class="i"><span class="l">Logical Processors (Threads)</span><span class="v">$cpuThreads</span>
    <span class="desc">Virtual cores via hyper-threading. Usually 2x physical cores. More threads help with parallel workloads</span></div>
    <div class="i"><span class="l">Max Clock Speed</span><span class="v">$cpuSpeed MHz</span>
    <span class="desc">Maximum speed in megahertz. Higher = faster single-threaded tasks like gaming</span></div>
</div></div></div>

<!-- 4. Memory (RAM) -->
<div class="sec" id="ram">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-green">&#128190;</span> Memory (RAM)</h2>
    <span class="sec-desc">Short-term memory for running apps &mdash; more RAM means more apps can run simultaneously</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body">
<div class="g">
    <div class="i"><span class="l">Total RAM</span><span class="v">$ramGB GB</span>
    <span class="desc">8 GB is minimum for daily use, 16 GB is recommended, 32+ GB is for heavy workloads</span></div>
    <div class="i"><span class="l">Current Usage</span><span class="v">$ramUsedGB GB ($ramPct%)</span>
    <span class="desc">How much RAM is currently being used. Above 85% may cause slowdowns</span></div>
</div>
<p style="font-size:12px;color:#555;margin-top:14px;">&#128204; <strong style="color:#888">Installed Modules</strong> &mdash; shows each physical RAM stick. Speed in MHz indicates data transfer rate.</p>
<table><tr><th>Slot</th><th>Manufacturer</th><th>Capacity</th><th>Speed</th></tr>
$ramRows
</table>
</div></div>

<!-- 5. Graphics -->
<div class="sec" id="gpu">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-pink">&#127912;</span> Graphics (GPU)</h2>
    <span class="sec-desc">Handles visual rendering &mdash; gaming, video editing, and display output</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i fw"><span class="l">GPU(s)</span><span class="v">$gpuList</span>
    <span class="desc">Graphics processor(s). Dedicated GPUs (NVIDIA/AMD) are much faster than integrated (Intel/AMD APU) for gaming and creative work</span></div>
    <div class="i"><span class="l">Driver Version</span><span class="v">$gpuDriver</span>
    <span class="desc">GPU software version. Keep drivers updated for best performance and compatibility</span></div>
</div></div></div>

<!-- 6. Display -->
<div class="sec" id="display">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-teal">&#128424;</span> Display &amp; Monitors</h2>
    <span class="sec-desc">Screen resolution and connected displays</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i"><span class="l">Display Resolution</span><span class="v">$resolution</span>
    <span class="desc">Current pixel dimensions. 1920x1080 is Full HD, 2560x1440 is QHD, 3840x2160 is 4K</span></div>
    <div class="i"><span class="l">Connected Monitor(s)</span><span class="v">$monitorHTML</span>
    <span class="desc">Physical display devices connected to this computer</span></div>
</div></div></div>

<!-- 7. Storage -->
<div class="sec" id="storage">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-blue">&#128449;</span> Storage</h2>
    <span class="sec-desc">Hard drives and SSDs &mdash; where your files, apps, and OS are permanently stored</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body">
<div class="i" style="margin-bottom:10px"><span class="l">Physical Disks</span><span class="v">$physHTML</span>
<span class="desc">SSD (Solid State Drive) is much faster than HDD (Hard Disk Drive). NVMe SSDs are the fastest type available</span></div>
<p style="font-size:12px;color:#555;margin-top:14px;">&#128204; <strong style="color:#888">Drive Partitions</strong> &mdash; each row is a logical drive. Keep at least 15% free space for best performance.</p>
<table><tr><th>Drive</th><th>Label</th><th>File System</th><th>Total (GB)</th><th>Free (GB)</th><th>Usage</th></tr>
$diskRows
</table>
</div></div>

<!-- 8. Network -->
<div class="sec" id="network">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-purple">&#127760;</span> Network</h2>
    <span class="sec-desc">Network connection details and saved Wi-Fi profiles</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i fw"><span class="l">Network Adapter</span><span class="v">$netAdapter</span>
    <span class="desc">The hardware handling your internet connection (Wi-Fi card or Ethernet adapter)</span></div>
    <div class="i"><span class="l">IP Address</span><span class="v">$ipAddr</span>
    <span class="desc">Your device's address on the local network. Private IPs (192.168.x.x) are not visible on the internet</span></div>
    <div class="i"><span class="l">MAC Address</span><span class="v">$macAddr</span>
    <span class="desc">A unique hardware identifier for your network adapter, sometimes used for network access control</span></div>
</div>
<p style="font-size:12px;color:#555;margin-top:14px;">&#128246; <strong style="color:#888">Saved Wi-Fi Profiles</strong> &mdash; networks your computer remembers and can auto-connect to. Passwords shown in plain text &mdash; keep this report private.</p>
<table><tr><th>Network Name (SSID)</th><th>Password</th></tr>
$wifiHTML
</table>
</div></div>

<!-- 9. Security Overview -->
<div class="sec" id="security">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-red">&#128274;</span> Security Overview</h2>
    <span class="sec-desc">Protection status &mdash; antivirus, firewall, encryption, and access controls</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i"><span class="l">Antivirus</span><span class="v">$av</span>
    <span class="desc">Active antivirus software protecting against malware, viruses, and other threats</span></div>
    <div class="i"><span class="l">Windows Firewall</span><span class="v">$firewallStatus</span>
    <span class="desc">Monitors network traffic and blocks unauthorized connections. Should always be enabled</span></div>
    <div class="i"><span class="l">User Account Control (UAC)</span><span class="v">$uacStatus</span>
    <span class="desc">Prompts for confirmation before apps make system changes. Prevents unauthorized modifications</span></div>
    <div class="i"><span class="l">BitLocker Encryption</span><span class="v">$blStatus</span>
    <span class="desc">Encrypts your entire drive so data can't be read if the computer is stolen</span></div>
</div></div></div>

<!-- 10. Power Plan -->
<div class="sec" id="power">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-yellow">&#9889;</span> Power &amp; Thermal</h2>
    <span class="sec-desc">Active power plan and energy settings</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i"><span class="l">Active Power Plan</span><span class="v">$powerPlan</span>
    <span class="desc">Balanced saves battery, High Performance maximizes speed, Power Saver extends battery life</span></div>
</div></div></div>

<!-- 11. Audio Devices -->
<div class="sec" id="audio">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-pink">&#127925;</span> Audio Devices</h2>
    <span class="sec-desc">Sound cards and audio hardware detected on this system</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body">
<table><tr><th>Device Name</th><th>Status</th></tr>
$audioHTML
</table>
</div></div>

<!-- 12. USB Devices -->
<div class="sec" id="usb">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-teal">&#128268;</span> Connected USB Devices</h2>
    <span class="sec-desc">Currently connected USB peripherals (mice, keyboards, drives, etc.)</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body">
<table><tr><th>Device Name</th></tr>
$usbHTML
</table>
</div></div>

<!-- 13. Startup Programs -->
<div class="sec" id="startup">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-orange">&#128640;</span> Startup Programs</h2>
    <span class="sec-desc">Apps that launch automatically when Windows starts &mdash; too many can slow down boot time</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body">
<p style="font-size:12px;color:#555;margin-bottom:10px;">&#128161; <em>Fewer startup programs = faster boot time. Disable unnecessary ones in Task Manager &gt; Startup tab.</em></p>
<table><tr><th>Program</th><th>Command</th><th>Location</th></tr>
$startupRows
</table>
</div></div>

<!-- 14. Installed Software -->
<div class="sec" id="software">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-green">&#128230;</span> Installed Software</h2>
    <span class="sec-desc">All programs installed on this computer (sorted alphabetically)</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body">
<table><tr><th>Name</th><th>Version</th><th>Publisher</th><th>Install Date</th></tr>
$softwareRows
</table>
</div></div>

<!-- 15. BIOS / Firmware -->
<div class="sec" id="bios">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-yellow">&#128272;</span> BIOS / Firmware</h2>
    <span class="sec-desc">Low-level software that initializes hardware before Windows boots</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body"><div class="g">
    <div class="i"><span class="l">BIOS Version</span><span class="v">$biosVer</span>
    <span class="desc">Firmware version. Updating BIOS can fix hardware bugs but carries risk &mdash; only update if needed</span></div>
    <div class="i"><span class="l">BIOS Release Date</span><span class="v">$biosDate</span>
    <span class="desc">When this BIOS version was released by the manufacturer</span></div>
</div></div></div>

<!-- 16. Battery -->
<div class="sec" id="battery">
<div class="sec-header" onclick="this.parentElement.classList.toggle('collapsed')">
    <div><h2><span class="sec-icon icon-green">&#128267;</span> Battery</h2>
    <span class="sec-desc">Battery health and detailed power consumption report</span></div>
    <span class="toggle-icon">&#9660;</span>
</div>
<div class="sec-body">
<p style="color:#888;font-size:13px;">A detailed battery health report has been generated separately. It shows capacity degradation over time, usage history, and estimated battery life.</p>
<a class="btn" href="battery-report.html" target="_blank">&#128196; Open Battery Report</a>
</div></div>

<!-- Footer -->
<p class="ft">System Report v2.0 &mdash; Generated on $reportDate<br>
<span style="color:#444">This report is a point-in-time snapshot. Values like RAM usage and uptime change continuously.</span></p>

</div>

<!-- Print Button -->
<button class="print-btn" onclick="window.print()" title="Print or save as PDF">&#128424; Print Report</button>

<script>
// Smooth scroll for nav links
document.querySelectorAll('.nav a').forEach(function(a) {
    a.addEventListener('click', function(e) {
        e.preventDefault();
        var target = document.querySelector(this.getAttribute('href'));
        if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
});
</script>

</body></html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "    REPORT GENERATED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Report:  $reportFile"
Write-Host "  Battery: $batteryFile"
Write-Host ""

Start-Process $reportFile
