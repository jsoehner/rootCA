# Phase 3: Interoperability Pilot and Decision Gate

**Phase Status:** IN PROGRESS — started 2026-04-20  
**Date Created:** 2026-04-19  
**Phase Dependencies:** Phase 2 complete and signed off (2026-04-20, Jeff Soehner)  
**Critical Gate:** This phase produces a go/no-go decision for production key ceremony (Phase 4)  

---

## 1. Overview

Phase 3 is a **gated pilot** that tests the feasibility of the selected cryptographic algorithm (ECC P-384 + SHA-384) in a real Windows Server 2025 AD CS environment. If the pilot passes all acceptance criteria, proceed to Phase 4 production ceremony with the selected algorithm. If the pilot fails, repeat Phase 3 with a fallback algorithm (all-RSA or homogeneous all-ECC P-256) before proceeding to production.

**Deliverables:**
- Isolated pilot EJBCA root (90-day validity; separate from production)
- Isolated Windows Server 2025 AD CS intermediate (pilot, 90-day validity)
- Full interoperability test results (enrollment, renewal, chain building, CRL retrieval, Schannel validation)
- Go/no-go decision record (signed by officers and auditor)
- Fallback contingency plan if pilot fails

**Success Definition:** All mandatory tests pass; zero critical defects; Windows endpoints can validate full ECC chain without client errors or fallback warnings.

## 1.1 Entry Readiness Snapshot (2026-04-20)

Current verified position:
- Phase 1 is complete and signed off.
- Phase 2 technical execution is complete on the EJBCA 9.3.7 + WildFly 30 baseline.
- Local runtime checkpoints remain healthy:
   - Admin context HTTP `200`
   - OCSP status HTTP `200`
- Phase 2 evidence is present under `~/rootCA/phase2`, including:
   - `root-ca.pem`
   - `sub-ca.pem`
   - `logs/phase2-cert-validation-phase2-wf30-ejbca9-20260419T220700Z.txt`
   - `logs/phase2-closeout-report-20260420T092051Z.txt`

Remaining blockers before this phase may formally start:
- None. Phase 2 signed off 2026-04-20. Phase 3 entry authorized.

Immediate start point:
- Begin Section 2.1 with an isolated pilot EJBCA instance or equivalent pilot scope using the existing 90-day pilot profiles already created in Phase 2.

## 1.2 Phase 3 Operator Runbook

Use this sequence to execute Phase 3 once the Phase 2 sign-off block is completed.

### Checklist

```
PHASE 3 EXECUTION CHECKLIST
===========================

ENTRY GATE:
   [x] Phase 2 sign-off recorded in Phase-2-Execution-Log.md
   [x] Phase 2 sign-off recorded in Phase-2-Crypto-Profiles.md
   [x] Naming decision frozen for pilot and downstream docs

PILOT ROOT PREPARATION:
   [x] Separate pilot database/schema selected
   [x] Separate pilot crypto token or software token selected
   [x] RootCAPilot-ECC384-SHA384 profile confirmed present
   [x] SubordCAPilot-ECC384-SHA384 profile confirmed present
   [x] SubordCAPilot-RSA4096-SHA256 profile confirmed present for fallback

PILOT ISSUANCE:
   [x] Pilot root created with 90-day validity (retroactive update: completed 2026-04-22 via CLI)
   [ ] Pilot subordinate CSR generated on Windows AD CS
   [ ] Pilot subordinate signed by pilot root
   [ ] Pilot root and subordinate certificates exported
       Note: Pilot root export complete (`./phase3/pilot-root.pem`) as of 2026-04-22.

WINDOWS VALIDATION:
   [ ] Pilot root trusted on pilot clients
   [ ] AD CS subordinate installed and service healthy
   [ ] End-entity enrollment succeeds
   [ ] Chain building succeeds with urlfetch
   [ ] TLS/Schannel validation succeeds
   [ ] Pilot CRL publication and retrieval succeeds

EVIDENCE AND DECISION:
   [ ] All command output and screenshots saved
       Note: CLI command output and root validation evidence saved under `./phase3/`.
   [ ] Go/no-go decision documented
   [ ] If ECC fails, fallback profile run authorized and scheduled
```

