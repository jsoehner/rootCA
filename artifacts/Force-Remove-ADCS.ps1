#Requires -RunAsAdministrator

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Surgical ADCS Teardown Script"                           -ForegroundColor Cyan
Write-Host "  Use ONLY when 0x80073701 completely blocks uninstallation" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Kill the Certificate Service
Write-Host "`n[1/5] Forcibly stopping and deleting CertSvc..." -ForegroundColor Yellow
$svc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service -Name CertSvc -Force -ErrorAction SilentlyContinue
    & sc.exe delete CertSvc
    Write-Host "  -> CertSvc deleted." -ForegroundColor Green
} else {
    Write-Host "  -> CertSvc already missing." -ForegroundColor Green
}

# 2. Obliterate ADCS Registry Keys
Write-Host "`n[2/5] Deleting ADCS Registry Hives..." -ForegroundColor Yellow
$regPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc",
    "HKLM:\SOFTWARE\Microsoft\Cryptography\CertificateTemplateCache",
    "HKLM:\SOFTWARE\Microsoft\Cryptography\AutoEnrollment"
)
foreach ($path in $regPaths) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  -> Deleted $path" -ForegroundColor Green
    }
}

# 3. Wipe ADCS Files
Write-Host "`n[3/5] Deleting ADCS File System Directories..." -ForegroundColor Yellow
$filePaths = @(
    "$env:windir\System32\CertSrv",
    "$env:windir\System32\CertLog",
    "C:\CertConfig"
)
foreach ($path in $filePaths) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  -> Deleted $path" -ForegroundColor Green
    }
}

# 4. Clear the Server Manager Cache
Write-Host "`n[4/5] Trashing Server Manager Component Cache..." -ForegroundColor Yellow
$smCache = "HKLM:\SOFTWARE\Microsoft\ServerManager\ServicingStorage\ServerComponentCache"
if (Test-Path $smCache) {
    Remove-Item -Path $smCache -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  -> Server Manager Cache cleared." -ForegroundColor Green
}

# 5. Attempt raw DISM Disable
Write-Host "`n[5/5] Attempting raw DISM disable (this may throw 0x80073701, which is fine)..." -ForegroundColor Yellow
& dism.exe /Online /Disable-Feature /FeatureName:ActiveDirectory-CertificateServices /Remove

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "TEARDOWN COMPLETE." -ForegroundColor Green
Write-Host "You MUST REBOOT the server now." -ForegroundColor Red
Write-Host "After reboot, Server Manager will rebuild its cache." -ForegroundColor Cyan
Write-Host "Then, attempt to install the role manually:" -ForegroundColor Cyan
Write-Host "Install-WindowsFeature ADCS-Cert-Authority -Source wim:D:\sources\install.wim:2" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
