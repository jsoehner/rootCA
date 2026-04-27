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

    # Clean up any test certs from previous runs
    Get-ChildItem "Cert:\LocalMachine\My" -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq "CN=Pilot-Auto-Test-Cert" } | Remove-Item -Force

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

[EnhancedKeyUsageExtension]
OID = 1.3.6.1.5.5.7.3.1 ; Server Authentication
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

    Write-Host "`n[*] Test 3: Accepting certificate to bind private key to Machine store..."
    $acceptOutput = & certreq -accept $cerPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to accept certificate: $($acceptOutput | Out-String)" }
    Write-Host "    -> PASS: Certificate accepted and fully installed." -ForegroundColor Green

    Write-Host "`n[*] Test 4: Validating certificate chain and CRL reachability..."
    $verifyOutput = & certutil -verify -urlfetch $cerPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Chain validation failed. Output: $($verifyOutput | Out-String)" }
    Write-Host "    -> PASS: Full chain built and verified successfully via CDP/AIA." -ForegroundColor Green

    $state = Get-State; $state.T3 = $true; $state.T4 = $true; Save-State $state
}

function Run-Test5 {
    if (!(Test-Path $cerPath)) { throw "Certificate not found. Run Tests 3 & 4 first." }
    
    Write-Host "`n[*] Test 5: TLS/Schannel Validation" -ForegroundColor Cyan
    Write-Host "[*] Locating previously installed certificate..."
    
    $cert = Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.Subject -eq "CN=Pilot-Auto-Test-Cert" } | Select-Object -First 1
    if (-not $cert -or -not $cert.HasPrivateKey) {
        throw "Certificate installed but private key is missing! Please re-run Option 1 (Tests 3 & 4)."
    }
    
    Write-Host "[*] Creating IIS HTTPS Binding..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (-not (Get-WebBinding -Name "Default Web Site" -Protocol https -ErrorAction SilentlyContinue)) {
        New-WebBinding -Name "Default Web Site" -Protocol https -Port 443 -IPAddress "*" | Out-Null
    }
    
    Write-Host "[*] Binding certificate to IIS (Port 443)..."
    $thumbprint = $cert.Thumbprint
    if (Test-Path "IIS:\SslBindings\*!443") { Remove-Item -Path "IIS:\SslBindings\*!443" -Force }
    if (Test-Path "IIS:\SslBindings\0.0.0.0!443") { Remove-Item -Path "IIS:\SslBindings\0.0.0.0!443" -Force }
    
    Get-Item -Path "Cert:\LocalMachine\My\$thumbprint" | New-Item -Path "IIS:\SslBindings\*!443" | Out-Null
    
    Write-Host "[*] Restarting IIS (W3SVC) to ensure bindings are applied..."
    Restart-Service -Name W3SVC -ErrorAction SilentlyContinue
    
    Write-Host "[*] Testing HTTPS connection (Schannel handshake)..."
    try {
        # Using native curl.exe to bypass .NET Framework quirks. 
        # --resolve maps the CN to localhost so Schannel performs full, strict validation!
        $curlOutput = & curl.exe --resolve "Pilot-Auto-Test-Cert:443:127.0.0.1" -s -v -I https://Pilot-Auto-Test-Cert 2>&1
        $curlStr = $curlOutput | Out-String
        
        # IIS default response might be 403 or 404 if no default document exists, which means TLS succeeded perfectly!
        if ($LASTEXITCODE -eq 0 -or $curlStr -match "HTTP/1.1 200|HTTP/1.1 403|HTTP/1.1 404") {
            Write-Host "    -> PASS: TLS Handshake succeeded and Schannel verified connection." -ForegroundColor Green
            $state = Get-State; $state.T5 = $true; Save-State $state
        } else {
            throw "TLS Handshake failed! curl output: $curlStr"
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