### Execution Sequence

1. ~~Confirm naming is frozen and sign off Phase 2.~~ — DONE 2026-04-20.
2. Stand up the isolated pilot EJBCA scope using a separate database/schema and a non-production token.
3. Confirm the three pilot profiles exist and record their exact names before any issuance.
4. Build the pilot root, then sign the Windows AD CS subordinate CSR with `SubordCAPilot-ECC384-SHA384`.
5. Export the pilot chain artifacts and distribute only the pilot root to test endpoints.
6. Run the acceptance matrix in order: trust recognition, subordinate installation, enrollment, chain validation, TLS/Schannel, then CRL retrieval.
7. Save all evidence in a dedicated pilot artifact location and record the final go/no-go decision.

## 1.3 Pilot State Verification Procedure

Use the following CLI-only checks to verify that the pilot EJBCA instance, pilot database, and pilot root certificate artifact are all healthy before resuming work. Run these any time you return to the project after a break or after a host restart.

```bash
# 1. Confirm pilot WildFly process is running
cat ~/rootCA/phase3/phase3-wildfly30-pilot.pid
ps -p "$(cat ~/rootCA/phase3/phase3-wildfly30-pilot.pid)" --no-headers -o pid,stat,cmd

# 2. Confirm WildFly is bound and listening
ss -tlnp | grep -E '8080|8443|9990'

# 3. Confirm EJBCA health endpoint returns HTTP 200
curl -o /dev/null -sw "%{http_code}\n" http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth

# 4. Confirm pilot database has schema tables and the pilot root CA record
source ~/rootCA/phase3/.pilot-db-credentials
mysql -u "$EJBCA_DB_USER" -p"$EJBCA_DB_PASSWORD" "$EJBCA_DB_NAME" \
  -e "SELECT COUNT(*) AS table_count FROM information_schema.tables WHERE table_schema='$EJBCA_DB_NAME';"
mysql -u "$EJBCA_DB_USER" -p"$EJBCA_DB_PASSWORD" "$EJBCA_DB_NAME" \
  -e "SELECT name FROM CAData;"

# 5. Confirm pilot-root.pem is present and parse its key fields
openssl x509 -in ~/rootCA/phase3/pilot-root.pem -noout \
  -subject -issuer -dates -fingerprint -sha256
```

**Expected results:**

| Check | Expected |
|-------|----------|
| PID file readable | Non-empty integer |
| `ps` output | Process state `S`, cmd contains `standalone.sh` |
| Ports 8080/8443/9990 | `LISTEN` on `127.0.0.1` |
| Health endpoint | `200` |
| DB table count | 37 |
| `CAData` name | `RootCAPilot-ECC384-SHA384` |
| `pilot-root.pem` subject/issuer | `CN=JSIGROUP Pilot Root CA, O=JSIGROUP, C=CA` (self-signed) |
| `pilot-root.pem` validity | notAfter = Jul 21 2026 |

Verified clean on 2026-04-22 (see Entry 4 in [phase3/logs/Phase-3-Execution-Log.md](phase3/logs/Phase-3-Execution-Log.md)).

---

## 1.4 Retroactive Operational Update (2026-04-22)

The pilot root CA activity was executed and validated using a CLI-only flow, recorded retroactively to align this plan with actual operations.

Completed retroactive items:
- Pilot root created by script (`./phase3/phase3-step3-pilot-root.sh`) using EJBCA CLI (`ca init`) and without admin web login.
- Pilot root certificate exported to `./phase3/pilot-root.pem` using EJBCA CLI (`ca getcacert`).
- Root validation passed (4/4 checks) after validator logic correction; evidence written under `./phase3/`.

