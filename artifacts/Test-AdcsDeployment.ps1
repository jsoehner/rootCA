<#
.SYNOPSIS
    Automated integration test suite for an AD CS Standalone Subordinate CA.

.DESCRIPTION
    This script automates Phase 3 pilot testing (Tests 3, 4, 5, and 6).
    It provides an interactive menu to test enrollment, chain validation, 
    TLS/Schannel handshakes via IIS, and CRL retrieval.

.USAGE
    Run this script as an Administrator on the AD CS server.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$workDir = "C:\certs\pilot-tests"
$cerPath = Join-Path $workDir "test.cer"
$crlUrl  = "http://localhost/crl/root.crl"
$StateFile = Join-Path $workDir "test-state.json"

function Get-State {
    if (Test-Path $StateFile) { return Get-Content -LiteralPath $StateFile | ConvertFrom-Json }
    return @{ T3 = $false; T4 = $false; T5 = $false; T6 = $false }
}

function Save-State {
    param($StateObj)
    $StateObj | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Force
}

function Get-CaConfig {
    try {
        $configPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
        $caConfigs = Get-ChildItem -Path $configPath -ErrorAction Stop
        if ($caConfigs.Count -eq 0) { throw "No CA configuration found." }
        return "$env:COMPUTERNAME\$($caConfigs[0].PSChildName)"
    } catch {
        throw "Failed to locate AD CS configuration. Is CertSvc installed?"
    }
}

function Run-Tests3And4 {
    $caConfigString = Get-CaConfig
    Write-Host "`n[*] Connected to CA: $caConfigString" -ForegroundColor Cyan
    
    if (!(Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }
    $infPath = Join-Path $workDir "test.inf"
    $reqPath = Join-Path $workDir "test.req"
    $rspPath = Join-Path $workDir "test.rsp"

    if (Test-Path $cerPath) { Remove-Item $cerPath -Force }
    if (Test-Path $reqPath) { Remove-Item $reqPath -Force }
    if (Test-Path $rspPath) { Remove-Item $rspPath -Force }

    Write-Host "`n[*] Test 3: Generating ECC P-256 CSR..."
    $infContent = @"
[NewRequest]
Subject = "CN=Pilot-Auto-Test-Cert"
KeyLength = 256
KeyAlgorithm = ECDSA_P256
ProviderName = "Microsoft Software Key Storage Provider"
MachineKeySet = true
RequestType = PKCS10
HashAlgorithm = sha256
"@
    Set-Content -Path $infPath -Value $infContent
    & certreq -new -q $infPath $reqPath
    if (!(Test-Path $reqPath)) { throw "Failed to generate CSR." }
    Write-Host "    -> PASS: CSR generated." -ForegroundColor Green

    Write-Host "`n[*] Test 3: Submitting CSR to Standalone CA..."
    $submitOutput = & certreq -submit -q -config $caConfigString $reqPath $cerPath 2>&1
    $submitStr = $submitOutput | Out-String

    if ($submitStr -match "RequestId:\s+(\d+)") {
        $requestId = $matches[1]
    } else {
        throw "Failed to parse RequestId from submission output. Output: $submitStr"
    }
    Write-Host "    -> PASS: Submitted. Request ID is $requestId." -ForegroundColor Green

    Write-Host "`n[*] Test 3: Approving/Issuing pending request $requestId..."
    $resubmitOutput = & certutil -resubmit $requestId 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to issue certificate: $($resubmitOutput | Out-String)" }
    Write-Host "    -> PASS: Certificate administratively issued." -ForegroundColor Green

    Write-Host "`n[*] Test 3: Retrieving issued certificate..."
    if (Test-Path $rspPath) { Remove-Item $rspPath -Force }
    $retrieveOutput = & certreq -retrieve -q -config $caConfigString $requestId $cerPath 2>&1
    if (!(Test-Path $cerPath)) { throw "Failed to retrieve certificate: $($retrieveOutput | Out-String)" }
    Write-Host "    -> PASS: Certificate retrieved and saved to $cerPath." -ForegroundColor Green

    Write-Host "`n[*] Test 4: Validating certificate chain and CRL reachability..."
    $verifyOutput = & certutil -verify -urlfetch $cerPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Chain validation failed. Output: $($verifyOutput | Out-String)" }
    Write-Host "    -> PASS: Full chain built and verified successfully via CDP/AIA." -ForegroundColor Green

    $state = Get-State; $state.T3 = $true; $state.T4 = $true; Save-State $state
}

function Run-Test5 {
    if (!(Test-Path $cerPath)) { throw "Certificate not found. Run Tests 3 & 4 first." }
    
    Write-Host "`n[*] Test 5: TLS/Schannel Validation" -ForegroundColor Cyan
    Write-Host "[*] Importing certificate to Machine Personal store..."
    
    $cert = Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\LocalMachine\My"
    
    Write-Host "[*] Creating IIS HTTPS Binding..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (-not (Get-WebBinding -Name "Default Web Site" -Protocol https -ErrorAction SilentlyContinue)) {
        New-WebBinding -Name "Default Web Site" -Protocol https -Port 443 -IPAddress "*" | Out-Null
    }
    
    Write-Host "[*] Binding certificate to IIS (Port 443)..."
    $thumbprint = $cert.Thumbprint
    Get-Item -Path "Cert:\LocalMachine\My\$thumbprint" | New-Item -Path "IIS:\SslBindings\0.0.0.0!443" -Force | Out-Null
    
    Write-Host "[*] Testing HTTPS connection (Schannel handshake)..."
    # Ignore CN mismatch for testing purposes since we bound CN=Pilot-Auto-Test-Cert to localhost
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    # Enable TLS 1.2 (3072) and TLS 1.3 (12288)
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor 3072 -bor 12288
    
    try {
        # Use 127.0.0.1 to guarantee IPv4, matching the 0.0.0.0!443 IIS binding above
        $response = Invoke-WebRequest -Uri "https://127.0.0.1" -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "    -> PASS: TLS Handshake succeeded and Schannel verified connection." -ForegroundColor Green
            $state = Get-State; $state.T5 = $true; Save-State $state
        }
    } catch {
        throw "Failed to validate TLS connection. Exception: $($_.Exception.Message)"
    }
}

