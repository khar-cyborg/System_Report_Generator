$ErrorActionPreference = 'SilentlyContinue'

$reportDir = "$env:USERPROFILE\Desktop\SystemReport"
$reportFile = "$reportDir\SystemReport.html"
$batteryFile = "$reportDir\battery-report.html"

if (!(Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "    SYSTEM REPORT GENERATOR" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host ""

# ---- Battery Report ----
Write-Host "  [1/4] Generating battery report..."
powercfg /batteryreport /output $batteryFile 2>$null

# ---- Collect All Data ----
Write-Host "  [2/4] Collecting hardware info..."

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

Write-Host "  [3/4] Processing details..."

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
$diskRows = ''
foreach ($d in $disks) {
    $totalGB = [math]::Round($d.Size / 1GB, 2)
    $freeGB  = [math]::Round($d.FreeSpace / 1GB, 2)
    $usedPct = if ($d.Size -gt 0) { [math]::Round(($d.Size - $d.FreeSpace) / $d.Size * 100, 1) } else { 0 }
    $barCol  = if ($usedPct -gt 90) { '#ff4444' } elseif ($usedPct -gt 70) { '#ffaa00' } else { '#00d4ff' }
    $diskRows += @"
<tr>
<td>$($d.DeviceID)</td>
<td>$($d.VolumeName)</td>
<td>$($d.FileSystem)</td>
<td>$totalGB</td>
<td>$freeGB</td>
<td>
<div style="background:#1e1e3a;border-radius:4px;height:8px;width:100px;display:inline-block;vertical-align:middle">
<div style="height:100%;width:$usedPct%;background:$barCol;border-radius:4px"></div>
</div> $usedPct%
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

Write-Host "  [4/4] Building HTML report..."

# ---- HTML Template ----
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>System Report - $compName</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #0a0a1a; color: #e0e0e0; padding: 30px; }
.container { max-width: 960px; margin: 0 auto; }
h1 { text-align: center; font-size: 28px; color: #00d4ff; margin-bottom: 5px; }
.sub { text-align: center; color: #888; font-size: 13px; margin-bottom: 30px; }
.sec { background: #12122a; border: 1px solid #1e1e3a; border-radius: 12px; padding: 20px 25px; margin-bottom: 20px; }
.sec h2 { font-size: 18px; color: #00d4ff; border-bottom: 1px solid #1e1e3a; padding-bottom: 10px; margin-bottom: 15px; }
.g { display: grid; grid-template-columns: 1fr 1fr; gap: 10px 30px; }
.i { display: flex; flex-direction: column; padding: 6px 0; }
.i .l { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1px; }
.i .v { font-size: 15px; color: #f0f0f0; margin-top: 2px; word-break: break-word; }
.fw { grid-column: 1 / -1; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; }
th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid #1e1e3a; font-size: 14px; }
th { color: #00d4ff; font-size: 12px; text-transform: uppercase; letter-spacing: 1px; }
.badge { display: inline-block; background: #00d4ff22; color: #00d4ff; padding: 3px 10px; border-radius: 20px; font-size: 12px; }
.btn { display: inline-block; margin-top: 15px; background: #00d4ff; color: #0a0a1a; padding: 10px 25px; border-radius: 8px; text-decoration: none; font-weight: 600; font-size: 14px; }
.btn:hover { background: #00b8d9; }
.ft { text-align: center; color: #555; font-size: 12px; margin-top: 30px; }
</style>
</head>
<body>
<div class="container">

<h1>&#128187; System Report</h1>
<p class="sub">Generated on $reportDate</p>

<div class="sec"><h2>&#127968; Device Overview</h2><div class="g">
<div class="i"><span class="l">Computer Name</span><span class="v">$compName</span></div>
<div class="i"><span class="l">Logged-in User</span><span class="v">$userName</span></div>
<div class="i"><span class="l">Manufacturer</span><span class="v">$mfr</span></div>
<div class="i"><span class="l">Model</span><span class="v">$modelName</span></div>
<div class="i"><span class="l">System Type</span><span class="v">$sysType</span></div>
<div class="i"><span class="l">Serial Number</span><span class="v">$serial</span></div>
</div></div>

<div class="sec"><h2>&#128421; Operating System</h2><div class="g">
<div class="i"><span class="l">OS Name</span><span class="v">$osName</span></div>
<div class="i"><span class="l">Version / Build</span><span class="v">$osVer (Build $osBuild)</span></div>
<div class="i"><span class="l">Architecture</span><span class="v"><span class="badge">$osArch</span></span></div>
<div class="i"><span class="l">Original Install Date</span><span class="v">$installDate</span></div>
<div class="i"><span class="l">Last Boot Time</span><span class="v">$lastBoot</span></div>
<div class="i"><span class="l">System Uptime</span><span class="v">$uptime</span></div>
<div class="i"><span class="l">Antivirus</span><span class="v">$av</span></div>
</div></div>

<div class="sec"><h2>&#9881; Processor</h2><div class="g">
<div class="i fw"><span class="l">Processor</span><span class="v">$cpuName</span></div>
<div class="i"><span class="l">Cores</span><span class="v">$cpuCores</span></div>
<div class="i"><span class="l">Logical Processors</span><span class="v">$cpuThreads</span></div>
<div class="i"><span class="l">Max Clock Speed</span><span class="v">$cpuSpeed MHz</span></div>
</div></div>

<div class="sec"><h2>&#128190; Memory (RAM)</h2><div class="g">
<div class="i"><span class="l">Total RAM</span><span class="v">$ramGB GB</span></div>
</div>
<table><tr><th>Slot</th><th>Manufacturer</th><th>Capacity</th><th>Speed</th></tr>
$ramRows
</table>
</div>

<div class="sec"><h2>&#127912; Graphics</h2><div class="g">
<div class="i fw"><span class="l">GPU(s)</span><span class="v">$gpuList</span></div>
<div class="i"><span class="l">Display Resolution</span><span class="v">$resolution</span></div>
<div class="i"><span class="l">Driver Version</span><span class="v">$gpuDriver</span></div>
</div></div>

<div class="sec"><h2>&#128272; BIOS / Firmware</h2><div class="g">
<div class="i"><span class="l">BIOS Version</span><span class="v">$biosVer</span></div>
<div class="i"><span class="l">BIOS Date</span><span class="v">$biosDate</span></div>
</div></div>

<div class="sec"><h2>&#127760; Network</h2><div class="g">
<div class="i fw"><span class="l">Network Adapter</span><span class="v">$netAdapter</span></div>
<div class="i"><span class="l">IP Address</span><span class="v">$ipAddr</span></div>
<div class="i"><span class="l">MAC Address</span><span class="v">$macAddr</span></div>
</div></div>

<div class="sec"><h2>&#128449; Storage</h2>
<div class="i" style="margin-bottom:10px"><span class="l">Physical Disks</span><span class="v">$physHTML</span></div>
<table><tr><th>Drive</th><th>Label</th><th>File System</th><th>Total (GB)</th><th>Free (GB)</th><th>Usage</th></tr>
$diskRows
</table>
</div>

<div class="sec"><h2>&#128267; Battery</h2>
<p style="color:#aaa;">A detailed battery health report has been generated separately.</p>
<a class="btn" href="battery-report.html" target="_blank">&#128196; Open Battery Report</a>
</div>

<p class="ft">Report generated by SystemReport | $reportDate</p>
</div></body></html>
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
