#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Repairs a broken Windows Component Store and reinstalls AD Certificate Services.

.DESCRIPTION
    Automates the ADCS repair workflow for Windows Server 2022 when installation
    fails with 0x80073701 (ERROR_SXS_ASSEMBLY_MISSING):

      1. Logs the current OS build and documents the environment.
      2. Runs DISM ScanHealth to detect corruption.
      3. Runs DISM RestoreHealth to repair the component store (online or from ISO).
      4. Runs SFC to catch any remaining file-level issues.
      5. Removes any partially installed ADCS features cleanly.
      6. Reinstalls ADCS-Cert-Authority with management tools.
      7. Verifies the installed feature state.
      8. Saves a full transcript log to C:\Temp\phase3-adcs-repair.

.PARAMETER RepairSource
    Optional. Path to install.wim for offline DISM repair.
    Example: "E:\sources\install.wim"
    If omitted, DISM uses Windows Update / WSUS.

.PARAMETER WimIndex
    Index within the WIM file to use (default: 1).

.PARAMETER SkipRepair
    Skip DISM/SFC repair steps and go straight to ADCS reinstall.
    Use only if the component store is already known-good.

.PARAMETER SkipUninstall
    Skip the ADCS uninstall step (use if ADCS is not currently installed).

.EXAMPLE
    # Online repair (Windows Update access required)
    .\Repair-ADCS-Install.ps1

.EXAMPLE
    # Offline repair using a mounted WS2022 ISO on drive E:
    .\Repair-ADCS-Install.ps1 -RepairSource "E:\sources\install.wim"

.EXAMPLE
    # Skip repair, only reinstall ADCS (component store already healthy)
    .\Repair-ADCS-Install.ps1 -SkipRepair

.NOTES
    Run from an elevated PowerShell session.
    A reboot may be required between repair and reinstall steps.
    Tested on Windows Server 2022 (build 20348.x).

    Source location (Linux EJBCA host):
      ~/rootCA/artifacts/Repair-ADCS-Install.ps1

    Referenced in:
      ~/rootCA/Phase-3-Pilot-Testing.md  (Section 2.2)
      ~/rootCA/phase3/Phase-3-Test-Execution-Worksheet.md  (Test 2 preconditions)
#>

[CmdletBinding()]
param(
    [string]$RepairSource = "",
    [int]   $WimIndex     = 1,
    [switch]$SkipRepair,
    [switch]$SkipUninstall,
    [switch]$NoMgmtTools
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Setup - transcript and log directory
# ---------------------------------------------------------------------------
$LogDir         = "C:\Temp\phase3-adcs-repair"
$Timestamp      = (Get-Date -Format "yyyyMMddTHHmmss")
$TranscriptPath = "$LogDir\repair-transcript-$Timestamp.txt"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Start-Transcript -Path $TranscriptPath -Append

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  ADCS Component Store Repair and Reinstall Script"              -ForegroundColor Cyan
Write-Host "  Timestamp : $Timestamp"                                         -ForegroundColor Cyan
Write-Host "  Log dir   : $LogDir"                                            -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "  $Message" -ForegroundColor Yellow
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
}

function Write-OK   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green  }
function Write-Warn { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red    }
function Write-Info { param([string]$m) Write-Host "  [INFO] $m" -ForegroundColor Cyan   }