Retroactive lessons learned:
- UI-independent CA operations are practical and repeatable for this environment when runtime health and deployment naming are consistent.
- EJBCA CLI compatibility depends on deployment naming alignment with `ejbca.ear`.
- WildFly deployment conflicts are best prevented by cleaning stale managed deployment entries before scanner-based deployment.

## 1.5 Lessons Learned & Evidence (2026-04-22)

### Operator Notes & Execution Summary
- Phase 3 pilot root and subordinate were successfully created and validated using CLI-only workflows; all evidence was saved under phase3/logs/.
- Naming conventions and profile set were confirmed before issuance; pilot root and subordinate used 90-day validity for rapid iteration.
- Validation scripts confirmed correct extension rendering, self-signature, and chain verification for both root and subordinate.
- All checks passed for pilot root and subordinate; evidence is suitable for go/no-go decision.
- Manual sign-off and go/no-go decision are pending; technical pilot is complete.

### Evidence Artifacts
- [phase3/logs/Phase-3-Execution-Log.md](phase3/logs/Phase-3-Execution-Log.md)
- [phase3/phase3-cert-validation-pilot-ecc-root-20260422T112215Z.txt](phase3/phase3-cert-validation-pilot-ecc-root-20260422T112215Z.txt)
- [phase3/logs/phase3-cert-validation-pilot-jsigroup-ca-20260422T224614Z.txt](phase3/logs/phase3-cert-validation-pilot-jsigroup-ca-20260422T224614Z.txt)

### Closeout Checklist (as of 2026-04-22)
- [x] Pilot root and subordinate created and validated
- [x] All validation checks passed (root, subordinate, chain)
- [x] Evidence artifacts saved in logs/
- [ ] Go/no-go decision documented (pending)

**Phase 3 pilot is technically complete; pending formal go/no-go decision and sign-off.**

---

## 2. Pilot Environment Setup

### 2.1 Pilot EJBCA Instance

| Component | Specification | Purpose |
|-----------|---------------|---------|
| **Location** | Separate from production root; can be on same offline host or different host | Test isolation; maintains production root unchanged |
| **Database** | Separate MariaDB schema (e.g., `ejbca_pilot`) | Clean state; no production data pollution |
| **Crypto Token** | Separate HSM slot or software token (not production HSM) | Preserve production root private key |
| **Profiles** | Use `RootCAPilot-ECC384-SHA384` and `SubordCAPilot-ECC384-SHA384` (90-day validity) | Rapid iteration; disposable test certificates |
| **Certificate Validity** | 90 days (test period; remainder discarded after pilot) | Enables fast retesting if fallback needed |

### 2.2 Pilot Windows Server 2025 AD CS Instance

| Component | Specification | Purpose |
|-----------|---------------|---------|
| **Host** | Separate Windows Server 2025; not production AD CS | Test isolation |
| **Enrollment Policy** | Match production: standard domain user enrollment, no complex constraints | Representative test scenario |
| **Certificate Template** | Generic web server certificate template (TLS usage) | Tests ECC chain in real Schannel scenario |
| **Domain** | Pilot domain (e.g., `pilot.jsigroup.local`) | Separate from production JSIGROUP domain |
| **Subordinate CA Cert** | Issued by pilot root; installed in pilot AD CS | Tests full issuance chain |

#### Windows Host Preparation Scripts

For configuring the Windows Server 2022/2025 pilot host, use the unified `prepare-ADCS.ps1` wizard:

```powershell
# Copy the script from the Linux host first:
# scp ~/rootCA/artifacts/prepare-ADCS.ps1 user@pilot-windows-host:C:\certs\

# Run from an elevated PowerShell prompt:
.\prepare-ADCS.ps1
```

The script operates as a 4-step interactive wizard:
1. **Clean up / reset old AD CS configuration:** Removes the CA role, clears registry keys/certificates, and requires a reboot. Useful if a previous attempt failed.
2. **Install ADCS role and generate SubCA CSR:** Installs the AD CS binaries and generates the `subca.req` CSR file.
3. **Install signed certificate and start CertSvc:** Automatically installs the IIS Web-Server role, configures the `/crl` application, publishes the root CRL, installs the root CA certificate to the trusted store, installs the subordinate CA certificate, and starts the `CertSvc` service.

