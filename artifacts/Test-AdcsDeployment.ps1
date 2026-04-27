<#
.SYNOPSIS
    Automated integration test suite for an AD CS Standalone Subordinate CA.

.DESCRIPTION
    This script automates Phase 3 pilot testing (Test 3 and Test 4) by simulating 
    a user requesting a certificate, an administrator approving it, and the system 
    validating the cryptographic chain of trust (including HTTP CRL retrieval).
    
    Tests performed:
    1. Generates an ECC P-256 CSR.
    2. Submits the CSR to the local Standalone CA (bypassing UI).
    3. Issues the pending request programmatically.
    4. Retrieves the signed certificate.
    5. Runs `certutil -verify -urlfetch` to ensure the CRL is reachable and the chain is valid.

.USAGE
    Run this script as an Administrator on the AD CS server after Step 3 of the prepare-ADCS wizard.
#>

[CmdletBinding()]
param(
    [string]$SubjectName = "CN=Pilot-Auto-Test-Cert"
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "   AD CS Automated Integration Validation Suite" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Get CA Config
try {
    $configPath = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
    $caConfigs = Get-ChildItem -Path $configPath -ErrorAction Stop
    if ($caConfigs.Count -eq 0) { throw "No CA configuration found." }
    $caName = $caConfigs[0].PSChildName
    $computerName = $env:COMPUTERNAME
    $caConfigString = "$computerName\$caName"
    Write-Host "[*] Connected to CA: $caConfigString"
} catch {
    Write-Host "[!] Failed to locate AD CS configuration. Is CertSvc installed?" -ForegroundColor Red
    throw
}

# Setup Workspace
$workDir = "C:\certs\pilot-tests"
if (!(Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }

$infPath = Join-Path $workDir "test.inf"
$reqPath = Join-Path $workDir "test.req"
$cerPath = Join-Path $workDir "test.cer"
$rspPath = Join-Path $workDir "test.rsp"

if (Test-Path $cerPath) { Remove-Item $cerPath -Force }
if (Test-Path $reqPath) { Remove-Item $reqPath -Force }
if (Test-Path $rspPath) { Remove-Item $rspPath -Force }

# 2. Create INF for CSR
Write-Host "`n[*] Test 1: Generating ECC P-256 CSR for $SubjectName..."
$infContent = @"
[NewRequest]
Subject = "$SubjectName"
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

# 3. Submit CSR
Write-Host "`n[*] Test 2: Submitting CSR to Standalone CA..."
$submitOutput = & certreq -submit -q -config $caConfigString $reqPath $cerPath 2>&1
$submitStr = $submitOutput | Out-String

$requestId = $null
if ($submitStr -match "RequestId:\s+(\d+)") {
    $requestId = $matches[1]
} else {
    throw "Failed to parse RequestId from submission output. Output: $submitStr"
}
Write-Host "    -> PASS: Submitted. Request ID is $requestId." -ForegroundColor Green

# 4. Issue the pending certificate
Write-Host "`n[*] Test 3: Approving/Issuing pending request $requestId..."
$resubmitOutput = & certutil -resubmit $requestId 2>&1
$resubmitStr = $resubmitOutput | Out-String
if ($LASTEXITCODE -ne 0 -and $resubmitStr -notmatch "command completed successfully") {
    throw "Failed to issue certificate: $resubmitStr"
}
Write-Host "    -> PASS: Certificate administratively issued." -ForegroundColor Green

# 5. Retrieve the certificate
Write-Host "`n[*] Test 4: Retrieving issued certificate..."
$retrieveOutput = & certreq -retrieve -q -config $caConfigString $requestId $cerPath 2>&1
if (!(Test-Path $cerPath)) {
    throw "Failed to retrieve certificate: $($retrieveOutput | Out-String)"
}
Write-Host "    -> PASS: Certificate retrieved and saved to $cerPath." -ForegroundColor Green

# 6. Verify the chain and revocation (Test 4 from Pilot)
Write-Host "`n[*] Test 5: Validating certificate chain and CRL reachability..."
Write-Host "    (This ensures IIS is hosting the CRL and the root trust is valid)" -ForegroundColor DarkGray

$verifyOutput = & certutil -verify -urlfetch $cerPath 2>&1
$verifyStr = $verifyOutput | Out-String

# certutil returns 0 on perfect success. If revocation is offline, it might return non-zero.
if ($LASTEXITCODE -ne 0 -or $verifyStr -match "Cannot find object or property") {
    Write-Host "    -> FAIL: Certificate verification failed!" -ForegroundColor Red
    Write-Host "    (Did you copy pilot-root.cer and root.crl to the server? Is IIS running?)" -ForegroundColor Yellow
    Write-Host "    --- Certutil Output ---" -ForegroundColor DarkGray
    Write-Host $verifyStr
    throw "Chain validation failed."
}
Write-Host "    -> PASS: Full chain built and verified successfully." -ForegroundColor Green
Write-Host "    -> PASS: HTTP CRL distribution point reachable." -ForegroundColor Green

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "   ALL TESTS PASSED SUCCESSFULLY! " -ForegroundColor Green
Write-Host "   The Subordinate CA is fully operational and verified." -ForegroundColor Green
Write-Host "========================================================`n" -ForegroundColor Cyan
