# System Report Generator

A lightweight Windows PowerShell tool that audits installed software versions and system health to help identify corporate security vulnerabilities.

---

## What It Does

| Report | What's Captured |
|--------|-----------------|
| **Software Report** | Every installed program — name, version, publisher, install date, size. Searchable & sortable HTML. |
| **System Report** | Hardware (CPU/RAM/GPU/Disk), OS, Security (AV, Firewall, UAC, BitLocker, last Windows Update), Network, Battery, BIOS, Startup programs. |

### Why It Matters for Corporate Security
- Instantly see **outdated software versions** that map to known CVEs
- Spot **unlicensed or shadow IT** software
- Verify **security controls** are active: AV, Firewall, UAC, BitLocker
- Check **patch status** via last Windows Update date
- Identify **suspicious startup programs**

---

## Project Structure

```
System_Report/
├── App.ps1               # WPF GUI launcher (dark-theme window)
├── SystemReport.ps1      # Collects hardware + security data → HTML
├── SoftwareReport.ps1    # Collects all installed apps → HTML
├── RunApp.bat            # Double-click launcher for the GUI
├── RunReport.bat         # Direct System Report (no GUI)
├── RunSoftwareReport.bat # Direct Software Report (no GUI)
└── README.md             # This file
```

---

## Requirements

- Windows 10 / 11
- PowerShell 5.0 or later (built-in on Windows 10+)
- No additional software or internet connection required

---

## How to Run

### Option 1 — GUI (Recommended)
Double-click **`RunApp.bat`**

A window opens with two buttons:
- **Generate System Report** — full hardware + security audit
- **Generate Software Report** — complete installed apps list

Click **Open Report** when done to view in your browser.

### Option 2 — Direct (No GUI)
```
RunReport.bat           # Runs system audit directly
RunSoftwareReport.bat   # Runs software audit directly
```

### Output Location
Reports are saved to:
```
%USERPROFILE%\Desktop\SystemReport\
  ├── SystemReport.html
  └── SoftwareReport.html
```

---

## Reading the Reports

### Software Report
| Column | Use |
|--------|-----|
| Name | Application name |
| Version | Compare against vendor's latest — flag outdated installs |
| Publisher | Identify unknown/untrusted vendors |
| Install Date | Spot recently added software |
| Size | Identify large unexpected installs |

Use the **live search bar** to find any app instantly. Use the **Publisher filter** to audit by vendor.

### System Report
Sections include: Hardware Summary · OS Details · Security Status · Storage · Network · Battery · BIOS · Startup Programs · Installed Software

---

## Security Use Cases

1. **Vulnerability Scanning Prep** — Export the Software Report and cross-reference versions against the NVD (National Vulnerability Database) or your org's CMDB.
2. **Compliance Audit** — Verify UAC, Firewall, BitLocker, and AV are all active before a compliance review.
3. **Incident Response** — Check startup programs and recently installed software during a security incident.
4. **Asset Management** — Capture a snapshot of every machine before/after software deployments.

---

## Notes

- All data is collected **locally** — nothing is sent over the network.
- Requires standard user privileges; some fields (BitLocker status) may need elevation.
- Reports are static HTML files — no database or server needed.
