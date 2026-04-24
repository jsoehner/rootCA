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
    [string]$TranscriptFile,
    [Nullable[bool]]$EnableTranscript
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==================== USER DEFAULTS (EDIT THIS BLOCK) ====================
# Update these values for your environment. Command-line parameters always
# override these defaults. Current values are set for JSIGROUP pilot testing.
$Script:UserDefaults = @{
    CaCommonName              = "JSIGROUP Intermediate CA - AD CS - PILOT"
    CADistinguishedNameSuffix = "O=JSIGROUP,C=CA"
    CAType                    = "StandaloneSubordinateCA"  # Or EnterpriseSubordinateCA
    KeyAlgorithm              = "ECC_P384"                  # Or RSA_4096
    WorkRoot                  = "C:\certs"
    RequestFile               = "C:\certs\subca.req"
    InfFile                   = "C:\certs\subca.inf"
    StateFile                 = "C:\certs\adcs-reset-state.json"
    AutoReboot                = $false
    TranscriptFile            = ""
    EnableTranscript          = $true
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
$TranscriptFile = [string](Resolve-Setting -Name "TranscriptFile" -CliValue $TranscriptFile)
$ShouldAutoReboot = [bool](
    if ($Script:ProvidedParameters.ContainsKey("AutoReboot")) { [bool]$AutoReboot }
    else { [bool]$Script:UserDefaults.AutoReboot }
)
$ShouldEnableTranscript = [bool](
    if ($Script:ProvidedParameters.ContainsKey("EnableTranscript")) { [bool]$EnableTranscript }
    else { [bool]$Script:UserDefaults.EnableTranscript }
)

if ([string]::IsNullOrWhiteSpace($TranscriptFile)) {
    $TranscriptFile = Join-Path -Path $WorkRoot -ChildPath ("logs\prepare-ADCS-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

Assert-AllowedValue -Name "CAType" -Value $CAType -Allowed @("StandaloneSubordinateCA","EnterpriseSubordinateCA")
Assert-AllowedValue -Name "KeyAlgorithm" -Value $KeyAlgorithm -Allowed @("ECC_P384","RSA_4096")

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

    @{
        Stage                    = $Stage
        CaCommonName             = $CaCommonName
        CADistinguishedNameSuffix= $CADistinguishedNameSuffix
        CAType                   = $CAType
        KeyAlgorithm             = $KeyAlgorithm
        RequestFile              = $RequestFile
        UpdatedUtc               = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
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

    $inf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=$CaCommonName, $CADistinguishedNameSuffix"
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
            Uninstall-WindowsFeature -Name $names -IncludeManagementTools -Restart:$false | Out-Null
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

    Write-Step "Cleaning work folder"
    Ensure-Directory -Path $WorkRoot
    Get-ChildItem -LiteralPath $WorkRoot -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $PSCommandPath } |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

    Save-State -Stage "NeedsReboot"

    Write-Host ""
    Write-Host "Pass 1 complete." -ForegroundColor Green
    Write-Host "Reboot the server now, then run this same script again in an elevated prompt." -ForegroundColor Green

    if ($ShouldAutoReboot) {
        Write-Info "Rebooting in 10 seconds..."
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
}

function Install-AdcsRoleAndPrepareSubca {
    Write-Step "Installing ADCS role binaries"
    Import-Module ServerManager -ErrorAction Stop
    Import-Module ADCSDeployment -ErrorAction Stop

    $caFeature = Get-WindowsFeature -Name ADCS-Cert-Authority
    if (-not $caFeature.Installed) {
        Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools | Out-Null
        Write-Info "Installed ADCS Certification Authority role and management tools."
    } else {
        Write-Info "ADCS Certification Authority role is already installed."
    }

    Write-Step "Preparing C:\certs workspace"
    Ensure-Directory -Path $WorkRoot

    $crypto = Get-CryptoSettings -Algorithm $KeyAlgorithm
    Write-SubcaInf -Path $InfFile -Crypto $crypto
    Write-Info "Created INF template: $InfFile"

    Write-Step "Configuring subordinate CA and generating CSR"
    $configPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
    if (Test-Path -LiteralPath $configPath) {
        Write-Warn "CA configuration already exists. Skipping Install-AdcsCertificationAuthority."
        Write-Warn "If you intended to rebuild CA config, run pass 1 again (clear state + rerun)."
    } else {
        $requestDir = Split-Path -Parent $RequestFile
        if ($requestDir) {
            Ensure-Directory -Path $requestDir
        }

        Install-AdcsCertificationAuthority `
            -CAType $CAType `
            -CACommonName $CaCommonName `
            -CADistinguishedNameSuffix $CADistinguishedNameSuffix `
            -CryptoProviderName $crypto.CryptoProviderName `
            -KeyLength $crypto.KeyLength `
            -HashAlgorithmName $crypto.HashAlgorithmName `
            -OutputCertRequestFile $RequestFile `
            -Force

        Write-Info "Generated subordinate CA request: $RequestFile"
    }

    Save-State -Stage "Prepared"

    Write-Step "Preparation complete"
    Write-Info "KeyAlgorithm: $KeyAlgorithm"
    Write-Info "CAType      : $CAType"
    Write-Info "CA Name     : $CaCommonName"
    Write-Info "Request file: $RequestFile"
    Write-Info "Next: transfer the request file to EJBCA for signing."
}

Assert-Elevation
Ensure-Directory -Path $WorkRoot
$transcriptStarted = Start-ExecutionTranscript

try {
    $state = Get-State

    if (-not $state -or $state.Stage -ne "NeedsReboot") {
        Remove-AdcsConfiguration
    } else {
        Install-AdcsRoleAndPrepareSubca
    }
}
finally {
    Stop-ExecutionTranscript -Started $transcriptStarted
}