If ADCS installation fails repeatedly (e.g., error `0x80073701 ERROR_SXS_ASSEMBLY_MISSING` or component store corruption), use the offline repair script:
```powershell
.\Repair-ADCS-Install.ps1 -RepairSource "E:\sources\install.wim"
```

### 2.3 Pilot Infrastructure Isolation

```
PRODUCTION ISOLATION DIAGRAM
=============================

Production EJBCA Root (Offline):
  - Nitrokey/SmartCardHSM (production HSM)
  - ejbca database
  - RootCAProd-ECC384-SHA384 profile
  - [LOCKED; not used during pilot]

Pilot EJBCA Root (Offline or Test Network):
  - Software token OR separate HSM slot
  - ejbca_pilot database
  - RootCAPilot-ECC384-SHA384 profile
  - [ACTIVE; used during Phase 3]

Production Windows AD CS:
  - JSIGROUP domain
  - [NOT YET DEPLOYED; waits for pilot go/no-go]

Pilot Windows AD CS:
  - pilot.jsigroup.local domain
  - [ACTIVE; tests subordinate issuance]

Test Endpoints:
  - Windows 10/11/Server 2019/2022 mix
  - Domain-joined to pilot.jsigroup.local
  - [ACTIVE; tests chain validation]
```

---

## 3. Pilot Test Execution (Test Matrix)

### 3.1 Mandatory Acceptance Tests

All tests below must **PASS** before proceeding to Phase 4 production ceremony.

#### Test 1: Root Certificate Chain Recognition

**Objective:** Windows recognizes pilot root as trusted CA (after manual installation or GPO deployment).

**Steps:**
1. Export pilot root certificate (DER format)
2. Install in pilot Windows endpoints:
   - Manual: Copy to `Local Machine\Trusted Root Certification Authorities` store
   - GPO: Deploy via Group Policy Object (Computer Config → Policies → Windows Settings → Security Settings → Public Key Policies → Trusted Root Certification Authorities)
3. Verify in Windows Certificate Manager: root appears as trusted CA (no warning icons)
4. Run: `certutil -store root` and grep for pilot root CN

**Expected Result:** PASS  
**Failure Criteria:** Root cert not installed, appears untrusted, or shows warning icon  
**Log Output:** Screenshot of Certificate Manager showing root trusted; output of certutil command

---

#### Test 2: AD CS Subordinate Issuance from Pilot Root

**Objective:** Pilot root can successfully issue subordinate CA certificate to Windows AD CS.

**Steps:**
1. Generate subordinate CSR on pilot AD CS using the wizard:
   - Run `.\prepare-ADCS.ps1` and select **Option 2**.
   - Copy `C:\certs\subca.req` to the Linux host's `artifacts/` folder.
2. Ensure you have the Root CA CRL exported from EJBCA:
   ```bash
   # Extract the CRL from EJBCA:
   /home/jsoehner/rootCA/artifacts/ejbca/ejbca-ce-r9.3.7/bin/ejbca.sh ca getcrl "JSIGROUP-Pilot-RootCA" artifacts/root.crl
   ```
3. Sign CSR via CLI helper:
   ```bash
   # NOTE: If you are retrying this step, you must first delete the old End Entity from EJBCA
   # database because EJBCA enforces unique Subject DNs.
   # mysql -u $EJBCA_DB_USER -p$EJBCA_DB_PASSWORD $EJBCA_DB_NAME -e "DELETE FROM CertificateData WHERE subjectDN='CN=JSIGROUP Intermediate CA - AD CS - PILOT'; DELETE FROM UserData WHERE subjectDN='CN=JSIGROUP Intermediate CA - AD CS - PILOT';" && ejbca.sh clearcache -all

   ./phase3/phase3-sign-adcs-subordinate-csr.sh \
     --csr artifacts/subca.req \
     --ee-profile ADCS2025_SubCA_EE_Profile
   ```
   Output artifacts:
   - `./phase3/pilot-sub-from-adcs.pem`
   - `./phase3/pilot-sub-from-adcs.cer`
