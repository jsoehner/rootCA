# Phase 3 Test Execution Worksheet

Date Prepared: 2026-04-22  
Scope: Mandatory Phase 3 interoperability tests (Tests 1-6)  
Gate Use: Populate results in phase3/logs/Phase-3-Execution-Log.md and complete GO/NO-GO block.

---

## Operator Instructions

1. Run tests in order.
2. Capture raw command output for each step.
3. Save evidence using the filenames listed below.
4. Mark each test PASS or FAIL with a short defect note.
5. Do not open Phase 4 until all mandatory tests are PASS or a formal NO-GO/fallback decision is recorded.

Suggested evidence location:
- Linux workspace: `~/rootCA/phase3/logs`
- Windows host capture folder: `C:\\Temp\\phase3-evidence`

---

## Test 1 - Root Chain Recognition (Windows)

Objective:
- Confirm pilot root is trusted by pilot Windows endpoints.

Preconditions:
- `pilot-root.pem` available from `~/rootCA/phase3/pilot-root.pem`.
- Pilot endpoint joined to pilot environment.

Steps:
1. Convert PEM to DER on Linux:
   - `openssl x509 -in ~/rootCA/phase3/pilot-root.pem -outform der -out ~/rootCA/phase3/pilot-root.cer`
2. Copy `pilot-root.cer` to Windows endpoint.
3. Install into Local Machine Trusted Root Certification Authorities.
4. Run on Windows (elevated CMD):
   - `certutil -store root > C:\Temp\phase3-evidence\test1-certutil-store-root.txt`

**Note:** For initial CRL generation before starting ADCS, if you receive 'The RPC server is not listening' or similar errors, use the documented CLI bootstrap CRL procedure to generate and copy a CRL from EJBCA to `C:\Windows\System32\CertSrv\CertEnroll\`. See Publish-CRL-AIA-HTTP.md for step-by-step instructions.

5. Verify pilot root CN appears and no trust warning is present.

PASS criteria:
- Pilot root is present in Local Machine Root store.
- `certutil -store root` shows expected root entry.

Evidence files:
- `test1-certutil-store-root.txt`
- `test1-root-store-screenshot.png`

Result:
- [ ] PASS
- [ ] FAIL
Notes:

---

## Test 2 - AD CS Subordinate Issuance From Pilot Root

Objective:
- Confirm pilot root signs AD CS subordinate and AD CS service starts healthy.

Preconditions:
- Windows Server 2022/2025 pilot host has ADCS-Cert-Authority installed and healthy.
  If installation failed (error 0x80073701), run the repair script first:
  - Script location (Linux): `~/rootCA/artifacts/Repair-ADCS-Install.ps1`
  - Copy to Windows host, then run elevated:
    ```powershell
    .\Repair-ADCS-Install.ps1
    # or offline: .\Repair-ADCS-Install.ps1 -RepairSource "E:\sources\install.wim"
    ```
  - Logs written to: `C:\Temp\phase3-adcs-repair\`
- AD CS subordinate CSR generated on pilot Windows CA host.
- Subordinate signing profile available in EJBCA.
- EJBCA end entity profile `ADCS2025_SubCA_EE_Profile` available and mapped to the intended subordinate certificate profile.
- CSR PoPO pre-check passes:
   - `openssl req -in <path-to-your-new-csr.req> -verify -noout`

Steps:
1. Export subordinate CSR from Windows CA host.
2. Sign CSR in EJBCA using CLI helper:
   - `./phase3/phase3-sign-adcs-subordinate-csr.sh --csr <path-to-your-new-csr.req> --ee-profile ADCS2025_SubCA_EE_Profile`
3. Export signed subordinate certificate as `pilot-sub-from-adcs.cer`.
4. Install signed subordinate cert into AD CS setup flow.
5. Run on Windows CA host:
   - `certutil -pulse > C:\Temp\phase3-evidence\test2-certutil-pulse.txt`
6. Check Event Viewer for AD CS start errors.

PASS criteria:
- Subordinate certificate accepted by AD CS.
- AD CS service healthy after install.
- No critical certificate validation/startup errors.

Evidence files:
- `test2-subordinate-csr.csr`
- `test2-signed-subordinate.cer`
- `test2-certutil-pulse.txt`
- `test2-adcs-eventviewer-screenshot.png`

Result:
- [ ] PASS
- [ ] FAIL
Notes:

---

## Test 3 - Pilot AD CS Enrollment Workflow

Objective:
- Confirm end-entity enrollment succeeds and chain is valid.

Preconditions:
- Test certificate template published on pilot AD CS.
- Pilot root trusted by endpoint.

Steps:
1. On Windows endpoint, submit enrollment request:
   - `certreq -submit -config "pilot-adcs.pilot.jsiggroup.local\\JSIGROUP Intermediate CA - AD CS - PILOT" request.inf C:\\Temp\\phase3-evidence\\test3-issued.cer > C:\\Temp\\phase3-evidence\\test3-certreq-submit.txt`
      - `certreq -submit -config "pilot-adcs.pilot.jsigroup.local\\JSIGROUP Intermediate CA - AD CS - PILOT" request.inf C:\\Temp\\phase3-evidence\\test3-issued.cer > C:\\Temp\\phase3-evidence\\test3-certreq-submit.txt`
2. Open MMC Certificates snap-in and confirm issued cert in Personal store.
3. Confirm full chain appears clean (root -> subordinate -> end-entity).

PASS criteria:
- Enrollment succeeds.
- Issued cert appears in Personal store.
- Chain builds without warnings.

Evidence files:
- `test3-certreq-submit.txt`
- `test3-issued.cer`
- `test3-mmc-chain-screenshot.png`

Result:
- [ ] PASS
- [ ] FAIL
Notes:

---

## Test 4 - Chain Building and Validation

Objective:
- Confirm chain validation behavior with URL fetch.

Preconditions:
- End-entity certificate from Test 3 available.
- Validation endpoint has only pilot root trusted (no manual intermediate preload).

Steps:
1. On Windows validation host:
   - `certutil -verify -urlfetch C:\\Temp\\phase3-evidence\\test3-issued.cer > C:\\Temp\\phase3-evidence\\test4-certutil-verify-urlfetch.txt`
2. Optional Linux cross-check:
   - `openssl verify -CAfile ~/rootCA/phase3/pilot-root.pem ~/rootCA/phase3/pilot-sub.pem > ~/rootCA/phase3/logs/test4-openssl-verify.txt 2>&1`

PASS criteria:
- `certutil -verify -urlfetch` returns successful chain validation.
- No AIA/CRL retrieval failure causing chain failure.

Evidence files:
- `test4-certutil-verify-urlfetch.txt`
- `test4-openssl-verify.txt` (optional)

Result:
- [ ] PASS
- [ ] FAIL
Notes:

---

## Test 5 - TLS/Schannel Validation

Objective:
- Confirm real TLS handshake succeeds with Schannel using pilot-issued cert.

Preconditions:
- Pilot-issued server cert bound to IIS HTTPS listener.

Steps:
1. Bind pilot-issued cert to IIS site on test server.
2. From Windows client, browse to target URL:
   - `https://pilot-web.pilot.jsiggroup.local`
      - `https://pilot-web.pilot.jsigroup.local`
