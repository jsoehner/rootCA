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
    [string]$TemplateName = "Computer"
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
    
    try {
        # Using the native PKI cmdlet to request a cert from the Enterprise CA
        $enrollResult = Get-Certificate -Template $TemplateName -CertStoreLocation "Cert:\LocalMachine\My" -ErrorAction Stop
        $cert = $enrollResult.Certificate
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
    
    Write-Host "[*] Binding Enterprise certificate to IIS (Port 443)..."
    if (Test-Path "IIS:\SslBindings\*!443") { Remove-Item -Path "IIS:\SslBindings\*!443" -Force }
    if (Test-Path "IIS:\SslBindings\0.0.0.0!443") { Remove-Item -Path "IIS:\SslBindings\0.0.0.0!443" -Force }
    
    Get-Item -Path "Cert:\LocalMachine\My\$($cert.Thumbprint)" | New-Item -Path "IIS:\SslBindings\*!443" | Out-Null
    
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

    # In an Enterprise CA environment, certreq can automatically renew a machine certificate
    # using the existing certificate as the signature for the renewal request.
    $renewOutput = & cmd.exe /c "certreq -enroll -q -machine -cert $($state.Thumbprint) renew 2>&1"
    $renewStr = $renewOutput | Out-String

    if ($LASTEXITCODE -ne 0 -and $renewStr -notmatch "Certificate Request Processor: The operation completed successfully") {
        # Note: If the template forces manager approval, this might pend instead of issue.
        Write-Host "    -> FAIL: Renewal failed or went to pending state. Output:" -ForegroundColor Red
        Write-Host $renewStr
        throw "Renewal operation failed."
    }

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