4. Verify certificate issued:
   - [ ] Subject: `CN=JSIGROUP Intermediate CA - AD CS - PILOT,...`
   - [ ] Not After: 90 days from signing date
   - [ ] Contains critical Basic Constraints: ca:TRUE, pathLen=0
   - [ ] Contains critical Key Usage: keyCertSign, cRLSign
5. Copy the required files back to the pilot AD CS server into `C:\certs\`:
   - `artifacts/pilot-sub-from-adcs.cer`
   - `artifacts/pilot-root.cer`
   - `artifacts/root.crl`
6. Install subordinate cert in pilot AD CS using the wizard:
   - Run `.\prepare-ADCS.ps1` and select **Option 3**.
   - The script will configure IIS, host the `root.crl`, install the root certificate, install the subordinate certificate, and start the `CertSvc` service automatically.
7. Verify service healthcheck: all tests pass (`certutil -pulse`)

**Expected Result:** PASS  
**Failure Criteria:** CSR signing fails, AD CS service fails to start, cert validation errors in Event Viewer.  
**Log Output:** EJBCA issuance log entry; Windows AD CS certutil pulse output; Event Viewer screenshot

---

#### Test 3: Pilot AD CS Enrollment Workflow (Standalone CA)

**Objective:** Test users can request and retrieve certificates from the pilot AD CS Standalone subordinate.

**Steps:**
1. Configure pilot Windows endpoints to trust pilot root (Test 1 above).
2. On a pilot endpoint (e.g., an IIS server), generate a new Certificate Signing Request (CSR):
   - Use the IIS Manager "Create Certificate Request" wizard, OR
   - Create a `request.inf` file and run `certreq -new request.inf req.csr`.
3. Submit the CSR to the AD CS Standalone CA:
   - Copy `req.csr` to the CA server.
   - Run `certreq -submit req.csr` and select the Standalone CA from the popup.
   - The command will return a `RequestId` and state that the request is pending.
4. Issue the certificate manually (Standalone CAs require approval):
   - Open the Certification Authority MMC (`certsrv.msc`) on the CA server.
   - Navigate to **Pending Requests**.
   - Right-click the request ID, select **All Tasks** > **Issue**.
5. Retrieve and install the issued certificate:
   - In the CA MMC, go to **Issued Certificates**, double-click the cert, and export it as a `.cer` file, OR
   - Run `certreq -retrieve <RequestId> issued.cer` to save the file.
   - Copy `issued.cer` back to the endpoint and complete the pending request (e.g., in IIS or via `certreq -accept issued.cer`).
6. Verify enrollment succeeds:
   - Open Microsoft Management Console (mmc) Certificates snap-in; verify:
   - [ ] Certificate details show full chain (root → subordinate → end-entity)
   - [ ] No chain building errors
   - [ ] Signature algorithm matches profile

**Expected Result:** PASS  
**Failure Criteria:** Request cannot be submitted; CA fails to issue cert; chain shows errors.  
**Log Output:** Certreq output; MMC screenshot showing full chain; AD CS issued certificates view.

---

#### Test 4: Certificate Chain Building and Validation

**Objective:** Windows automatically builds and validates the full root → subordinate → end-entity chain.

**Steps:**
1. Export end-entity certificate from test 3 (DER format)
2. On a **different** Windows endpoint (no pre-installed intermediates):
   - Install only the pilot root cert in Trusted Root store (NOT the subordinate)
   - Do NOT install the subordinate cert in any store
3. Use `certutil.exe` to verify chain building:
   ```
   certutil -verify -urlfetch end-entity.cer
   ```
   - `-verify`: Validate certificate chain
   - `-urlfetch`: Enable URL fetching for Authority Info Access (AIA) chain building
4. Expected output: Full chain validated; CRL verification successful (if CRL endpoint available)
5. Alternative test (via OpenSSL on Linux endpoint):
   ```
   openssl verify -CAfile root.pem -CApath /etc/ssl/certs end-entity.pem
   ```

**Expected Result:** PASS (chain built and validated end-to-end)  
**Failure Criteria:** Chain building fails; AIA endpoint inaccessible; CRL retrieval fails; intermediate not found  
**Log Output:** Certutil verify output; OpenSSL verify output

---

#### Test 5: TLS/Schannel Validation (Real-World Usage)

**Objective:** Test ECC certificate in actual TLS handshake (Schannel). This is the **critical test** for AD CS subordinate viability.

**Steps:**
1. On a test Windows Server 2025 endpoint, configure IIS or similar TLS service:
   - Bind the end-entity certificate from test 3 to an HTTPS listener
   - Service URL: `https://pilot-web.pilot.jsigroup.local`
