# prepare-ADCS.ps1
# Two-pass workflow:
#   Pass 1: Remove ADCS configuration, uninstall role if possible, purge CA artifacts, request reboot
#   Pass 2: Ensure role binaries exist, configure subordinate CA, and generate CSR
#
# Run elevated:
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\prepare-ADCS.ps1 -KeyAlgorithm ECC_P384
#
# Or:
#   .\prepare-ADCS.ps1 -KeyAlgorithm RSA_4096

<#
.SYNOPSIS
Prepares a Windows AD CS host for subordinate CA enrollment to an offline EJBCA root.

.DESCRIPTION
Runs in two passes:
1) Removes existing AD CS CA artifacts and stores state indicating reboot is required.
2) After reboot, reinstalls/prepares AD CS subordinate CA configuration and generates a CSR.

Default values are defined in the USER DEFAULTS block near the top of this file.
New users should start there and edit values for their environment.

.PARAMETER CaCommonName
Subordinate CA common name used for AD CS setup.

.PARAMETER CADistinguishedNameSuffix
DN suffix appended to the CA common name.

.PARAMETER CAType
AD CS subordinate type. Allowed: StandaloneSubordinateCA, EnterpriseSubordinateCA.

.PARAMETER KeyAlgorithm
Key profile for subordinate CA key generation. Allowed: ECC_P384, RSA_4096.

.PARAMETER WorkRoot
Workspace root used for files and cleanup operations.

.PARAMETER RequestFile
Path for generated subordinate CA certificate request file.

.PARAMETER InfFile
Path for generated INF request template file.

.PARAMETER StateFile
Path for two-pass state tracking JSON file.

.PARAMETER AutoReboot
When set, reboot automatically at the end of pass 1.

.PARAMETER OverwriteExistingKey
When true, remove/replace an existing CA private key container if present.

.PARAMETER ServicingRepairMode
Controls when DISM/SFC servicing repair is executed.
Allowed: Never, OnComponentStoreError, Always.

.PARAMETER DismSourceWim
Optional WIM source path for DISM restore (example: D:\sources\install.wim:1).

.PARAMETER RunSfcAfterDism
When true, run SFC after DISM repair.

.PARAMETER MaxRepairAttempts
Maximum number of repair/reboot cycles before script halts with guidance. Default: 2.

.PARAMETER TranscriptFile
Path for transcript log output. If blank, a timestamped file is created under WorkRoot\logs.

.PARAMETER EnableTranscript
Controls transcript logging. Use -EnableTranscript:$false to disable for one run.

.EXAMPLE
.\prepare-ADCS.ps1
Uses USER DEFAULTS and writes a transcript log.

.EXAMPLE
.\prepare-ADCS.ps1 -KeyAlgorithm RSA_4096 -EnableTranscript:$false
Overrides defaults for a single execution.

.EXAMPLE
.\prepare-ADCS.ps1 -OverwriteExistingKey:$true
Allows replacing an existing key container for the same CA name.

.EXAMPLE
.\prepare-ADCS.ps1 -ServicingRepairMode OnComponentStoreError -DismSourceWim "D:\sources\install.wim:1"
Runs DISM/SFC only when servicing corruption is detected, using explicit media source.
#>

