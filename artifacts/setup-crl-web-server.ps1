<#
.SYNOPSIS
    Configures a standalone Windows Server as an IIS Web Server to host CRLs and AIA certificates.

.DESCRIPTION
    This script automates the setup of an HTTP-based Certificate Distribution Point (CDP).
    It installs the IIS Web Server role, creates a dedicated /crl application directory,
    configures Anonymous Authentication, adds the required MIME types for PKI files,
    and enables double escaping (which is strictly required for Delta CRLs that contain '+' characters).

.USAGE
    Run this script as an Administrator on the standalone Windows server intended to host CRLs.
#>

[CmdletBinding()]
param(
    [string]$CrlPhysicalPath = "C:\inetpub\wwwroot\crl",
    [string]$AppName = "crl",
    [string]$SiteName = "Default Web Site"
)

# 1. Install IIS Web Server
Write-Host "[*] Installing IIS Web-Server role..." -ForegroundColor Cyan
Install-WindowsFeature -Name Web-Server,Web-Mgmt-Tools -IncludeAllSubFeature

# 2. Ensure the WebAdministration module is loaded
Import-Module WebAdministration

# 3. Create physical directory structure
Write-Host "[*] Creating physical directory at: $CrlPhysicalPath" -ForegroundColor Cyan
if (!(Test-Path $CrlPhysicalPath)) {
    New-Item -ItemType Directory -Force -Path $CrlPhysicalPath | Out-Null
}

# 4. Create the IIS Web Application
Write-Host "[*] Configuring IIS Web Application '/$AppName'..." -ForegroundColor Cyan
$appPath = "IIS:\Sites\$SiteName\$AppName"
if (!(Test-Path $appPath)) {
    New-WebApplication -Name $AppName -Site $SiteName -PhysicalPath $CrlPhysicalPath -Force | Out-Null
} else {
    Write-Host "    Application '/$AppName' already exists." -ForegroundColor Yellow
}

# 5. Enable Anonymous Authentication (and disable others to ensure no prompts)
Write-Host "[*] Ensuring Anonymous Authentication is enabled..." -ForegroundColor Cyan
Set-WebConfigurationProperty -Filter '/system.webServer/security/authentication/anonymousAuthentication' -Name 'enabled' -Value $true -PSPath "IIS:\Sites\$SiteName\$AppName"

# 6. Enable Double Escaping (Required for Delta CRLs which use '+' in the filename)
Write-Host "[*] Enabling Double Escaping for Delta CRLs..." -ForegroundColor Cyan
Set-WebConfigurationProperty -Filter '/system.webServer/security/requestFiltering' -Name 'allowDoubleEscaping' -Value $true -PSPath "IIS:\Sites\$SiteName\$AppName"

# 7. Configure MIME Types
Write-Host "[*] Configuring MIME types for .crl and .cer files..." -ForegroundColor Cyan
$mimeTypes = @(
    @{ Ext = ".crl"; Mime = "application/pkix-crl" },
    @{ Ext = ".cer"; Mime = "application/x-x509-ca-cert" },
    @{ Ext = ".crt"; Mime = "application/x-x509-ca-cert" }
)

foreach ($type in $mimeTypes) {
    # Remove existing to prevent duplication errors
    Remove-WebConfigurationProperty -Filter "//staticContent" -Name "." -AtElement @{fileExtension=$type.Ext} -PSPath "IIS:\Sites\$SiteName" -ErrorAction SilentlyContinue
    
    # Add proper MIME type
    Add-WebConfigurationProperty -Filter "//staticContent" -Name "." -Value @{fileExtension=$type.Ext; mimeType=$type.Mime} -PSPath "IIS:\Sites\$SiteName"
}

# 8. (Optional) Setup an SMB Share for remote AD CS publishing
Write-Host "[*] Setting up SMB Share for AD CS automatic publishing..." -ForegroundColor Cyan
$ShareName = "CertEnroll"
if (!(Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $ShareName -Path $CrlPhysicalPath -Description "PKI CRL Distribution Share" -ChangeAccess "Everyone" | Out-Null
    Write-Host "    Share '\\$env:COMPUTERNAME\$ShareName' created successfully." -ForegroundColor Green
    Write-Host "    NOTE: For automatic publishing from AD CS, grant the AD CS Computer Account 'Full Control' on the NTFS folder: $CrlPhysicalPath" -ForegroundColor Yellow
} else {
    Write-Host "    Share '$ShareName' already exists." -ForegroundColor Yellow
}

Write-Host "`n[*] Setup Complete!" -ForegroundColor Green
Write-Host "    You can access the CRL directory via HTTP: http://localhost/$AppName/"
Write-Host "    Physical path: $CrlPhysicalPath"