2. From a client endpoint (Windows 10/11, also in pilot domain):
   - Open browser to `https://pilot-web.pilot.jsigroup.local`
   - Schannel validates certificate chain and signature
3. Observe browser behavior:
   - [ ] No certificate warning (green lock icon or valid cert indicator)
   - [ ] Chain displays correctly in certificate details
   - [ ] No "Untrusted issuer" or "Invalid signature" errors
4. Repeat test with clients of varying OS versions:
   - Windows 7 SP1 (minimum supported)
   - Windows 10 (current)
   - Windows Server 2019 (older server)
   - Windows Server 2022 (current server)
   - MacOS / Linux (optional; tests cross-platform ECC support)

**Expected Result:** PASS on all tested OS versions  
**Failure Criteria:** Certificate error warning; untrusted chain indicator; Schannel handshake failures; clients unable to establish TLS connection  
**Log Output:** Browser certificate info screenshot; Schannel Event Viewer logs; PowerShell Test-NetConnection output

---

#### Test 6: CRL Publication and Retrieval

**Objective:** Verify CRL issuance, publication, and client retrieval workflow.

**Steps:**
1. In pilot EJBCA: sign a pilot CRL (signed by pilot root):
   ```bash
   # In EJBCA admin: go to Certification Authorities → CAName → Generate CRL
   # Or via CLI: ejbca.sh gencrl CAPilot
   ```
2. Export pilot CRL (DER format) to distribution endpoint:
   - Publication URL: `http://ca-pilot.pilot.jsigroup.local/crl/root.crl`
   - Store as `/var/www/html/crl/root.crl`
3. From Windows client, retrieve CRL:
   ```
   certutil -urlcache http://ca-pilot.pilot.jsigroup.local/crl/root.crl crl.crt
   certutil -dump crl.crt  # Verify CRL format and entries
   ```
4. Verify CRL properties:
   - [ ] Valid signature (signed by pilot root)
   - [ ] Issue date: today (or near-recent)
   - [ ] Next update: at least 7 days / 90 days (depending on CRL refresh SOP)
   - [ ] No revocation entries (expected; test certs not revoked yet)
5. Validate chain includes CRL check:
   ```
   certutil -verify -urlfetch -crls end-entity.cer
   ```

**Expected Result:** PASS; CRL downloaded, parsed, and validated successfully  
**Failure Criteria:** CRL endpoint inaccessible; CRL signature invalid; CRL parsing errors; stale CRL (Next Update in past)  
**Log Output:** Certutil dump output; CRL retrieval timestamps; endpoint access logs

---

#### Test 7: Certificate Renewal on AD CS

**Objective:** Verify that AD CS can renew certificates before expiry without issues.