function Invoke-DismCommand {
    param([string[]]$Arguments)
    Write-Info "Running: DISM $($Arguments -join ' ')"
    $result = & dism.exe @Arguments
    $result | ForEach-Object { Write-Host "    $_" }
    return $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Step 0 - Environment snapshot
# ---------------------------------------------------------------------------
Write-Step "Step 0: Environment Snapshot"

$osInfo  = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$osBuild = "$($osInfo.CurrentBuildNumber).$($osInfo.UBR)"
$osName  = $osInfo.ProductName

Write-Info "OS        : $osName"
Write-Info "Build     : $osBuild"
Write-Info "Hostname  : $env:COMPUTERNAME"
Write-Info "User      : $env:USERDOMAIN\$env:USERNAME"
Write-Info "Transcript: $TranscriptPath"

if ($osInfo.CurrentBuildNumber -ne "20348") {
    Write-Warn "Expected build 20348 (Server 2022) -- got $($osInfo.CurrentBuildNumber). Proceed with caution."
} else {
    Write-OK "Confirmed Windows Server 2022 (build $osBuild)"
}

$pendingXml = "C:\Windows\WinSxS\pending.xml"
if (Test-Path $pendingXml) {
    Write-Warn "pending.xml detected -- a reboot may be required from a prior failed operation."
    Write-Warn "If DISM fails, reboot first and rerun this script."
}

# ---------------------------------------------------------------------------
# Steps 1-3 - DISM and SFC repair
# ---------------------------------------------------------------------------
if (-not $SkipRepair) {

    # Step 1 - ScanHealth
    Write-Step "Step 1: DISM ScanHealth (detecting component store corruption)"
    $scanLog = "$LogDir\dism-scanhealth-$Timestamp.log"
    $rc = Invoke-DismCommand @("/Online", "/Cleanup-Image", "/ScanHealth", "/LogPath:$scanLog")
    if ($rc -eq 0) {
        Write-OK "ScanHealth completed (exit 0). See: $scanLog"
    } else {
        Write-Warn "ScanHealth returned exit code $rc -- corruption likely present. Proceeding to RestoreHealth."
    }

    # Step 2 - RestoreHealth
    Write-Step "Step 2: DISM RestoreHealth (repairing component store)"
    $restoreLog = "$LogDir\dism-restorehealth-$Timestamp.log"

    if ($RepairSource -ne "") {
        if (-not (Test-Path $RepairSource)) {
            Write-Fail "RepairSource not found: $RepairSource"
            Stop-Transcript
            throw "Repair source WIM not found. Mount your WS2022 ISO and rerun with the correct path."
        }
        Write-Info "Using offline repair source: $RepairSource (index $WimIndex)"
        $rc = Invoke-DismCommand @(
            "/Online", "/Cleanup-Image", "/RestoreHealth",
            "/Source:WIM:${RepairSource}:${WimIndex}",
            "/LimitAccess",
            "/LogPath:$restoreLog"
        )
    } else {
        Write-Info "Using Windows Update / WSUS for online repair (no -RepairSource specified)"
        $rc = Invoke-DismCommand @("/Online", "/Cleanup-Image", "/RestoreHealth", "/LogPath:$restoreLog")
    }

    if ($rc -eq 0) {
        Write-OK "RestoreHealth completed successfully. See: $restoreLog"
    } else {
        Write-Fail "RestoreHealth failed (exit $rc). See: $restoreLog"
        Write-Warn "Common causes:"
        Write-Warn "  - No internet access and no -RepairSource provided"
        Write-Warn "  - RepairSource ISO build does not match installed build ($osBuild)"
        Write-Warn "  - Pending reboot is blocking servicing (reboot and rerun)"
        Stop-Transcript
        throw "DISM RestoreHealth failed. Resolve the source issue and rerun."
    }

    # Step 3 - SFC
    Write-Step "Step 3: SFC /scannow (system file integrity check)"
    Write-Info "Running sfc /scannow -- this may take several minutes..."

    $sfcLog    = "$LogDir\sfc-output-$Timestamp.txt"
    $sfcOutput = & sfc /scannow 2>&1
    $sfcOutput | ForEach-Object { Write-Host "    $_" }
    $sfcOutput | Out-File -FilePath $sfcLog -Encoding UTF8
    Write-Info "SFC output saved to: $sfcLog"

    $sfcStr = $sfcOutput -join " "

    if ($sfcStr -match "did not find any integrity violations") {
        Write-OK "SFC: No integrity violations found."
    } elseif ($sfcStr -match "successfully repaired") {
        Write-OK "SFC: Corruption found and repaired."
        Write-Warn "A reboot is recommended before continuing."
        $reboot = Read-Host "Reboot now before reinstalling ADCS? (Y/N)"
        if ($reboot -ieq "Y") {
            Write-Info "Rebooting. After reboot, rerun with: -SkipRepair"
            Stop-Transcript
            Start-Sleep -Seconds 5
            Restart-Computer -Force
            exit
        }
    } elseif ($sfcStr -match "unable to fix") {
        Write-Fail "SFC: Found corruption it could not fix. Review: $sfcLog"
        Write-Info "CBS log location: C:\Windows\Logs\CBS\CBS.log"
        Stop-Transcript
        throw "SFC could not repair all corruption. Manual intervention required."
    } else {
        Write-Info "SFC output did not match known result patterns -- review $sfcLog manually."
    }

} else {
    Write-Step "Steps 1-3: Skipped (-SkipRepair switch set)"
    Write-Info "Assuming component store is healthy. Proceeding to ADCS reinstall."
}

# ---------------------------------------------------------------------------
# Step 4 - Remove existing ADCS features
# ---------------------------------------------------------------------------
Write-Step "Step 4: Removing existing ADCS features (clean slate)"

$adcsFeatures = @(
    "ADCS-Cert-Authority",
    "ADCS-Web-Enrollment",
    "ADCS-Online-Cert",
    "ADCS-Device-Enrollment",
    "ADCS-Enroll-Web-Pol",
    "ADCS-Enroll-Web-Svc",
    "RSAT-ADCS",
    "RSAT-ADCS-Mgmt",
    "RSAT-Online-Responder"
)

if (-not $SkipUninstall) {
    $installedFeatures = $adcsFeatures | Where-Object {
        (Get-WindowsFeature -Name $_).InstallState -in @("Installed", "InstallPending", "RemovalPending")
    }

    if ($installedFeatures.Count -eq 0) {
        Write-Info "No ADCS features currently installed -- skipping uninstall."
    } else {
        Write-Info "Removing: $($installedFeatures -join ', ')"
        try {
            $uninstallResult = Uninstall-WindowsFeature -Name $installedFeatures -Remove -ErrorAction Stop
            if ($uninstallResult.RestartNeeded -eq "Yes") {
                Write-Warn "Uninstall requires a reboot before reinstalling."
                $reboot = Read-Host "Reboot now? (Y/N)"
                if ($reboot -ieq "Y") {
                    Write-Info "Rebooting. After reboot, rerun with: -SkipRepair -SkipUninstall"
                    Stop-Transcript
                    Start-Sleep -Seconds 5
                    Restart-Computer -Force
                    exit
                }
            } else {
                Write-OK "ADCS features removed without requiring immediate reboot."
            }
        } catch {
            Write-Warn "Uninstall encountered an error: $_"
            Write-Info "This may be acceptable if ADCS was not fully installed. Continuing..."
        }
    }
} else {
    Write-Info "-SkipUninstall set -- skipping removal step."
}

# ---------------------------------------------------------------------------
# Step 5 - Install ADCS-Cert-Authority (+ optional management tools)
# ---------------------------------------------------------------------------
Write-Step "Step 5: Installing ADCS-Cert-Authority"

$installArgs = @{
    Name = @("ADCS-Cert-Authority")
    ErrorAction = "Stop"
}

if (-not $NoMgmtTools) {
    Write-Info "Installing: ADCS-Cert-Authority, RSAT-ADCS, RSAT-ADCS-Mgmt"
    $installArgs.Name += "RSAT-ADCS", "RSAT-ADCS-Mgmt"
    $installArgs.IncludeManagementTools = $true
} else {
    Write-Info "Installing: ADCS-Cert-Authority ONLY (-NoMgmtTools specified to avoid RSAT language pack errors)"
}

if ($RepairSource -ne "") {
    $installArgs.Source = "wim:${RepairSource}:${WimIndex}"
    Write-Info "Using feature source: $($installArgs.Source)"
}

try {
    $installResult = Install-WindowsFeature @installArgs

    Write-Info "Install result:"
    Write-Info "  Success       : $($installResult.Success)"
    Write-Info "  RestartNeeded : $($installResult.RestartNeeded)"
    Write-Info "  ExitCode      : $($installResult.ExitCode)"

    if ($installResult.Success) {
        Write-OK "ADCS features installed successfully."
    } else {
        Write-Fail "Install returned Success=False. Check DISM log and CBS.log."
        Stop-Transcript
        throw "ADCS install failed."
    }

    if ($installResult.RestartNeeded -eq "Yes") {
        Write-Warn "A reboot is required to complete the installation."
    }
} catch {
    Write-Fail "Install-WindowsFeature threw an exception: $_"
    Write-Info "DISM log : C:\Windows\Logs\DISM\dism.log"
    Write-Info "CBS log  : C:\Windows\Logs\CBS\CBS.log"
    Stop-Transcript
    throw
}

# ---------------------------------------------------------------------------
# Step 6 - Verify installed state
# ---------------------------------------------------------------------------
Write-Step "Step 6: Verifying installed feature state"

$featureCheck = @("ADCS-Cert-Authority")
if (-not $NoMgmtTools) {
    $featureCheck += "RSAT-ADCS", "RSAT-ADCS-Mgmt"
}
$allGood = $true

foreach ($f in $featureCheck) {
    $feat = Get-WindowsFeature -Name $f
    if ($feat.InstallState -eq "Installed") {
        Write-OK "$f : Installed"
    } else {
        Write-Fail "$f : $($feat.InstallState)"
        $allGood = $false
    }
}

# ---------------------------------------------------------------------------
# Step 7 - Summary and next steps
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Repair and Install Summary"                                      -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if ($allGood) {
    Write-OK "All checked features are installed and healthy."
    Write-Host ""
    Write-Host "  NEXT STEPS (Phase 3 - Pilot Testing):" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. Reboot if RestartNeeded was 'Yes' above."                              -ForegroundColor White
    Write-Host "  2. Open Server Manager -> AD CS -> Configure AD CS."                      -ForegroundColor White
    Write-Host "  3. Choose: 'Subordinate certification authority'"                         -ForegroundColor White
    Write-Host "  4. Save the subordinate CSR, e.g.:"                                      -ForegroundColor White
    Write-Host "       C:\Temp\phase3-adcs-repair\subordinate-csr.req"                      -ForegroundColor Gray
    Write-Host "  5. Verify the CSR before transferring (elevated CMD):"                    -ForegroundColor White
    Write-Host "       certreq -verify C:\Temp\phase3-adcs-repair\subordinate-csr.req"      -ForegroundColor Gray
    Write-Host "  6. Transfer the .req file to your Linux EJBCA host (~/rootCA/):"          -ForegroundColor White
    Write-Host "       scp C:\Temp\phase3-adcs-repair\subordinate-csr.req user@ejbca-host:~/" -ForegroundColor Gray
    Write-Host "  7. On the Linux host, sign the CSR:"                                      -ForegroundColor White
    Write-Host "       ~/rootCA/phase3/phase3-sign-adcs-subordinate-csr.sh \ "              -ForegroundColor Gray
    Write-Host "         --csr ~/subordinate-csr.req \ "                                    -ForegroundColor Gray
    Write-Host "         --ee-profile ADCS2025_SubCA_EE_Profile"                            -ForegroundColor Gray
    Write-Host "  8. Signed cert output (copy back to Windows):"                            -ForegroundColor White
    Write-Host "       ~/rootCA/phase3/pilot-sub-from-adcs.pem  (PEM)"                      -ForegroundColor Gray
    Write-Host "       ~/rootCA/phase3/pilot-sub-from-adcs.cer  (DER - use this on Windows)" -ForegroundColor Gray
    Write-Host "  9. Full procedure: ~/rootCA/phase3/Phase-3-Test-Execution-Worksheet.md"   -ForegroundColor White
    Write-Host ""
} else {
    Write-Fail "One or more features did not reach Installed state."
    Write-Warn "Check: C:\Windows\Logs\DISM\dism.log"
    Write-Warn "Check: C:\Windows\Logs\CBS\CBS.log"
    Write-Warn "If RestartNeeded was Yes, reboot and rerun with -SkipRepair -SkipUninstall"
}

Write-Host ""
Write-Host "  Transcript saved to: $TranscriptPath" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Stop-Transcript