[CmdletBinding()]
param(
    [string]$CaCommonName,
    [string]$CADistinguishedNameSuffix,
    [ValidateSet("StandaloneSubordinateCA","EnterpriseSubordinateCA")]
    [string]$CAType,

    [ValidateSet("ECC_P384","RSA_4096")]
    [string]$KeyAlgorithm,

    [string]$WorkRoot,
    [string]$RequestFile,
    [string]$InfFile,
    [string]$StateFile,
    [switch]$AutoReboot,
    [Nullable[bool]]$OverwriteExistingKey,
    [ValidateSet("Never","OnComponentStoreError","Always")]
    [string]$ServicingRepairMode,
    [string]$DismSourceWim,
    [Nullable[bool]]$RunSfcAfterDism,
    [string]$TranscriptFile,
    [Nullable[bool]]$EnableTranscript
    ,[int]$MaxRepairAttempts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==================== USER DEFAULTS (EDIT THIS BLOCK) ====================
# Update these values for your environment. Command-line parameters always
# override these defaults. Current values are set for JSIGROUP pilot testing.
$Script:UserDefaults = @{
    CaCommonName              = "JSIGROUP Intermediate CA - AD CS - PILOT"
    CADistinguishedNameSuffix = ""                         # CN-only: ADCS2025_SubCA_EE_Profile requires no OU/O suffix
    CAType                    = "StandaloneSubordinateCA"  # Or EnterpriseSubordinateCA
    KeyAlgorithm              = "ECC_P384"                  # Or RSA_4096
    WorkRoot                  = "C:\certs"
    RequestFile               = "C:\certs\subca.req"
    InfFile                   = "C:\certs\subca.inf"
    StateFile                 = "C:\certs\adcs-reset-state.json"
    AutoReboot                = $false
    OverwriteExistingKey      = $true
    ServicingRepairMode       = "OnComponentStoreError"
    DismSourceWim             = ""
    RunSfcAfterDism           = $true
    TranscriptFile            = ""
    EnableTranscript          = $true
    MaxRepairAttempts         = 2
}
# ========================================================================

$Script:ProvidedParameters = @{}
foreach ($k in $PSBoundParameters.Keys) {
    $Script:ProvidedParameters[$k] = $true
}

function Resolve-Setting {
    param(
        [string]$Name,
        $CliValue
    )

    if ($Script:ProvidedParameters.ContainsKey($Name)) {
        return $CliValue
    }
    return $Script:UserDefaults[$Name]
}

function Assert-AllowedValue {
    param(
        [string]$Name,
        [string]$Value,
        [string[]]$Allowed
    )

    if ($Allowed -notcontains $Value) {
        throw "Invalid value '$Value' for $Name. Allowed values: $($Allowed -join ', ')."
    }
}

$CaCommonName = [string](Resolve-Setting -Name "CaCommonName" -CliValue $CaCommonName)
$CADistinguishedNameSuffix = [string](Resolve-Setting -Name "CADistinguishedNameSuffix" -CliValue $CADistinguishedNameSuffix)
$CAType = [string](Resolve-Setting -Name "CAType" -CliValue $CAType)
$KeyAlgorithm = [string](Resolve-Setting -Name "KeyAlgorithm" -CliValue $KeyAlgorithm)
$WorkRoot = [string](Resolve-Setting -Name "WorkRoot" -CliValue $WorkRoot)
$RequestFile = [string](Resolve-Setting -Name "RequestFile" -CliValue $RequestFile)
$InfFile = [string](Resolve-Setting -Name "InfFile" -CliValue $InfFile)
$StateFile = [string](Resolve-Setting -Name "StateFile" -CliValue $StateFile)
$ServicingRepairMode = [string](Resolve-Setting -Name "ServicingRepairMode" -CliValue $ServicingRepairMode)
$DismSourceWim = [string](Resolve-Setting -Name "DismSourceWim" -CliValue $DismSourceWim)
$TranscriptFile = [string](Resolve-Setting -Name "TranscriptFile" -CliValue $TranscriptFile)
if ($Script:ProvidedParameters.ContainsKey("MaxRepairAttempts")) {
    $RepairAttemptLimit = [int]$MaxRepairAttempts
} else {
    $RepairAttemptLimit = [int]$Script:UserDefaults.MaxRepairAttempts
}
if ($Script:ProvidedParameters.ContainsKey("AutoReboot")) {
    $ShouldAutoReboot = [bool]$AutoReboot
} else {
    $ShouldAutoReboot = [bool]$Script:UserDefaults.AutoReboot
}

if ($Script:ProvidedParameters.ContainsKey("OverwriteExistingKey")) {
    $ShouldOverwriteExistingKey = [bool]$OverwriteExistingKey
} else {
    $ShouldOverwriteExistingKey = [bool]$Script:UserDefaults.OverwriteExistingKey
}

if ($Script:ProvidedParameters.ContainsKey("RunSfcAfterDism")) {
    $ShouldRunSfcAfterDism = [bool]$RunSfcAfterDism
} else {
    $ShouldRunSfcAfterDism = [bool]$Script:UserDefaults.RunSfcAfterDism
}

if ($Script:ProvidedParameters.ContainsKey("EnableTranscript")) {
    $ShouldEnableTranscript = [bool]$EnableTranscript
} else {
    $ShouldEnableTranscript = [bool]$Script:UserDefaults.EnableTranscript
}

if ([string]::IsNullOrWhiteSpace($TranscriptFile)) {
    $TranscriptFile = Join-Path -Path $WorkRoot -ChildPath ("logs\prepare-ADCS-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

Assert-AllowedValue -Name "CAType" -Value $CAType -Allowed @("StandaloneSubordinateCA","EnterpriseSubordinateCA")
Assert-AllowedValue -Name "KeyAlgorithm" -Value $KeyAlgorithm -Allowed @("ECC_P384","RSA_4096")
Assert-AllowedValue -Name "ServicingRepairMode" -Value $ServicingRepairMode -Allowed @("Never","OnComponentStoreError","Always")

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "== $Message ==" -ForegroundColor Green
}

function Request-OperatorReboot {
    param(
        [string]$Reason,
        [int]$CountdownSeconds = 10
    )

    Write-Warn "A reboot is recommended: $Reason"

    if ($ShouldAutoReboot) {
        Write-Info "AutoReboot is enabled. Rebooting in $CountdownSeconds seconds..."
        Start-Sleep -Seconds $CountdownSeconds
        Restart-Computer -Force
        return
    }

    try {
        while ($true) {
            $answer = [string](Read-Host "Do you want to reboot this server now? (Y/N)")
            $normalized = $answer.Trim().ToLowerInvariant()

            if ($normalized -match '(^|\W)y(es)?(\W|$)') {
                Write-Info "Operator approved reboot. Restarting now..."
                Restart-Computer -Force
                break
            }

            if ($normalized -match '(^|\W)n(o)?(\W|$)') {
                Write-Info "Operator declined immediate reboot. Please reboot before rerunning this script."
                break
            }

            Write-Warn "Response not recognized. Enter Y/Yes or N/No."
        }
    } catch {
        Write-Warn "Could not prompt for reboot interactively. Reboot manually before rerunning this script."
    }
}

function Remove-MachineCngKeyIfPresent {
    param(
        [string]$KeyName,
        [string]$ProviderName = "Microsoft Software Key Storage Provider"
    )

    if ([string]::IsNullOrWhiteSpace($KeyName)) {
        return
    }

    try {
        $provider = [System.Security.Cryptography.CngProvider]::new($ProviderName)
        $options = [System.Security.Cryptography.CngKeyOpenOptions]::MachineKey
        $key = [System.Security.Cryptography.CngKey]::Open($KeyName, $provider, $options)
        $key.Delete()
        $key.Dispose()
        Write-Info "Deleted machine CNG key container: $KeyName"
    } catch [System.Security.Cryptography.CryptographicException] {
        Write-Info "No machine CNG key container found for: $KeyName"
    } catch {
        Write-Warn "Unable to delete machine CNG key container '$KeyName': $($_.Exception.Message)"
    }
}

function Start-ExecutionTranscript {
    if (-not $ShouldEnableTranscript) {
        Write-Info "Transcript logging disabled for this run."
        return $false
    }

    $transcriptDir = Split-Path -Parent $TranscriptFile
    if ($transcriptDir) {
        Ensure-Directory -Path $transcriptDir
    }

    try {
        Start-Transcript -Path $TranscriptFile -Append -ErrorAction Stop | Out-Null
        Write-Info "Transcript started: $TranscriptFile"
        return $true
    } catch {
        Write-Warn "Could not start transcript: $($_.Exception.Message)"
        return $false
    }
}

function Stop-ExecutionTranscript {
    param([bool]$Started)

    if (-not $Started) {
        return
    }

    try {
        Stop-Transcript | Out-Null
    } catch {
        Write-Warn "Could not stop transcript cleanly: $($_.Exception.Message)"
    }
}

function Invoke-ServicingRepair {
    param([string]$Reason)

    Write-Step "Component Store Repair"
    Write-Warn "Trigger: $Reason"

    $dismArgs = @("/Online", "/Cleanup-Image", "/RestoreHealth")
    if (-not [string]::IsNullOrWhiteSpace($DismSourceWim)) {
        $dismArgs += "/Source:wim:$DismSourceWim"
        $dismArgs += "/LimitAccess"
        Write-Info "DISM source set to: $DismSourceWim"
    } else {
        Write-Info "No explicit DISM source provided; using default servicing sources."
    }

    Write-Info "Running: DISM $($dismArgs -join ' ')"
    & dism.exe @dismArgs
    $dismExit = $LASTEXITCODE
    if ($dismExit -ne 0) {
        throw "DISM restore failed with exit code $dismExit."
    }
    Write-Info "DISM completed successfully."

    if ($ShouldRunSfcAfterDism) {
        Write-Info "Running: SFC /SCANNOW"
        & sfc.exe /SCANNOW
        $sfcExit = $LASTEXITCODE
        if ($sfcExit -ne 0) {
            throw "SFC failed with exit code $sfcExit."
        }
        Write-Info "SFC completed successfully."
    } else {
        Write-Info "RunSfcAfterDism disabled; skipping SFC."
    }
}

function Assert-Elevation {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated PowerShell session."
    }
}

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Save-State([string]$Stage) {
    $stateDir = Split-Path -Parent $StateFile
    if ($stateDir) {
        Ensure-Directory -Path $stateDir
    }
    $currentState = [PSCustomObject]@{}
    if (Test-Path -LiteralPath $StateFile) {
        try {
            $currentState = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        } catch {}
    }
    
    $currentState | Add-Member -MemberType NoteProperty -Name "Stage" -Value $Stage -Force
    $currentState | Add-Member -MemberType NoteProperty -Name "CaCommonName" -Value $CaCommonName -Force
    $currentState | Add-Member -MemberType NoteProperty -Name "CADistinguishedNameSuffix" -Value $CADistinguishedNameSuffix -Force
    $currentState | Add-Member -MemberType NoteProperty -Name "CAType" -Value $CAType -Force
    $currentState | Add-Member -MemberType NoteProperty -Name "KeyAlgorithm" -Value $KeyAlgorithm -Force
    $currentState | Add-Member -MemberType NoteProperty -Name "RequestFile" -Value $RequestFile -Force
    $currentState | Add-Member -MemberType NoteProperty -Name "UpdatedUtc" -Value (Get-Date).ToUniversalTime().ToString("o") -Force

    if ($null -eq $currentState.PSObject.Properties['RepairAttempts']) { 
        $currentState | Add-Member -MemberType NoteProperty -Name RepairAttempts -Value 0 -Force 
    }
    
    $currentState | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Get-State {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        return $null
    }
    Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
}

function Remove-ItemIfPresent([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-CryptoSettings {
    param([string]$Algorithm)

    switch ($Algorithm) {
        "ECC_P384" {
            return @{
                CryptoProviderName = "ECDSA_P384#Microsoft Software Key Storage Provider"
                KeyLength          = 384
                HashAlgorithmName  = "SHA384"
                InfKeyAlgorithm    = "ECDSA_P384"
                InfHashAlgorithm   = "SHA384"
            }
        }
        "RSA_4096" {
            return @{
                CryptoProviderName = "RSA#Microsoft Software Key Storage Provider"
                KeyLength          = 4096
                HashAlgorithmName  = "SHA256"
                InfKeyAlgorithm    = "RSA"
                InfHashAlgorithm   = "SHA256"
            }
        }
        default {
            throw "Unsupported KeyAlgorithm '$Algorithm'"
        }
    }
}

function Write-SubcaInf {
    param(
        [string]$Path,
        [hashtable]$Crypto
    )

    $subjectString = if ([string]::IsNullOrWhiteSpace($CADistinguishedNameSuffix)) { "CN=$CaCommonName" } else { "CN=$CaCommonName, $CADistinguishedNameSuffix" }

    $inf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "$subjectString"
MachineKeySet = TRUE
Exportable = FALSE
RequestType = PKCS10
ProviderName = "Microsoft Software Key Storage Provider"
KeyAlgorithm = $($Crypto.InfKeyAlgorithm)
HashAlgorithm = $($Crypto.InfHashAlgorithm)
KeyLength = $($Crypto.KeyLength)
KeyUsage = 0x06

[Extensions]
2.5.29.19 = "{critical}{text}"
_basicConstraints = "CA=TRUE&pathlength=0"
"@

    Set-Content -LiteralPath $Path -Value $inf -Encoding ASCII
}

function Remove-MatchingCertificates {
    param(
        [string]$StoreLocationName,
        [string]$StoreName,
        [string]$SubjectNeedle
    )

    $storeLocation = [System.Security.Cryptography.X509Certificates.StoreLocation]::$StoreLocationName
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($StoreName, $storeLocation)
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

    try {
        $matches = @($store.Certificates | Where-Object { $_.Subject -like "*$SubjectNeedle*" })
        foreach ($cert in $matches) {
            Write-Info ("Removing cert from {0}\{1}: {2} [{3}]" -f $StoreLocationName, $StoreName, $cert.Subject, $cert.Thumbprint)

            if ($cert.HasPrivateKey) {
                try {
                    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                    if ($rsa -and $rsa.GetType().FullName -eq "System.Security.Cryptography.RSACng") {
                        $rsa.Key.Delete()
                        Write-Info "Deleted attached RSA CNG key."
                    }
                } catch {
                    Write-Warn "RSA private key delete skipped: $($_.Exception.Message)"
                }

                try {
                    $ecdsa = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey($cert)
                    if ($ecdsa -and $ecdsa.GetType().FullName -eq "System.Security.Cryptography.ECDsaCng") {
                        $ecdsa.Key.Delete()
                        Write-Info "Deleted attached ECDSA CNG key."
                    }
                } catch {
                    Write-Warn "ECDSA private key delete skipped: $($_.Exception.Message)"
                }
            }

            $store.Remove($cert)
        }
    }
    finally {
        $store.Close()
    }
}

function Remove-AdcsConfiguration {
    Write-Step "Stopping certificate services"
    $svc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne "Stopped") {
            Stop-Service -Name CertSvc -Force
        }
        Set-Service -Name CertSvc -StartupType Disabled
        Write-Info "CertSvc stopped and disabled."
    } else {
        Write-Info "CertSvc not present."
    }

    Write-Step "Removing ADCS CA configuration"
    try {
        Import-Module ADCSDeployment -ErrorAction Stop
        if (Get-Command Uninstall-AdcsCertificationAuthority -ErrorAction SilentlyContinue) {
            Uninstall-AdcsCertificationAuthority -Force -ErrorAction Stop
            Write-Info "Uninstall-AdcsCertificationAuthority completed."
        } else {
            Write-Warn "Uninstall-AdcsCertificationAuthority command not available."
        }
    } catch {
        Write-Warn "ADCSDeployment uninstall step skipped or already removed: $($_.Exception.Message)"
    }

    Write-Step "Uninstalling ADCS Windows features"
    Import-Module ServerManager -ErrorAction Stop
    $featureNames = @(
        "ADCS-Cert-Authority",
        "ADCS-Web-Enrollment",
        "ADCS-Enroll-Web-Pol",
        "ADCS-Enroll-Web-Svc",
        "RSAT-ADCS",
        "RSAT-ADCS-Mgmt"
    )

    $installed = @(
        Get-WindowsFeature |
        Where-Object { $_.Name -in $featureNames -and $_.Installed }
    )

    if ($installed.Count -gt 0) {
        $names = $installed.Name
        try {
            Uninstall-WindowsFeature -Name $names -Restart:$false | Out-Null
            Write-Info "Removed features: $($names -join ', ')"
        } catch {
            Write-Warn "Feature removal failed: $($_.Exception.Message)"
            Write-Warn "This often indicates Windows servicing/component-store issues (for example 0x80073701)."
            Write-Warn "Cleanup will continue; repair with DISM/SFC before next full cycle if needed."
        }
    } else {
        Write-Info "No ADCS features currently installed."
    }

    Write-Step "Purging registry and file-system CA artifacts"
    Remove-ItemIfPresent -Path "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
    Remove-ItemIfPresent -Path "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc"
    Remove-ItemIfPresent -Path "$env:windir\System32\CertLog"
    Remove-ItemIfPresent -Path "$env:windir\System32\CertSrv"
    Write-Info "Removed CertSvc registry and CertLog/CertSrv directories if present."

    Write-Step "Removing matching CA certificates and software-backed keys"
    Remove-MatchingCertificates -StoreLocationName LocalMachine -StoreName My   -SubjectNeedle $CaCommonName
    Remove-MatchingCertificates -StoreLocationName LocalMachine -StoreName CA   -SubjectNeedle $CaCommonName
    Remove-MatchingCertificates -StoreLocationName LocalMachine -StoreName Root -SubjectNeedle $CaCommonName
    Remove-MachineCngKeyIfPresent -KeyName $CaCommonName

    Write-Step "Cleaning work folder"
    Ensure-Directory -Path $WorkRoot
    Get-ChildItem -LiteralPath $WorkRoot -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $PSCommandPath } |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

    Save-State -Stage "NeedsReboot"

    Write-Host ""
    Write-Host "Pass 1 complete." -ForegroundColor Green
    Write-Host "Reboot the server now, then run this same script again in an elevated prompt." -ForegroundColor Green
    Request-OperatorReboot -Reason "Pass 1 cleanup completed; pass 2 requires a rebooted host state."
}