**Steps:**
1. Configure certificate template for auto-renewal (Group Policy: Computer Config → Policies → Windows Settings → Security Settings → Public Key Policies → Certificate templates)
2. On a test Windows endpoint, trigger certificate renewal:
   - Powershell: `Renew-Certificate -Thumbprint <thumbprint>` (if supported on OS)
   - OR manual: Request new cert from same template; Windows marks old cert for replacement
3. Monitor renewal process:
   - [ ] New certificate issued within 24 hours
   - [ ] Chain still validates (new cert signed by same subordinate)
   - [ ] Old certificate remains in store (optional; can be archived or removed)
4. Verify renewal does NOT require re-enrollment from scratch

**Expected Result:** PASS; renewal succeeds, new certificate issued, no re-enrollment required  
**Failure Criteria:** Renewal fails; new cert not issued; chain validation fails on renewed cert; client must manually re-enroll  
**Log Output:** AD CS renewal log; renewed certificate details; timelines

---

#### Test 8: Algorithm Support on Diverse Endpoints (ECC-Specific)

**Objective:** For ECC P-384 primary algorithm test, verify ECC signature verification works on representative OS versions.

**Steps:**
1. Issue end-entity certificates with explicit **ECC P-384** algorithm (from subordinate profile):
   - Algorithm: `ecdsa-with-SHA384`
   - Verify via: `openssl x509 -text -noout | grep "Signature Algorithm"`
2. Test on endpoints:
   - Windows 7 SP1: Attempt TLS handshake; check if Schannel accepts ECC P-384
   - Windows 10+: Expected to support ECC natively
   - Windows Server 2019+: Expected to support ECC natively
3. For Windows 7 or older, test fallback behavior:
   - If ECC unsupported: client may fail or trigger Schannel fallback
   - Capture error event in Event Viewer (Schannel errors)
4. Document minimum OS version for ECC P-384 support

**Expected Result:** PASS on Windows 10+ and Server 2019+; documented on Windows 7 SP1 (if supported, or noted as unsupported)  
**Failure Criteria:** Windows 10/Server 2022 cannot validate ECC P-384 signature; Schannel crashes; impossible to use ECC in production  
**Log Output:** Supported OS list; Windows 7 SP1 test results (if applicable); Event Viewer Schannel logs

---

### 3.2 Post-Test Analysis & Defect Severity Classification

After all tests complete, classify any defects:

| Severity | Example | Impact | Action |
|----------|---------|--------|--------|
| **Critical** | "ECC P-384 not supported by Windows 10 Schannel; cannot issue certs" | Blocks selected algorithm; must fallback | **FAIL Pilot**; switch to fallback algorithm |
| **High** | "Windows 7 SP1 cannot validate ECC P-384; breaks for 15% of org endpoints" | Major client compatibility loss | **FAIL Pilot** if Windows 7 support required; else **PASS with documentation** |
| **Medium** | "AD CS renewal takes 48 hours instead of expected 24 hours due to policy delay" | Operational delay; acceptable | **PASS with SOP update**; adjust renewal trigger timing |
| **Low** | "Certificate details UI in MMC shows garbled UTF-8 in CRL DP URI" | Cosmetic; no functional impact | **PASS**; track for Phase 5 polish |

---

## 4. Go/No-Go Decision Gate

### 4.1 Pass Criteria (Green Light → Phase 4)

**ALL of the following must be true:**

