# Publishing CRL and AIA via HTTP on ADCS

This document describes how to configure an ADCS server to host the CRL and AIA over HTTP, for both standalone (non-domain) and domain-joined CA scenarios.

---

## Initial CRL Generation (Required Before Starting ADCS)

After installing the subordinate CA certificate and before starting the ADCS service for the first time:

**If the CA service is not running yet (first CRL):**
1. Open the Certification Authority management console (`certsrv.msc`) as an administrator.
2. In the left pane, click **Revoked Certificates** under your CA name.
3. Right-click **Revoked Certificates** → All Tasks → Publish → select "New CRL".
4. The CRL will be generated in `C:\Windows\System32\CertSrv\CertEnroll\`.
5. Copy the generated `.crl` file to your HTTP CDP directory (e.g., `C:\inetpub\wwwroot\crl`).
6. Verify HTTP access to the CRL from another machine:
   ```
   certutil -url http://ca.jsigroup.local/crl/<YourCAName>.crl
   ```
7. Start the ADCS service.


**If the CA service is not running yet (first CRL) and you receive 'The RPC server is not listening' or similar errors:**

### CLI Bootstrap CRL Procedure

1. On the EJBCA Linux host, generate a CRL for the subordinate CA using the CLI:
   ```bash
   cd ~/rootCA/artifacts/ejbca/ejbca-ce-r9.3.7/bin
   ./ejbca.sh ca getcrl --caname <SubordinateCAName> --out /tmp/bootstrap.crl
   ```
   Replace `<SubordinateCAName>` with the exact name of your subordinate CA as registered in EJBCA.

2. Copy the CRL to the Windows CA host (e.g., using `scp`, SMB share, or USB):
   ```bash
   scp /tmp/bootstrap.crl <windowsuser>@<windows-host>:/C$/Temp/bootstrap.crl
   ```

3. On the Windows CA host:
   - Rename `bootstrap.crl` to match the expected CRL filename (usually `<CACommonName>.crl`, matching the subordinate CA's common name).
   - Move the file to `C:\Windows\System32\CertSrv\CertEnroll\`.
   - Ensure file permissions allow the CA service to read it.

4. Start the ADCS service. It should now start successfully.

5. Once the service is running, immediately publish a new CRL from the Windows CA (using certsrv.msc or `certutil -crl`) to replace the bootstrap CRL.

This manual CRL copy is required only for the very first startup if no CRL exists and the CA service will not start.

**If the CA service is already running:**
- You may use `certutil -crl` to publish a new CRL as needed.

This step is required to avoid revocation errors and allow the CA service to start successfully.

---

## 1. Standalone (Non-Domain-Joined) ADCS CA — HTTP AIA/CRL Only

### Steps
1. **Install IIS (if not already installed):**
   ```powershell
   Install-WindowsFeature -Name Web-Server -IncludeManagementTools
   ```
2. **Create CRL and AIA directories:**
   ```powershell
   mkdir "C:\inetpub\wwwroot\crl"
   ```
3. **Configure ADCS to publish CRL/AIA to HTTP:**
   - Open Certification Authority MMC.
   - Right-click the CA > Properties > Extensions tab.
   - For both CRL Distribution Point (CDP) and Authority Information Access (AIA), add:
     - `http://ca.jsigroup.local/crl/<CaName><CRLNameSuffix><DeltaCRLAllowed>.crl`
     - `http://ca.jsigroup.local/<CaName>.cer`
   - Check "Include in the CDP extension of issued certificates" and "Include in the AIA extension of issued certificates" as appropriate.
   - For each, check "Publish CRLs to this location" and "Publish CA certificate to this location" as needed.
4. **Publish the CRL and CA certificate:**
   ```powershell
   certutil -dspublish -f "C:\Windows\System32\CertSrv\CertEnroll\<YourCAName>.crt"
   certutil -dspublish -f "C:\Windows\System32\CertSrv\CertEnroll\<YourCAName>.crl"
   ```
5. **Copy files to IIS directory:**
   ```powershell
   Copy-Item "C:\Windows\System32\CertSrv\CertEnroll\*" "C:\inetpub\wwwroot\crl" -Force
   ```
6. **Verify HTTP access:**
   - From a client:
     ```
     certutil -url http://ca.jsigroup.local/crl/<YourCAName>.crl
     ```

---

## 2. Domain-Joined ADCS CA — LDAP/HTTP Publishing

### Steps
1. **Install IIS (if not already installed):**
   ```powershell
   Install-WindowsFeature -Name Web-Server -IncludeManagementTools
   ```
2. **Create CRL directory:**
   ```powershell
   mkdir "C:\inetpub\wwwroot\crl"
   ```
3. **Configure ADCS Extensions:**
   - In Certification Authority MMC > Properties > Extensions:
     - For CDP, include both LDAP and HTTP locations:
       - `ldap:///CN=<CATruncatedName>,CN=CDP,CN=Public Key Services,CN=Services,CN=Configuration,DC=jsigroup,DC=local?certificateRevocationList?base?objectClass=cRLDistributionPoint`
       - `http://ca.jsigroup.local/crl/<CaName><CRLNameSuffix><DeltaCRLAllowed>.crl`
     - For AIA, include both LDAP and HTTP:
       - `ldap:///CN=<CATruncatedName>,CN=AIA,CN=Public Key Services,CN=Services,CN=Configuration,DC=jsigroup,DC=local?cACertificate?base?objectClass=certificationAuthority`
       - `http://ca.jsigroup.local/<CaName>.cer`
     - Check "Include in the CDP/AIA extension of issued certificates" and "Publish to this location" as appropriate.
4. **Publish to AD and HTTP:**
   - AD publishing is automatic for LDAP entries.
   - For HTTP, copy files as in the standalone path:
     ```powershell
     Copy-Item "C:\Windows\System32\CertSrv\CertEnroll\*" "C:\inetpub\wwwroot\crl" -Force
     ```
5. **Verify both LDAP and HTTP access:**
   - HTTP:
     ```
     certutil -url http://ca.jsigroup.local/crl/<YourCAName>.crl
     ```
   - LDAP:
     ```
     certutil -url ldap:///CN=<CATruncatedName>,CN=CDP,CN=Public Key Services,CN=Services,CN=Configuration,DC=jsigroup,DC=local
     ```

---

**Note:**
- Replace `<YourCAName>` and `<CATruncatedName>` with your actual CA names as shown in the CertEnroll directory.
- For DNS, ensure ca.jsigroup.local resolves to the ADCS server’s IP (edit your DNS or hosts file as needed).