function Install-AdcsRoleAndPrepareSubca {
    # Track repair attempts in state file
    $state = Get-State
    if ($null -eq $state) { $state = @{} }
    if ($state.PSObject.Properties['RepairAttempts'] -eq $null) { $state | Add-Member -MemberType NoteProperty -Name RepairAttempts -Value 0 }

    if ($state.PSObject.Properties['RepairAttempts'] -eq $null) { $state | Add-Member -MemberType NoteProperty -Name RepairAttempts -Value 0 }
    if ($state.RepairAttempts -ge $RepairAttemptLimit) {
        Write-Warn "Maximum repair/reboot attempts ($RepairAttemptLimit) reached."
        Write-Host "" -ForegroundColor Yellow
        Write-Host "ADCS role cannot be repaired automatically. Manual intervention is required." -ForegroundColor Yellow
        Write-Host "Try the following steps before rerunning this script:" -ForegroundColor Yellow
        Write-Host "1. Mount the exact Windows Server installation media matching your OS version." -ForegroundColor Yellow
        Write-Host "2. Run: DISM /Online /Cleanup-Image /RestoreHealth /Source:wim:<DriveLetter>:\sources\install.wim:1 /LimitAccess" -ForegroundColor Yellow
        Write-Host "3. Run: SFC /SCANNOW" -ForegroundColor Yellow
        Write-Host "4. Reboot the server." -ForegroundColor Yellow
        Write-Host "5. If this still fails, perform an in-place upgrade/repair install or OS rebuild." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        throw "Halting to prevent endless repair loop. See above for next steps."
    }
    Write-Step "Installing ADCS role binaries"
    Import-Module ServerManager -ErrorAction Stop

    if ($ServicingRepairMode -eq "Always") {
        Invoke-ServicingRepair -Reason "ServicingRepairMode=Always"
    }

    $caFeature = Get-WindowsFeature -Name ADCS-Cert-Authority
    $certSvc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue

    if ($caFeature.Installed -and -not $certSvc) {
        Write-Warn "ADCS feature is marked installed but CertSvc service is missing."
        Write-Info "Attempting in-place ADCS role repair..."

        try {
            Install-WindowsFeature -Name ADCS-Cert-Authority | Out-Null
            $certSvc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue

            if (-not $certSvc) {
                Write-Warn "In-place install did not restore CertSvc."
                Install-WindowsFeature -Name ADCS-Cert-Authority | Out-Null
                $certSvc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
            }
        } catch {
            $repairError = $_.Exception.Message
            if ($repairError -match "0x80073701|referenced assembly could not be found") {
                if ($state.PSObject.Properties['RepairAttempts'] -eq $null) { $state | Add-Member -MemberType NoteProperty -Name RepairAttempts -Value 0 }
                $state.RepairAttempts++
                $state | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
                                if ($ServicingRepairMode -eq "Never") {
                            Request-OperatorReboot -Reason "Component store corruption detected while ServicingRepairMode is Never."
                                        throw @"
Windows component store appears unhealthy (0x80073701), and ServicingRepairMode=Never.
Set ServicingRepairMode to OnComponentStoreError or Always to run DISM/SFC from this script.
"@
                                }

                                Write-Warn "Detected component-store corruption; running servicing repair workflow."
                                Invoke-ServicingRepair -Reason "ADCS role repair hit 0x80073701"

                                Write-Info "Retrying ADCS role repair after servicing repair."
                                Install-WindowsFeature -Name ADCS-Cert-Authority | Out-Null
                                $certSvc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue

                                if (-not $certSvc) {
                                        Write-Warn "CertSvc still missing after retry."
                                    if ($state.PSObject.Properties['RepairAttempts'] -eq $null) { $state | Add-Member -MemberType NoteProperty -Name RepairAttempts -Value 0 }
                                    $state.RepairAttempts++
                                    $state | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
                                    try {
                                        Install-WindowsFeature -Name ADCS-Cert-Authority | Out-Null
                                        $certSvc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
                                    } catch {
                                        Request-OperatorReboot -Reason "ADCS role reinstall failed after DISM/SFC repair."
                                        throw
                                    }
                                }
                        } else {
                                throw
            }
        }

        if (-not $certSvc) {
            if ($state.PSObject.Properties['RepairAttempts'] -eq $null) { $state | Add-Member -MemberType NoteProperty -Name RepairAttempts -Value 0 }
            $state.RepairAttempts++
            $state | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
                        Request-OperatorReboot -Reason "CertSvc remains missing after repair attempts."
            throw "CertSvc service is still missing after ADCS role repair. Run DISM/SFC, reboot, and rerun this script."
        }

        Write-Info "ADCS role repair completed and CertSvc service is present."
    }

    if (-not $caFeature.Installed) {
        Install-WindowsFeature -Name ADCS-Cert-Authority | Out-Null
        Write-Info "Installed ADCS Certification Authority role."
    } else {
        Write-Info "ADCS Certification Authority role is already installed."
    }

    Import-Module ADCSDeployment -ErrorAction Stop

    Write-Step "Preparing C:\certs workspace"
    Ensure-Directory -Path $WorkRoot

    $crypto = Get-CryptoSettings -Algorithm $KeyAlgorithm
    Write-SubcaInf -Path $InfFile -Crypto $crypto
    Write-Info "Created INF template: $InfFile"

    Write-Step "Configuring subordinate CA and generating CSR"
    if ($ShouldOverwriteExistingKey) {
        Remove-MachineCngKeyIfPresent -KeyName $CaCommonName
    } else {
        Write-Info "OverwriteExistingKey is disabled; existing key containers will be preserved."
    }

    $configPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
    if (Test-Path -LiteralPath $configPath) {
        Write-Warn "CA configuration already exists. Skipping Install-AdcsCertificationAuthority."
        Write-Warn "If you intended to rebuild CA config, run pass 1 again (clear state + rerun)."
    } else {
        $requestDir = Split-Path -Parent $RequestFile
        if ($requestDir) {
            Ensure-Directory -Path $requestDir
        }

        $installArgs = @{
            CAType                    = $CAType
            CACommonName              = $CaCommonName
            CryptoProviderName        = $crypto.CryptoProviderName
            KeyLength                 = $crypto.KeyLength
            HashAlgorithmName         = $crypto.HashAlgorithmName
            OutputCertRequestFile     = $RequestFile
            Force                     = $true
        }
        
        if (-not [string]::IsNullOrWhiteSpace($CADistinguishedNameSuffix)) {
            $installArgs.CADistinguishedNameSuffix = $CADistinguishedNameSuffix
        }

        $installCmd = Get-Command Install-AdcsCertificationAuthority -ErrorAction Stop
        if ($ShouldOverwriteExistingKey -and $installCmd.Parameters.ContainsKey("OverwriteExistingKey")) {
            $installArgs.OverwriteExistingKey = $true
        }

        Install-AdcsCertificationAuthority @installArgs

        Write-Info "Generated subordinate CA request: $RequestFile"
    }

    Save-State -Stage "Prepared"

    Write-Step "Preparation complete"
    Write-Info "KeyAlgorithm: $KeyAlgorithm"
    Write-Info "CAType      : $CAType"
    Write-Info "CA Name     : $CaCommonName"
    Write-Info "OverwriteKey: $ShouldOverwriteExistingKey"
    Write-Info "SvcRepair   : $ServicingRepairMode"
    Write-Info "Request file: $RequestFile"
    Write-Info "Next: transfer the request file to EJBCA for signing."
}

