$ErrorActionPreference = 'SilentlyContinue'

$reportDir  = "$env:USERPROFILE\Desktop\SystemReport"
$reportFile = "$reportDir\SoftwareReport.html"

if (!(Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "    SOFTWARE REPORT GENERATOR  v1.0" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [1/3] Collecting installed software..."

# ---- Collect all installed software ----
$software = @()
try {
    $software = Get-ItemProperty `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, EstimatedSize |
        Sort-Object DisplayName -Unique
} catch {}

$totalCount  = $software.Count
$reportDate  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$compName    = $env:COMPUTERNAME

Write-Host "  [2/3] Found $totalCount programs. Building report..."

# ---- Build software rows ----
$softwareRows = ''
$index = 1
foreach ($s in $software) {
    $iDate   = if ($s.InstallDate -and $s.InstallDate.Length -ge 8) {
        try { [datetime]::ParseExact($s.InstallDate.Substring(0,8),'yyyyMMdd',$null).ToString('yyyy-MM-dd') } catch { $s.InstallDate }
    } else { '-' }

    $sizeMB  = if ($s.EstimatedSize -and $s.EstimatedSize -gt 0) {
        "$([math]::Round($s.EstimatedSize / 1024, 1)) MB"
    } else { '-' }

    $ver     = if ($s.DisplayVersion) { $s.DisplayVersion } else { '-' }
    $pub     = if ($s.Publisher)      { $s.Publisher }      else { '-' }

    $softwareRows += @"
<tr>
  <td class="num">$index</td>
  <td class="name">$($s.DisplayName)</td>
  <td>$ver</td>
  <td>$pub</td>
  <td>$iDate</td>
  <td>$sizeMB</td>
</tr>
"@
    $index++
}

Write-Host "  [3/3] Writing HTML report..."

# ---- HTML ----
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Software Report - $compName</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

* { margin:0; padding:0; box-sizing:border-box; }

body {
    font-family: 'Inter', 'Segoe UI', system-ui, sans-serif;
    background: #06060f;
    color: #e0e0e0;
    padding: 24px;
    line-height: 1.6;
}

body::before {
    content:'';
    position:fixed; top:0; left:0; right:0; bottom:0;
    background:
        radial-gradient(ellipse at 20% 50%, rgba(0,212,255,0.06) 0%, transparent 50%),
        radial-gradient(ellipse at 80% 20%, rgba(120,80,255,0.05) 0%, transparent 50%);
    pointer-events:none; z-index:0;
}

.container { max-width: 1100px; margin: 0 auto; position: relative; z-index:1; }

/* Header */
.header {
    text-align: center;
    padding: 36px 20px 24px;
    margin-bottom: 28px;
}
.header h1 {
    font-size: 30px;
    font-weight: 700;
    background: linear-gradient(135deg, #00d4ff, #7850ff);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
    margin-bottom: 8px;
}
.header .sub { color: #666; font-size: 13px; }
.header .machine-id {
    display: inline-block;
    margin-top: 10px;
    background: rgba(0,212,255,0.08);
    border: 1px solid rgba(0,212,255,0.15);
    padding: 5px 18px;
    border-radius: 20px;
    font-size: 12px;
    color: #00d4ff;
    letter-spacing: 0.5px;
}

/* Stats bar */
.stats {
    display: flex;
    gap: 14px;
    margin-bottom: 22px;
    flex-wrap: wrap;
}
.stat-card {
    background: rgba(18,18,42,0.6);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 12px;
    padding: 16px 22px;
    flex: 1;
    min-width: 140px;
    text-align: center;
    backdrop-filter: blur(10px);
}
.stat-card .stat-val {
    font-size: 28px;
    font-weight: 700;
    color: #00d4ff;
}
.stat-card .stat-lbl {
    font-size: 11px;
    color: #666;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    margin-top: 4px;
}

/* Search & filter bar */
.toolbar {
    display: flex;
    gap: 10px;
    margin-bottom: 18px;
    align-items: center;
    flex-wrap: wrap;
}
.search-wrap {
    flex: 1;
    min-width: 200px;
    position: relative;
}
.search-wrap input {
    width: 100%;
    background: rgba(18,18,42,0.7);
    border: 1px solid rgba(255,255,255,0.08);
    color: #e0e0e0;
    padding: 10px 14px 10px 38px;
    border-radius: 10px;
    font-size: 13px;
    font-family: inherit;
    outline: none;
    transition: border-color 0.2s;
}
.search-wrap input:focus { border-color: rgba(0,212,255,0.4); }
.search-wrap .search-icon {
    position: absolute;
    left: 12px;
    top: 50%;
    transform: translateY(-50%);
    color: #555;
    font-size: 14px;
    pointer-events: none;
}
.toolbar select {
    background: rgba(18,18,42,0.7);
    border: 1px solid rgba(255,255,255,0.08);
    color: #aaa;
    padding: 10px 14px;
    border-radius: 10px;
    font-size: 13px;
    font-family: inherit;
    outline: none;
    cursor: pointer;
}
.toolbar select:focus { border-color: rgba(0,212,255,0.4); }
.count-badge {
    background: rgba(0,212,255,0.1);
    border: 1px solid rgba(0,212,255,0.2);
    color: #00d4ff;
    padding: 8px 16px;
    border-radius: 10px;
    font-size: 12px;
    font-weight: 600;
    white-space: nowrap;
}

/* Table wrapper */
.table-wrap {
    background: rgba(18,18,42,0.5);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 16px;
    overflow: hidden;
    backdrop-filter: blur(10px);
}

table { width:100%; border-collapse:collapse; }

thead th {
    padding: 12px 14px;
    text-align: left;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    color: #888;
    font-weight: 600;
    background: rgba(255,255,255,0.025);
    border-bottom: 1px solid rgba(255,255,255,0.06);
    cursor: pointer;
    user-select: none;
    white-space: nowrap;
}
thead th:hover { color: #00d4ff; }
thead th .sort-arrow { color: #444; margin-left: 4px; font-size: 10px; }
thead th.sort-asc .sort-arrow::after  { content: ' ▲'; color: #00d4ff; }
thead th.sort-desc .sort-arrow::after { content: ' ▼'; color: #00d4ff; }

tbody tr {
    border-bottom: 1px solid rgba(255,255,255,0.03);
    transition: background 0.15s;
}
tbody tr:last-child { border-bottom: none; }
tbody tr:hover { background: rgba(0,212,255,0.04); }
tbody tr.hidden { display: none; }

td {
    padding: 10px 14px;
    font-size: 13px;
    color: #ccc;
    vertical-align: middle;
}
td.num { color: #444; font-size: 11px; width: 40px; text-align: right; padding-right: 8px; }
td.name { color: #f0f0f0; font-weight: 500; }

/* No results row */
.no-results {
    text-align: center;
    padding: 40px;
    color: #555;
    font-size: 14px;
    display: none;
}

/* Print button */
.print-btn {
    position: fixed;
    bottom: 24px; right: 24px;
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
    margin-top: 30px;
    padding: 16px;
    border-top: 1px solid rgba(255,255,255,0.04);
}

/* Animations */
@keyframes fadeUp {
    from { opacity:0; transform:translateY(12px); }
    to   { opacity:1; transform:translateY(0); }
}
.stats, .table-wrap { animation: fadeUp 0.4s ease forwards; opacity:0; }
.stats       { animation-delay: 0.05s; }
.table-wrap  { animation-delay: 0.15s; }

/* Print */
@media print {
    body { background:#fff; color:#333; padding:10px; }
    body::before { display:none; }
    .toolbar, .print-btn { display:none; }
    .table-wrap { background:#fff; border:1px solid #ddd; }
    thead th { background:#f5f5f5; color:#333; }
    td { color:#444; }
    td.name { color:#111; }
    tbody tr.hidden { display:table-row !important; }
}

@media (max-width:700px) {
    .stats { flex-direction: column; }
    td:nth-child(5), th:nth-child(5),
    td:nth-child(6), th:nth-child(6) { display:none; }
}
</style>
</head>
<body>
<div class="container">

<!-- Header -->
<div class="header">
    <h1>&#128230; Installed Software Report</h1>
    <p class="sub">Generated on $reportDate</p>
    <div class="machine-id">$compName</div>
</div>

<!-- Stats -->
<div class="stats">
    <div class="stat-card">
        <div class="stat-val" id="visibleCount">$totalCount</div>
        <div class="stat-lbl">Programs Listed</div>
    </div>
    <div class="stat-card">
        <div class="stat-val" id="pubCount">-</div>
        <div class="stat-lbl">Unique Publishers</div>
    </div>
    <div class="stat-card">
        <div class="stat-val" id="datedCount">-</div>
        <div class="stat-lbl">With Install Date</div>
    </div>
</div>

<!-- Toolbar -->
<div class="toolbar">
    <div class="search-wrap">
        <span class="search-icon">&#128269;</span>
        <input type="text" id="searchInput" placeholder="Search by name, publisher, or version..." oninput="filterTable()">
    </div>
    <select id="pubFilter" onchange="filterTable()">
        <option value="">All Publishers</option>
    </select>
    <div class="count-badge" id="matchBadge">$totalCount results</div>
</div>

<!-- Table -->
<div class="table-wrap">
<table id="softwareTable">
<thead>
<tr>
    <th onclick="sortTable(0)">#<span class="sort-arrow"></span></th>
    <th onclick="sortTable(1)">Name<span class="sort-arrow"></span></th>
    <th onclick="sortTable(2)">Version<span class="sort-arrow"></span></th>
    <th onclick="sortTable(3)">Publisher<span class="sort-arrow"></span></th>
    <th onclick="sortTable(4)">Install Date<span class="sort-arrow"></span></th>
    <th onclick="sortTable(5)">Size<span class="sort-arrow"></span></th>
</tr>
</thead>
<tbody id="tableBody">
$softwareRows
</tbody>
</table>
<div class="no-results" id="noResults">&#128269; No programs match your search.</div>
</div>

<p class="ft">Software Report v1.0 &mdash; $reportDate &mdash; $totalCount programs found</p>
</div>

<button class="print-btn" onclick="window.print()">&#128424; Print / Save PDF</button>

<script>
// ---- Populate publisher filter ----
(function() {
    var rows = document.querySelectorAll('#tableBody tr');
    var pubs = new Set();
    var dated = 0;
    rows.forEach(function(r) {
        var pub = r.cells[3].textContent.trim();
        var dt  = r.cells[4].textContent.trim();
        if (pub && pub !== '-') pubs.add(pub);
        if (dt  && dt  !== '-') dated++;
    });
    document.getElementById('pubCount').textContent  = pubs.size;
    document.getElementById('datedCount').textContent = dated;

    var sel = document.getElementById('pubFilter');
    Array.from(pubs).sort().forEach(function(p) {
        var o = document.createElement('option');
        o.value = p; o.textContent = p;
        sel.appendChild(o);
    });
})();

// ---- Filter ----
function filterTable() {
    var query  = document.getElementById('searchInput').value.toLowerCase();
    var pubVal = document.getElementById('pubFilter').value.toLowerCase();
    var rows   = document.querySelectorAll('#tableBody tr');
    var visible = 0;
    rows.forEach(function(r) {
        var name = r.cells[1].textContent.toLowerCase();
        var ver  = r.cells[2].textContent.toLowerCase();
        var pub  = r.cells[3].textContent.toLowerCase();
        var matchQ   = !query  || name.includes(query)  || ver.includes(query)  || pub.includes(query);
        var matchPub = !pubVal || pub === pubVal;
        if (matchQ && matchPub) { r.classList.remove('hidden'); visible++; }
        else                    { r.classList.add('hidden'); }
    });
    document.getElementById('matchBadge').textContent  = visible + ' result' + (visible !== 1 ? 's' : '');
    document.getElementById('visibleCount').textContent = visible;
    document.getElementById('noResults').style.display  = visible === 0 ? 'block' : 'none';
}

// ---- Sort ----
var sortDir = {};
function sortTable(col) {
    var tbody = document.getElementById('tableBody');
    var rows  = Array.from(tbody.querySelectorAll('tr'));
    var asc   = sortDir[col] !== true;
    sortDir   = {};
    sortDir[col] = asc;

    // Update header arrows
    document.querySelectorAll('thead th').forEach(function(th, i) {
        th.classList.remove('sort-asc','sort-desc');
        if (i === col) th.classList.add(asc ? 'sort-asc' : 'sort-desc');
    });

    rows.sort(function(a, b) {
        var va = a.cells[col].textContent.trim();
        var vb = b.cells[col].textContent.trim();
        // numeric for col 0 (#)
        if (col === 0) { return asc ? +va - +vb : +vb - +va; }
        return asc ? va.localeCompare(vb) : vb.localeCompare(va);
    });
    rows.forEach(function(r) { tbody.appendChild(r); });
}
</script>
</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "    REPORT GENERATED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Report: $reportFile"
Write-Host "  Total:  $totalCount programs found"
Write-Host ""

Start-Process $reportFile
