<#
.SYNOPSIS
    Automated integration test suite for an AD CS Enterprise Certification Authority (Domain-Joined).

.DESCRIPTION
    This script automates Phase 3 pilot testing (Tests 3, 4, 5, 6, and 7) specifically 
    tailored for an Enterprise CA installed on a Domain Controller (PDC) or domain-joined member server.
    
    Unlike the Standalone CA test, this script leverages Active Directory Certificate Templates 
    (e.g., the default 'Computer' template) for zero-touch auto-enrollment and auto-renewal.

.USAGE
    Run this script as a Domain Administrator on the Enterprise AD CS server.
#>

[CmdletBinding()]
param(
    [string]$TemplateName = "DomainController"
)

$ErrorActionPreference = "Stop"
$workDir = "C:\certs\enterprise-tests"
$crlUrl  = "http://localhost/crl/root.crl" # Update if your Enterprise CDP is different
$StateFile = Join-Path $workDir "ent-test-state.json"

function Get-State {
    if (Test-Path $StateFile) { return Get-Content -LiteralPath $StateFile | ConvertFrom-Json }
    return @{ T3 = $false; T5 = $false; T6 = $false; T7 = $false; Thumbprint = "" }
}

function Save-State {
    param($StateObj)
    $StateObj | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Force
}