3. Run on Windows client:
   - `certutil -ssl https://pilot-web.pilot.jsiggroup.local > C:\\Temp\\phase3-evidence\\test5-certutil-ssl.txt`
      - `certutil -ssl https://pilot-web.pilot.jsigroup.local > C:\\Temp\\phase3-evidence\\test5-certutil-ssl.txt`
4. Confirm browser and Schannel report no trust/chain errors.

PASS criteria:
- HTTPS connection succeeds without cert warnings.
- Schannel output indicates valid chain and usable server cert.

Evidence files:
- `test5-certutil-ssl.txt`
- `test5-browser-connection-screenshot.png`
- `test5-iis-binding-screenshot.png`

Result:
- [ ] PASS
- [ ] FAIL
Notes:

---

## Test 6 - CRL Publication and Retrieval

Objective:
- Confirm CRL is published and retrievable by clients.

Preconditions:
- CRL distribution point configured and reachable from test client.

Steps:
1. Publish/update CRL on issuing CA.
2. On Windows client, force URL retrieval check:
   - `certutil -url C:\\Temp\\phase3-evidence\\test3-issued.cer > C:\\Temp\\phase3-evidence\\test6-certutil-url.txt`
3. Confirm CRL endpoint retrieval succeeds and status is valid.

PASS criteria:
- CRL endpoint reachable.
- Certificate status check does not fail due to CRL retrieval.

Evidence files:
- `test6-certutil-url.txt`
- `test6-crl-endpoint-screenshot.png`

Result:
- [ ] PASS
- [ ] FAIL
Notes:

---

## Final Gate Summary (Populate After Tests 1-6)

Mandatory test summary:
- Test 1: [ ] PASS [ ] FAIL
- Test 2: [ ] PASS [ ] FAIL
- Test 3: [ ] PASS [ ] FAIL
- Test 4: [ ] PASS [ ] FAIL
- Test 5: [ ] PASS [ ] FAIL
- Test 6: [ ] PASS [ ] FAIL

Defect summary:
- Critical defects count: ____
- Major defects count: ____
- Minor defects count: ____

Decision recommendation:
- [ ] GO to Phase 4
- [ ] NO-GO, run fallback/remediation

Prepared by: __________________________  Date: __/__/____
Reviewed by: __________________________  Date: __/__/____