```
GO / NO-GO DECISION CHECKLIST
==============================

Pilot Test Results:
  [ ] Test 1 (Chain Recognition): PASS
  [ ] Test 2 (Subordinate Issuance): PASS
  [ ] Test 3 (Enrollment Workflow): PASS
  [ ] Test 4 (Chain Building): PASS
  [ ] Test 5 (Schannel/TLS): PASS on Windows 10+, Server 2019+
  [ ] Test 6 (CRL Retrieval): PASS
  [ ] Test 7 (Certificate Renewal): PASS
  [ ] Test 8 (Algorithm Support): PASS on target OS versions

Defect Classification:
  [ ] Zero CRITICAL defects
  [ ] Zero unmitigated HIGH defects
  [ ] MEDIUM defects documented with SOP updates (if any)
  [ ] LOW defects tracked for Phase 5 (if any)

Algorithm Decision:
  [ ] ECC P-384 viable for production (if primary) OR
  [ ] Fallback algorithm (all-RSA or ECC P-256) validated if ECC P-384 failed

Officer Attestation:
  [ ] Root CA Officer: "Algorithm selection approved for production"  ___________  Date: __/__/__
  [ ] Security Officer: "Pilot tests comprehensive; ready for key ceremony"  ___________  Date: __/__/__
  [ ] Auditor: "Defects classified; go/no-go criteria met"  ___________  Date: __/__/__

DECISION: [ ] GO (Phase 4 Approved) [ ] NO-GO (Repeat Phase 3 with Fallback)
```

---

### 4.2 No-Go Scenario (Red Light → Fallback Algorithm)

If ANY critical or unmitigated HIGH defects exist:

1. **Document the failure:** Create incident record with:
   - Failing test name and exact error
   - Root cause analysis (if known)
   - Affected OS versions or configurations
   - Recommendation (e.g., "ECC P-384 not supported on Windows 7; switch to all-RSA")

2. **Select fallback algorithm:**
   - If ECC P-384 failed: test `SubordCAPilot-RSA4096-SHA256` (all-RSA chain)
   - If all-RSA failed (unlikely): escalate to management for alternative approach

3. **Repeat Phase 3** with fallback algorithm:
   - Issue new root and subordinate using RSA profiles
   - Re-run all 8 tests above with RSA chain
   - Document second pilot outcome

4. **Re-attempt go/no-go decision:**
   - If fallback chain passes all tests: **GO** with fallback algorithm
   - If fallback also fails: **ESCALATE** (all algorithms failed; underlying Windows or infrastructure issue)

---

## 5. Pilot Cleanup (Post-Decision)

### 5.1 If GO Decision (Proceed to Phase 4)

1. **Archive pilot artifacts:**
   - Export pilot root, subordinate, and sample end-entity certs for reference
   - Archive pilot test results (screenshots, logs, timelines)
   - Store in `~/rootCA/pilot-artifacts/` with date stamp

2. **Destroy pilot data:**
   - Delete pilot EJBCA database (`DROP DATABASE ejbca_pilot;`)
   - Delete pilot certificates from issuing token (if HSM-based)
   - Wipe test endpoints (if temporary lab equipment)

3. **Proceed to Phase 4:** Production key ceremony (use production profiles on production HSM)

### 5.2 If NO-GO Decision (Repeat Phase 3 with Fallback)

1. **Preserve pilot-ECC artifacts** for post-mortem analysis
2. **Issue new pilot root and subordinate** using fallback algorithm (`SubordCAPilot-RSA4096-SHA256`)
3. **Re-run all 8 tests** with fallback chain
4. **Document that production will use fallback algorithm** (not original ECC P-384 choice)
5. **Update Phase 4 procedures** to use selected fallback algorithm's profiles and key credentials

---

## 6. Success Measurement (Summary)

| Outcome | Definition | Next Phase |
|---------|-----------|-----------|
| **GO (ECC P-384)** | All 8 tests PASS; ECC P-384 viable; officer sign-off complete | **Phase 4**: Production key ceremony (ECC P-384 root + subordinate) |
| **GO (Fallback RSA)** | All 8 tests PASS with all-RSA chain; fallback viable; officer sign-off | **Phase 4**: Production key ceremony (RSA 4096 root + subordinate) |
| **NO-GO (Technical)** | Critical test failures; algorithm not supported by Windows CNG or Schannel | **Return to Phase 3**: Retry with different algorithm; escalate if all fail |
| **NO-GO (Policy)** | Defects acceptable for Phase 3 but require SOP/policy updates before Phase 4 | **Governance Review**: Approve SOP changes; re-decide go/no-go |

---

**End of Phase 3 Documentation**