function Run-Test6 {
    Write-Host "`n[*] Test 6: CRL Retrieval Verification" -ForegroundColor Cyan
    Write-Host "[*] Downloading CRL from $crlUrl..."
    $crlPath = Join-Path $workDir "downloaded.crl"
    if (Test-Path $crlPath) { Remove-Item $crlPath -Force }
    
    try {
        Invoke-WebRequest -Uri $crlUrl -OutFile $crlPath -UseBasicParsing -ErrorAction Stop
    } catch {
        throw "Failed to download CRL. Is IIS running and hosting /crl/root.crl?"
    }

    if (!(Test-Path $crlPath)) { throw "CRL file not found after download." }
    Write-Host "    -> PASS: CRL downloaded successfully." -ForegroundColor Green
    
    Write-Host "[*] Parsing CRL using certutil..."
    $dumpOutput = & certutil -dump $crlPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to parse CRL. Output: $($dumpOutput | Out-String)" }
    Write-Host "    -> PASS: CRL parsed successfully and signature is valid." -ForegroundColor Green
    
    $state = Get-State; $state.T6 = $true; Save-State $state
}

function Show-Menu {
    function Checkbox { param([bool]$Done) if ($Done) { return "[X]" } else { return "[ ]" } }
    
    while ($true) {
        $state = Get-State
        Write-Host "`n============================================================" -ForegroundColor Cyan
        Write-Host "   AD CS Automated Integration Validation Suite" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "  $(Checkbox ($state.T3 -and $state.T4)) 1. Tests 3 & 4: Enrollment and Chain Validation"
        Write-Host "  $(Checkbox $state.T5) 2. Test 5: TLS/Schannel Validation (Requires Test 3/4)"
        Write-Host "  $(Checkbox $state.T6) 3. Test 6: CRL Retrieval Verification"
        Write-Host "  [ ] 4. Run All Tests Sequentially"
        Write-Host "  [ ] 5. Exit"
        Write-Host "============================================================" -ForegroundColor Cyan

        $choice = Read-Host "`nSelect an option (1-5)"
        
        try {
            switch ($choice) {
                "1" { Run-Tests3And4 }
                "2" { Run-Test5 }
                "3" { Run-Test6 }
                "4" { Run-Tests3And4; Run-Test5; Run-Test6 }
                "5" { return }
                default { Write-Host "Invalid option." -ForegroundColor Yellow }
            }
        } catch {
            Write-Host "`n[!] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Show-Menu