Assert-Elevation
Ensure-Directory -Path $WorkRoot
$transcriptStarted = Start-ExecutionTranscript

# ---------------------------------------------------------------------------
# Stage 3 — Install the signed subordinate certificate and start CertSvc
# ---------------------------------------------------------------------------
function Install-SignedCertificate {
    $signedCert = Join-Path $WorkRoot "pilot-sub-from-adcs.cer"

    if (-not (Test-Path -LiteralPath $signedCert)) {
        Write-Warn "Signed certificate not found at: $signedCert"
        Write-Host ""
        Write-Host "ACTION REQUIRED:" -ForegroundColor Yellow
        Write-Host "  Copy the signed certificate from EJBCA to this server and place it at:" -ForegroundColor Yellow
        Write-Host "  $signedCert" -ForegroundColor Cyan
        Write-Host ""
        throw "Halting: signed certificate not present. Copy the file and re-run this script, then choose option 3."
    }

    Write-Step "Installing signed subordinate CA certificate"
    Write-Info "Certificate file: $signedCert"

    $certutilResult = & certutil -installcert "$signedCert" 2>&1
    $certutilExit   = $LASTEXITCODE

    $certutilResult | ForEach-Object { Write-Info "  [certutil] $_" }

    if ($certutilExit -ne 0) {
        throw "certutil -installcert exited with code $certutilExit. See output above."
    }

    Write-Info "Certificate installed successfully."

    Write-Step "Starting CertSvc"
    try {
        Set-Service -Name CertSvc -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name CertSvc -ErrorAction Stop
        Write-Info "CertSvc started and set to Automatic."
    } catch {
        throw "CertSvc failed to start: $($_.Exception.Message)"
    }

    Save-State -Stage "Complete"

    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host "  SUCCESS: Subordinate CA is operational!" -ForegroundColor Green
    Write-Host "  The AD CS service (CertSvc) is running." -ForegroundColor Green
    Write-Host "  Proceed with Phase 3 interoperability tests." -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------
function Get-StageStatus {
    param($StateObj, [bool]$CertFilePresent)

    $stages = @{
        Cleanup   = @{ Done = $false; Hint = "" }
        Prepare   = @{ Done = $false; Hint = "" }
        Install   = @{ Done = $false; Hint = "" }
    }

    if ($StateObj) {
        if ($StateObj.Stage -in @("NeedsReboot", "Prepared", "Complete")) {
            $stages.Cleanup.Done = $true
        }
        if ($StateObj.Stage -in @("Prepared", "Complete")) {
            $stages.Prepare.Done = $true
        }
        if ($StateObj.Stage -eq "Complete") {
            $stages.Install.Done = $true
        }
    }

    # Step 1 hint
    if (-not $stages.Cleanup.Done) {
        $stages.Cleanup.Hint = "  --> Run this step first, then reboot."
    } elseif ($StateObj -and $StateObj.Stage -eq "NeedsReboot") {
        $stages.Cleanup.Hint = "  --> REBOOT REQUIRED before running step 2."
    }

    # Step 2 hint
    if ($stages.Cleanup.Done -and -not $stages.Prepare.Done -and
        ($StateObj -and $StateObj.Stage -ne "NeedsReboot")) {
        $stages.Prepare.Hint = "  --> Run this step to install the role and generate a CSR."
    }

    # Step 3 hint
    if ($stages.Prepare.Done -and -not $stages.Install.Done) {
        if ($CertFilePresent) {
            $stages.Install.Hint = "  --> Signed certificate found. Ready to install!"
        } else {
            $stages.Install.Hint = "  --> Copy pilot-sub-from-adcs.cer to $WorkRoot, then run this step."
        }
    }

    return $stages
}

function Show-Menu {
    param($StateObj)

    $certFile      = Join-Path $WorkRoot "pilot-sub-from-adcs.cer"
    $certPresent   = Test-Path -LiteralPath $certFile
    $stages        = Get-StageStatus -StateObj $StateObj -CertFilePresent $certPresent

    function Checkbox { param([bool]$Done) if ($Done) { return "[X]" } else { return "[ ]" } }
    function StepColor { param([bool]$Done) if ($Done) { return "Green" } else { return "White" } }

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "   AD CS Pilot Setup Wizard" -ForegroundColor Cyan
    if ($StateObj -and $StateObj.Stage) {
        Write-Host "   Current Stage : $($StateObj.Stage)" -ForegroundColor Cyan
    } else {
        Write-Host "   Current Stage : Not started" -ForegroundColor Cyan
    }
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $(Checkbox $stages.Cleanup.Done) 1.  Clean up / reset old AD CS configuration" -ForegroundColor (StepColor $stages.Cleanup.Done)
    if ($stages.Cleanup.Hint) { Write-Host $stages.Cleanup.Hint -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  $(Checkbox $stages.Prepare.Done) 2.  Install ADCS role and generate SubCA CSR" -ForegroundColor (StepColor $stages.Prepare.Done)
    if ($stages.Prepare.Hint) { Write-Host $stages.Prepare.Hint -ForegroundColor Yellow }
    Write-Host ""
    $step3Label = "3.  Install signed certificate and start CertSvc"
    if ($certPresent) {
        Write-Host "  $(Checkbox $stages.Install.Done) $step3Label" -ForegroundColor (StepColor $stages.Install.Done)
        Write-Host "      Certificate : $certFile" -ForegroundColor DarkGray
    } else {
        Write-Host "  $(Checkbox $stages.Install.Done) $step3Label" -ForegroundColor DarkGray
        Write-Host "      (waiting for: $certFile)" -ForegroundColor DarkGray
    }
    if ($stages.Install.Hint) { Write-Host $stages.Install.Hint -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "      4.  Exit"
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host ""

    return Read-Host "Select a step (1-4)"
}

try {
    $state     = Get-State
    $selection = Show-Menu -StateObj $state

    switch ($selection) {
        "1" { Remove-AdcsConfiguration }
        "2" { Install-AdcsRoleAndPrepareSubca }
        "3" { Install-SignedCertificate }
        "4" { Write-Info "Exiting." }
        default { Write-Warn "'$selection' is not a valid option. Please enter 1, 2, 3 or 4." }
    }
}
finally {
    Stop-ExecutionTranscript -Started $transcriptStarted
}