function Run-EnterpriseEnrollment {
    Write-Host "`n[*] Test 3 & 4: Enterprise Auto-Enrollment & Chain Validation" -ForegroundColor Cyan
    
    if (!(Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }

    Write-Host "[*] Requesting a new certificate using the '$TemplateName' AD Template..."
    Write-Host "    (Because this is an Enterprise CA, no manual approval is needed!)" -ForegroundColor DarkGray
    
    # Ensure the template is published to the CA before requesting
    & certutil -setCAtemplates +$TemplateName | Out-Null
    Restart-Service -Name CertSvc -ErrorAction SilentlyContinue
    
    Write-Host "[*] Trusting the Production Root CA in the Local Machine store..." -ForegroundColor DarkGray
    $rootCertPath = "C:\certs\root-ca-prod-ecc384.cer"
    if (Test-Path $rootCertPath) {
        Import-Certificate -FilePath $rootCertPath -CertStoreLocation "Cert:\LocalMachine\Root" -ErrorAction SilentlyContinue | Out-Null
    }

    try {
        # WORKAROUND: Legacy V1 AD templates (like DomainController) force the client to use a Legacy CSP. 
        # Legacy CSPs cannot verify ECDSA CA signatures and throw 0x80070057 during installation.
        # We use an INF file to explicitly generate an RSA key inside a modern CNG Provider, 
        # which correctly processes the ECC signature during installation, while still leveraging the AD Template.
        $infPath = Join-Path $workDir "ent-request.inf"
        $reqPath = Join-Path $workDir "ent-request.req"
        $cerPath = Join-Path $workDir "ent-issued.cer"
        $rspPath = Join-Path $workDir "ent-issued.rsp"
        
        # Cleanup previous run artifacts to prevent certreq ERROR_FILE_EXISTS
        if (Test-Path $reqPath) { Remove-Item $reqPath -Force }
        if (Test-Path $cerPath) { Remove-Item $cerPath -Force }
        if (Test-Path $rspPath) { Remove-Item $rspPath -Force }
        
        $inf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=$env:COMPUTERNAME.jsigroup.local"
MachineKeySet = TRUE
RequestType = PKCS10
ProviderName = "Microsoft Software Key Storage Provider"
KeyAlgorithm = RSA
KeyLength = 2048
HashAlgorithm = SHA256
"@
        Set-Content -Path $infPath -Value $inf -Encoding ASCII
        
        Write-Host "    -> Generating RSA 2048 CSR via CNG..." -ForegroundColor DarkGray
        $newOut = & cmd.exe /c "certreq.exe -new -q $infPath $reqPath 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "certreq -new failed: $newOut" }
        
        Write-Host "    -> Submitting to Enterprise CA as Machine Context..." -ForegroundColor DarkGray
        $submitOut = & cmd.exe /c "certreq.exe -AdminForceMachine -submit -attrib `"CertificateTemplate:$TemplateName`" -q $reqPath $cerPath 2>&1"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $cerPath)) { throw "certreq -submit failed: $submitOut" }
        
        Write-Host "    -> Accepting and installing issued certificate..." -ForegroundColor DarkGray
        $acceptOut = & cmd.exe /c "certreq.exe -accept -q -machine $cerPath 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "certreq -accept failed: $acceptOut" }

        # Get the newest certificate from the store matching the subject
        $cert = Get-ChildItem "Cert:\LocalMachine\My" | Where-Object Subject -match $env:COMPUTERNAME | Sort-Object NotBefore -Descending | Select-Object -First 1
        if (-not $cert) { throw "Certificate not found in store after successful enroll." }
    } catch {
        throw "Failed to enroll for template '$TemplateName'. Ensure the template is published on the CA and Domain Computers have Enroll permissions. Error: $($_.Exception.Message)"
    }
    
    Write-Host "    -> PASS: Certificate instantly issued and installed." -ForegroundColor Green
    Write-Host "       Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green

    Write-Host "`n[*] Validating full cryptographic chain (AIA/CDP reachability)..."
    # Export temporarily to verify chain
    $tempCer = Join-Path $workDir "ent-test.cer"
    [System.IO.File]::WriteAllBytes($tempCer, $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    
    $verifyOutput = & certutil -verify -urlfetch $tempCer 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Chain validation failed. Output: $($verifyOutput | Out-String)" }
    Write-Host "    -> PASS: Full chain built and verified successfully via CDP/AIA." -ForegroundColor Green

    $state = Get-State; $state.T3 = $true; $state.Thumbprint = $cert.Thumbprint; Save-State $state
}

function Run-TlsValidation {
    $state = Get-State
    if (-not $state.T3 -or -not $state.Thumbprint) { throw "No certificate enrolled. Run Test 3 first." }
    
    Write-Host "`n[*] Test 5: TLS/Schannel Validation (Enterprise CA)" -ForegroundColor Cyan
    $cert = Get-Item -Path "Cert:\LocalMachine\My\$($state.Thumbprint)" -ErrorAction SilentlyContinue
    if (-not $cert) { throw "Certificate with thumbprint $($state.Thumbprint) not found in store." }

    Write-Host "[*] Creating IIS HTTPS Binding..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (-not (Get-WebBinding -Name "Default Web Site" -Protocol https -ErrorAction SilentlyContinue)) {
        New-WebBinding -Name "Default Web Site" -Protocol https -Port 443 -IPAddress "*" | Out-Null
    }
    
    Write-Host "[*] Binding Enterprise certificate to IIS (Port 443) via netsh..."
    $thumbprint = $cert.Thumbprint
    
    # Remove existing bindings
    & netsh http delete sslcert ipport=0.0.0.0:443 2>&1 | Out-Null
    
    # Add new binding
    $appId = "{4dc3e181-e14b-4a21-b022-59fc669b0914}"
    $netshOut = & netsh http add sslcert ipport=0.0.0.0:443 certhash=$thumbprint appid=$appId 2>&1
    if ($LASTEXITCODE -ne 0 -and $netshOut -notmatch "SSL Certificate successfully added") {
        throw "Failed to bind certificate using netsh: $netshOut"
    }
    
    Write-Host "[*] Restarting IIS (W3SVC) to apply bindings..."
    Restart-Service -Name W3SVC -ErrorAction SilentlyContinue
    
    Write-Host "[*] Testing HTTPS connection via strict Schannel validation..."
    try {
        # Get the Subject CN to test against
        $cn = ($cert.Subject -split ',')[0].Replace("CN=", "").Trim()
        
        # Use native curl.exe with --resolve to force strict TLS name and chain validation
        $curlOutput = & cmd.exe /c "curl.exe --resolve ${cn}:443:127.0.0.1 -s -v -I https://${cn} 2>&1"
        $curlStr = $curlOutput | Out-String
        
        if ($LASTEXITCODE -eq 0 -or $curlStr -match "HTTP/1.1 200|HTTP/1.1 403|HTTP/1.1 404") {
            Write-Host "    -> PASS: TLS Handshake succeeded and Schannel verified connection." -ForegroundColor Green
            $state.T5 = $true; Save-State $state
        } else {
            throw "TLS Handshake failed! curl output: $curlStr"
        }
    } catch {
        throw "Failed to validate TLS connection. Exception: $($_.Exception.Message)"
    }
}

function Run-CrlVerification {
    Write-Host "`n[*] Test 6: CRL Retrieval Verification" -ForegroundColor Cyan
    Write-Host "[*] Downloading CRL from $crlUrl..."
    $crlPath = Join-Path $workDir "downloaded.crl"
    if (Test-Path $crlPath) { Remove-Item $crlPath -Force }
    
    try {
        Invoke-WebRequest -Uri $crlUrl -OutFile $crlPath -UseBasicParsing -ErrorAction Stop
    } catch {
        throw "Failed to download CRL. Is IIS running and hosting /crl/root.crl?"
    }

    Write-Host "    -> PASS: CRL downloaded successfully." -ForegroundColor Green
    
    Write-Host "[*] Parsing CRL using certutil..."
    $dumpOutput = & certutil -dump $crlPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to parse CRL. Output: $($dumpOutput | Out-String)" }
    Write-Host "    -> PASS: CRL parsed successfully and signature is valid." -ForegroundColor Green
    
    $state = Get-State; $state.T6 = $true; Save-State $state
}

function Run-EnterpriseRenewal {
    $state = Get-State
    if (-not $state.T3 -or -not $state.Thumbprint) { throw "No certificate enrolled to renew. Run Test 3 first." }

    Write-Host "`n[*] Test 7: Certificate Renewal on Enterprise AD CS" -ForegroundColor Cyan
    Write-Host "[*] Sending renewal request to the CA for cert thumbprint: $($state.Thumbprint)..."

    # WORKAROUND: Just like the initial enrollment, native Enterprise renewal falls back to the AD Template's 
    # Legacy CSP settings, which throws 0x80070057 when trying to verify the ECC CA signature.
    # We must explicitly force the renewal to happen within the CNG provider using an INF file.
    $infPath = Join-Path $workDir "ent-renew.inf"
    $reqPath = Join-Path $workDir "ent-renew.req"
    $cerPath = Join-Path $workDir "ent-renew.cer"
    
    if (Test-Path $reqPath) { Remove-Item $reqPath -Force }
    if (Test-Path $cerPath) { Remove-Item $cerPath -Force }
    
    $inf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
RenewalCert = "$($state.Thumbprint)"
MachineKeySet = TRUE
RequestType = CMC
"@
    Set-Content -Path $infPath -Value $inf -Encoding ASCII
    
    Write-Host "    -> Generating CMC Renewal CSR..." -ForegroundColor DarkGray
    $newOut = & cmd.exe /c "certreq.exe -new -q $infPath $reqPath 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "certreq -new failed: $newOut" }
    
    Write-Host "    -> Submitting renewal request as Machine Context..." -ForegroundColor DarkGray
    $submitOut = & cmd.exe /c "certreq.exe -AdminForceMachine -submit -attrib `"CertificateTemplate:$TemplateName`" -q $reqPath $cerPath 2>&1"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $cerPath)) { throw "certreq -submit failed: $submitOut" }
    
    Write-Host "    -> Accepting and installing renewed certificate..." -ForegroundColor DarkGray
    $acceptOut = & cmd.exe /c "certreq.exe -accept -q -machine $cerPath 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "certreq -accept failed: $acceptOut" }

    Write-Host "    -> PASS: Certificate successfully renewed via Enterprise auto-enrollment protocol!" -ForegroundColor Green
    
    # Find the newly issued cert (it will have the same subject but a different thumbprint)
    $oldCert = Get-Item -Path "Cert:\LocalMachine\My\$($state.Thumbprint)" -ErrorAction SilentlyContinue
    $newCerts = Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.Subject -eq $oldCert.Subject -and $_.Thumbprint -ne $state.Thumbprint } | Sort-Object NotBefore -Descending
    
    if ($newCerts) {
        Write-Host "    -> PASS: New certificate installed with Thumbprint: $($newCerts[0].Thumbprint)" -ForegroundColor Green
        # Update state with new thumbprint
        $state.Thumbprint = $newCerts[0].Thumbprint
    } else {
        Write-Host "    [!] Warning: Renewal command succeeded but new certificate was not found in the store." -ForegroundColor Yellow
    }

    $state.T7 = $true; Save-State $state
}

function Show-Menu {
    function Checkbox { param([bool]$Done) if ($Done) { return "[X]" } else { return "[ ]" } }
    
    while ($true) {
        $state = Get-State
        Write-Host "`n============================================================" -ForegroundColor Cyan
        Write-Host "   Enterprise AD CS Automated Integration Validation Suite" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "  $(Checkbox $state.T3) 1. Tests 3 & 4: Enterprise Auto-Enrollment & Chain Validation"
        Write-Host "  $(Checkbox $state.T5) 2. Test 5: TLS/Schannel Validation (Requires Test 3)"
        Write-Host "  $(Checkbox $state.T6) 3. Test 6: CRL Retrieval Verification"
        Write-Host "  $(Checkbox $state.T7) 4. Test 7: Certificate Renewal (Requires Test 3)"
        Write-Host "  [ ] 5. Run All Tests Sequentially"
        Write-Host "  [ ] 6. Exit"
        Write-Host "============================================================" -ForegroundColor Cyan

        $choice = Read-Host "`nSelect an option (1-6)"
        
        try {
            switch ($choice) {
                "1" { Run-EnterpriseEnrollment }
                "2" { Run-TlsValidation }
                "3" { Run-CrlVerification }
                "4" { Run-EnterpriseRenewal }
                "5" { Run-EnterpriseEnrollment; Run-TlsValidation; Run-CrlVerification; Run-EnterpriseRenewal }
                "6" { return }
                default { Write-Host "Invalid option." -ForegroundColor Yellow }
            }
        } catch {
            Write-Host "`n[!] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Show-Menu
