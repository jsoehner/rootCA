# Phase 3 Execution Log

**Phase Status:** IN PROGRESS  
**Start Date:** 2026-04-20  
**Authorized by:** Jeff Soehner (Phase 2 sign-off, 2026-04-20)  
**Decision Gate:** Go/no-go for Phase 4 production key ceremony  

---

## Entry Gate Verification (2026-04-20)

| Item | Status |
|------|--------|
| Phase 2 sign-off recorded in Phase-2-Execution-Log.md | ✅ DONE |
| Phase 2 sign-off recorded in Phase-2-Crypto-Profiles.md | ✅ DONE |
| Naming frozen (`JSIGROUP`) | ✅ DONE |
| EJBCA runtime healthy (admin=200, ocsp=200) | ✅ DONE |
| RootCAPilot-ECC384-SHA384 profile confirmed present | ✅ DONE (Phase 2 evidence) |
| SubordCAPilot-ECC384-SHA384 profile confirmed present | ✅ DONE (Phase 2 evidence) |
| SubordCAPilot-RSA4096-SHA256 profile confirmed present (fallback) | ✅ DONE (Phase 2 evidence) |

---

## Execution Checklist

### Pilot Root Preparation

```
[ ] Separate pilot database/schema selected (e.g., ejbca_pilot) OR existing DB
    confirmed isolated from production data
[ ] Separate pilot crypto token or software token confirmed
[ ] Pilot profile set confirmed in running EJBCA instance:
    [ ] RootCAPilot-ECC384-SHA384
    [ ] SubordCAPilot-ECC384-SHA384
    [ ] SubordCAPilot-RSA4096-SHA256 (fallback)
```

### Pilot Issuance

```
[x] Pilot root CA created with 90-day validity using RootCAPilot-ECC384-SHA384
[x] Pilot root certificate exported (PEM) to ./phase3/pilot-root.pem
[x] Pilot subordinate CSR generated on Windows AD CS
[x] Pilot subordinate signed using SubordCAPilot-ECC384-SHA384 (see Entry 8–9 for DN/profile troubleshooting)
[x] Pilot subordinate certificate exported (PEM/DER) to ./phase3/pilot-sub-from-adcs.pem and .cer
```

### Windows Validation (Test Matrix — Phase-3-Pilot-Testing.md §3)

```
[ ] Test 1: Root chain recognition (trusted root install + certutil -store root)
[ ] Test 2: AD CS subordinate issuance from pilot root
[ ] Test 3: Pilot AD CS enrollment workflow
[ ] Test 4: Certificate chain building and validation (certutil -verify -urlfetch)
[ ] Test 5: TLS/Schannel validation
[ ] Test 6: CRL publication and retrieval
```

### Evidence and Decision

```
[x] All command output saved under ~/rootCA/phase3/
[ ] All screenshots captured and named
[ ] Go/no-go decision documented in this log
[ ] If ECC fails: fallback RSA4096 run authorized and scheduled
```

---

## Execution Log Entries

### Entry 1 — Phase 3 Opened (2026-04-20)

- Phase 2 sign-off confirmed (Jeff Soehner, 2026-04-20).
- EJBCA runtime: admin=200, ocsp=200.
- Confirmed pilot profiles from Phase 2 evidence:
  - `RootCAPilot-ECC384-SHA384` — 90-day validity, ECC P-384 + SHA-384
  - `SubordCAPilot-ECC384-SHA384` — 90-day validity, ECC P-384 + SHA-384
  - `SubordCAPilot-RSA4096-SHA256` — 90-day validity, RSA 4096 + SHA-256 (fallback)
- Next action: Stand up isolated pilot scope (§2.1) and create pilot root CA.

---

### Entry 2 — Pilot Infrastructure Scripts Created (2026-04-22)

Runtime baseline confirmed healthy before Phase 3 setup:
- `healthcheck/ejbcahealth` HTTP 200
- `status/ocsp` HTTP 200
- MariaDB active; `ejbca` production database intact with all EJBCA schema tables present
- WildFly MariaDB module deployed (`mariadb-java-client.jar` v3.5, `java:/EjbcaDS` bound)

Database migration completed (H2 → MariaDB persistent storage):
- Production EJBCA database: `ejbca` (MariaDB), credentials in `phase1/.db-credentials`
- All CA data now survives WildFly restarts

Phase 3 pilot infrastructure scripts created:

| Script | Purpose |
|--------|---------|
| `phase3/phase3-setup-pilot.sh` | One-time setup: creates isolated `ejbca_pilot` MariaDB DB and writes `phase3/.pilot-db-credentials` |
| `phase3/phase3-run-wildfly30-pilot.sh` | Start EJBCA on pilot DB; stops any running instance, reconfigures datasource to `ejbca_pilot` |
| `phase3/phase3-run-wildfly30-prod.sh` | Restore EJBCA to production DB after pilot testing |
| `phase3/phase3-validate-pilot-certs.sh` | OpenSSL validation of pilot root/sub/end-entity certs; writes structured evidence artifacts |

Isolation model confirmed:
- Production database (`ejbca`) is untouched when pilot scripts are active
- Pilot database (`ejbca_pilot`) is fully separate; WildFly switches datasource at runtime
- Only one EJBCA instance runs at a time (port 8080); `phase3-run-wildfly30-prod.sh` safely restores production context

**Checklist update:**

```
PILOT ROOT PREPARATION:
   [x] Separate pilot database/schema: ejbca_pilot (created by phase3-setup-pilot.sh)
   [x] Separate pilot crypto token: software token via EJBCA admin (no production HSM)
   [x] RootCAPilot-ECC384-SHA384 profile confirmed present (Phase 2 evidence)
   [x] SubordCAPilot-ECC384-SHA384 profile confirmed present (Phase 2 evidence)
   [x] SubordCAPilot-RSA4096-SHA256 profile confirmed present (Phase 2 evidence — fallback)
```

**Immediate next steps (operator):**

```bash
# 1. Create pilot database
./phase3/phase3-setup-pilot.sh

# 2. Switch EJBCA to pilot database
./phase3/phase3-run-wildfly30-pilot.sh

# 3. Create/export pilot root CA via EJBCA CLI only (no admin web login)
./phase3/phase3-step3-pilot-root.sh

# 4. Generate pilot subordinate CSR on Windows AD CS, submit to EJBCA,
#    sign with SubordCAPilot-ECC384-SHA384, export to ~/rootCA/phase3/pilot-sub.pem

# 5. Validate full pilot chain
./phase3/phase3-validate-pilot-certs.sh \
  --root-cert ./phase3/pilot-root.pem \
  --sub-cert  ./phase3/pilot-sub.pem \
  --label pilot-ecc-chain
```

---

### Entry 3 — Retroactive CLI-Only Root CA Completion (2026-04-22)

This entry is recorded retroactively to capture the actual Phase 3 root issuance path used during execution.

Activity completed:
- Pilot WildFly runtime confirmed healthy (admin and OCSP probe HTTP 200).
- Pilot root CA was created without UI interaction using EJBCA CLI:
  - CA name: `RootCAPilot-ECC384-SHA384`
  - DN: `CN=JSIGROUP Pilot Root CA, O=JSIGROUP, C=CA`
  - Algorithm: ECDSA P-384 with SHA-384
  - Validity: 90 days
- Pilot root certificate exported to `./phase3/pilot-root.pem`.
- Validation rerun after script correction: 4 PASS, 0 FAIL, validator exit code 0.

Supporting evidence:
- `./phase3/pilot-root.pem`
- `./phase3/logs/phase3-step3-cli.log`
- `./phase3/logs/phase3-cert-validation-pilot-ecc-root-20260422T112215Z.txt`

Technical corrections recorded:
- Deployment naming standardized to `ejbca.ear` (required for `bin/ejbca.sh` CLI EJB lookup compatibility).
- Startup scripts updated to clear stale managed deployments before scanner deployment to avoid context path conflicts.
- Root validator self-signed comparison corrected by normalizing `subject`/`issuer` values prior to equality check.

Lessons learned:
- EJBCA CLI is sufficient for pilot root CA lifecycle operations; UI access is not required for this phase activity.
- Deployment name and CLI internal app lookup must remain aligned (`ejbca.ear`); mismatches cause CLI EJB resolution failures.
- Removing stale managed deployments in WildFly must include management model cleanup, not only filesystem cleanup.
- Validation scripts should compare normalized certificate fields and tie final status text to the same pass/fail condition used for exit code.

---

### Entry 4 — Pilot State Verification (2026-04-22)

Full end-to-end state verification performed after returning to the project. All checks passed.

**Commands run:**

```bash
# WildFly PID check
cat ~/rootCA/phase3/phase3-wildfly30-pilot.pid          # → 39825
ps -p 39825 --no-headers -o pid,stat,cmd                # → S  /bin/sh ./bin/standalone.sh -b 127.0.0.1

# Port binding
ss -tlnp | grep -E '8080|8443|9990'
# → LISTEN 127.0.0.1:8080, 127.0.0.1:8443, 127.0.0.1:9990

# EJBCA health
curl -o /dev/null -sw "%{http_code}" http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth
# → 200

# Pilot DB
mysql -u ejbca_pilot -p<redacted> ejbca_pilot -e "SHOW TABLES;"    # → 37 tables
mysql -u ejbca_pilot -p<redacted> ejbca_pilot -e "SELECT name FROM CAData;"
# → RootCAPilot-ECC384-SHA384

# Pilot root cert
openssl x509 -in ~/rootCA/phase3/pilot-root.pem -noout -subject -issuer -dates -fingerprint -sha256
# → subject=CN=JSIGROUP Pilot Root CA, O=JSIGROUP, C=CA
# → issuer=CN=JSIGROUP Pilot Root CA, O=JSIGROUP, C=CA
# → notBefore=Apr 22 11:18:12 2026 GMT  notAfter=Jul 21 11:18:11 2026 GMT
# → SHA256 Fingerprint=D3:6C:B3:73:B2:39:C8:0E:DB:4D:4D:0B:8B:76:8B:9F:37:30:A0:19:CB:1B:30:3A:55:05:3B:13:A2:6D:6B:BA
```

**Results:**

| Check | Result |
|-------|--------|
| Pilot WildFly running (PID 39943) | ✅ PASS |
| Ports 8080 / 8443 / 9990 bound on 127.0.0.1 | ✅ PASS |
| EJBCA health endpoint HTTP 200 | ✅ PASS |
| `ejbca_pilot` DB has 37 tables | ✅ PASS |
| `RootCAPilot-ECC384-SHA384` present in CAData | ✅ PASS |
| `pilot-root.pem` subject/issuer self-signed | ✅ PASS |
| `pilot-root.pem` validity expires Jul 21 2026 | ✅ PASS |

Verification procedure captured in [Phase-3-Pilot-Testing.md §1.3](../Phase-3-Pilot-Testing.md).

---

### Entry 5 — Pilot Certificate Reissue With Canonical Identity (2026-04-22)

Objective:
- Reissue pilot certificate material using canonical identity values `O=JSIGROUP, C=CA`.

Actions completed:
1. Attempted pilot runtime restore:
   - `./phase3/phase3-run-wildfly30-pilot.sh --fail-fast`
   - Runtime probes returned `404`; pilot startup recorded a classloader conflict warning in `./phase3/logs/phase3-wildfly30-pilot.log`.
2. Executed CA reissue script in current runtime context:
   - `./phase2/phase2-reissue-ca-material.sh`
   - Root: `JSIGROUP-Pilot-RootCA` (ID: `-2118228720`)
   - Subordinate: `JSIGROUP-Pilot-SubCA` (signed by pilot root)
3. Exported replacement pilot artifacts:
   - `./phase3/pilot-root.pem`
   - `./phase3/pilot-sub.pem`
4. Validation completed with expected CA constraints and signature algorithm.

Pilot replacement certificate highlights:
- Pilot root subject/issuer: `CN=JSIGROUP Pilot Root CA, O=JSIGROUP, C=CA`
- Pilot root SHA-256: `35:F5:73:4B:23:9B:8E:6A:D4:EF:FE:FF:2B:D5:D1:81:F7:B8:0E:46:9C:7C:B4:C8:3D:0C:8F:D3:8C:A8:C0:86`
- Pilot subordinate subject: `CN=JSIGROUP Intermediate CA - AD CS - PILOT, OU=Certificate Authority, O=JSIGROUP, C=CA`
- Pilot subordinate issuer: `CN=JSIGROUP Pilot Root CA, O=JSIGROUP, C=CA`
- Pilot subordinate SHA-256: `BC:41:A9:1B:F9:10:16:50:7D:53:6B:85:17:EE:54:8B:A4:3E:F3:84:F7:EC:07:B3:EE:76:5C:0A:BD:AA:A3:FF`

Evidence:
- `./phase2/logs/phase2-reissue-20260422T152841Z.log`
- `./phase2/logs/phase2-cert-validation-pilot-jsigroup-ca-20260422T152946Z.txt`
- `./phase3/pilot-root.pem`
- `./phase3/pilot-sub.pem`

---

### Entry 6 — Pilot Cert Validation Refresh (2026-04-22)

Objective:
- Generate a fresh, timestamped validation artifact from the current `pilot-root.pem` and `pilot-sub.pem` material before continuing with remaining interoperability tests.

Action completed:
- Executed:

```bash
./phase3/phase3-validate-pilot-certs.sh \
   --root-cert ./phase3/pilot-root.pem \
   --sub-cert ./phase3/pilot-sub.pem \
   --label pilot-jsigroup-ca
```

Result summary:
- Validation timestamp: `2026-04-22 22:46:14 UTC`
- PASS: 7
- FAIL: 0
- Result: `ALL CHECKS PASSED`

Verified properties:
- Root CA is self-signed (`subject == issuer`)
- Root basic constraints include `CA:TRUE`
- Root key usage includes `keyCertSign` and `cRLSign`
- Root self-signature verifies
- Subordinate basic constraints include `CA:TRUE, pathLen=0`
- Subordinate chain verifies against pilot root

Evidence:
- `./phase3/logs/phase3-cert-validation-pilot-jsigroup-ca-20260422T224614Z.txt`

Gate interpretation:
- This refresh confirms Linux-side certificate structure and root-to-subordinate chain integrity only.
- Phase 3 mandatory Windows interoperability tests (Test 1 through Test 6) and formal GO/NO-GO decision remain pending.

---

### Entry 7 — Operator Worksheet Prepared For Mandatory Test Matrix (2026-04-22)

Objective:
- Standardize execution and evidence capture for mandatory Phase 3 interoperability tests to reduce decision-gate ambiguity.

Action completed:
- Created operator worksheet:
   - `./phase3/Phase-3-Test-Execution-Worksheet.md`
- Prepared Windows-ready pilot root certificate artifact:
   - `./phase3/pilot-root.cer` (DER)

Worksheet coverage:
- Test 1: Root chain recognition
- Test 2: AD CS subordinate issuance
- Test 3: Enrollment workflow
- Test 4: Chain building and URL fetch validation
- Test 5: TLS/Schannel validation
- Test 6: CRL publication/retrieval
- Final gate summary section with GO/NO-GO recommendation fields

Immediate next action:
- Execute Tests 1 through 6 using the worksheet and populate pass/fail evidence, then complete the GO/NO-GO decision block in this log.

---

### Entry 8 — External AD CS CSR Signing Workflow Update (2026-04-24)

Objective:
- Operationalize a repeatable CLI-only signing workflow for externally generated AD CS subordinate CSRs.

Actions completed:
1. Added signing helper script:
   - `./phase3/phase3-sign-adcs-subordinate-csr.sh`
2. Validated CSR intake for Windows `certreq` format:
   - Handles `BEGIN NEW CERTIFICATE REQUEST` by normalizing to standard PKCS#10 PEM.
3. Confirmed runtime and CA/profile presence checks in script preflight.
4. Observed and documented issuance constraint in current EJBCA state:
   - `ra addendentity` can fail with:
     - `Couldn't find certificate profile (...) among available certificate profiles`
   - Root cause: selected end entity profile does not permit `SubordCAPilot-ECC384-SHA384`.

Lesson learned and workflow change:
- External CSR signing now requires an explicit end entity profile that allows the subordinate CA certificate profile used for signing.
- The helper script now accepts `--ee-profile` and fails with actionable remediation if profile permissions are insufficient.

Impact on Test 2:
- Test 2 remains pending until the pilot signing end entity profile is created/imported and used with:
  - `./phase3/phase3-sign-adcs-subordinate-csr.sh --csr <path> --ee-profile <profile>`

---

### Entry 9 — ADCS2025 EE Profile Naming And CSR PoPO Validation Update (2026-04-24)

Objective:
- Finalize end entity profile naming for Windows Server 2025 AD CS subordinate issuance and validate signing readiness.

Actions completed:
1. Imported renamed EE profile for pilot AD CS subordinate issuance:
    - Profile name: `ADCS2025_SubCA_EE_Profile`
    - Source XML: `./phase3/profiles/entityprofile_ADCS2025_SubCA_EE_Profile-198381620.xml`
2. Cleaned profile XML workspace to keep only the active ADCS2025 profile definition:
    - Removed:
       - `./phase3/profiles/entityprofile_SubCA_EE_Profile-198381618.xml`
       - `./phase3/profiles/entityprofile_SubCA_EE_Profile_v2-198381619.xml`
3. Updated signing helper defaults to use ADCS2025 profile:
    - `./phase3/phase3-sign-adcs-subordinate-csr.sh`
4. Added early CSR PoPO validation in signing helper:
    - Script now runs `openssl req -verify -noout` after header normalization and fails fast if invalid.

Observed blocker:
- Current CSR (`~/JSI-Root.jsigroup.local_jsigroup-JSI-ROOT-CA-1.req`) fails PoPO validation:
   - `CSR self-signature verification failed (PoPO invalid)`
- This directly explains EJBCA issuance failure observed earlier:
   - `Could not create certificate: POPO verification failed.`

Operational next step:
- Regenerate subordinate CSR on AD CS and rerun signing helper with ADCS2025 profile.

Validated rerun command:
```bash
./phase3/phase3-sign-adcs-subordinate-csr.sh \
   --csr ~/JSI-Root.jsigroup.local_jsigroup-JSI-ROOT-CA-1.req \
   --ee-profile ADCS2025_SubCA_EE_Profile
```

---

### Lessons Learned — Subject DN and End Entity Profile Mapping (2026-04-26)

Multiple failed attempts to sign the AD CS subordinate CSR were due to mismatches between the CSR Subject DN and the requirements of the EJBCA end entity profile. Key points:

- The end entity profile must allow the exact DN structure present in the CSR (e.g., correct number of OU and O fields).
- DN normalization is required: extra or missing OU/O fields will cause registration to fail with errors like "Wrong number of ORGANIZATIONALUNIT fields in Subject DN."
- The helper script now enforces early PoPO validation and explicit end entity profile selection to avoid silent failures.
- Successful issuance was achieved only after aligning the CSR DN with the profile and using the correct EE profile (`ADCS2025_SubCA_EE_Profile`).

This should be referenced for future subordinate onboarding and profile design.

---

### Entry 10 -- Windows AD CS Host Repair Script Added (2026-04-25)

Objective:
- Resolve Windows Server 2022 component store corruption (`0x80073701 ERROR_SXS_ASSEMBLY_MISSING`) that was blocking ADCS reinstallation on the pilot Windows host.

Actions completed:
1. Diagnosed CBS log error: missing assembly `Microsoft-Windows-CertificateServices-CAManagement-Deployment-LanguagePack` at build `10.0.20348.3692` while OS was at `10.0.20348.4163`.
2. Created repair and reinstall script:
   - `~/rootCA/artifacts/Repair-ADCS-Install.ps1`
3. Script automates:
   - DISM ScanHealth and RestoreHealth (online or offline WIM source)
   - SFC /scannow with reboot checkpoint
   - Clean ADCS feature removal (`-Remove`)
   - ADCS-Cert-Authority + RSAT tools reinstall
   - Feature state verification
   - Inline next-step guidance for CSR generation and Linux signing workflow
4. References added to:
   - `~/rootCA/Phase-3-Pilot-Testing.md` (Section 2.2)
   - `~/rootCA/phase3/Phase-3-Test-Execution-Worksheet.md` (Test 2 preconditions)

Usage on Windows pilot host:
```powershell
# Online repair:
.\Repair-ADCS-Install.ps1

# Offline repair (mount WS2022 ISO first):
.\Repair-ADCS-Install.ps1 -RepairSource "E:\sources\install.wim"
```

Logs saved to: `C:\Temp\phase3-adcs-repair\` on the Windows host.

Impact on Test 2:
- Test 2 remains PENDING pending a fresh CSR from the repaired Windows host.

---

## Test Results

| Test | Result | Date | Notes |
|------|--------|------|-------|
| Test 1: Root chain recognition | PENDING | | |
| Test 2: AD CS subordinate issuance | PENDING | | |
| Test 3: AD CS enrollment workflow | PENDING | | |
| Test 4: Chain building & validation | PENDING | | |
| Test 5: TLS/Schannel validation | PENDING | | |
| Test 6: CRL publication & retrieval | PENDING | | |

---

## Next Steps (as of 2026-04-26)

- Execute Windows interoperability tests (Test 1–6) using the worksheet in phase3/Phase-3-Test-Execution-Worksheet.md.
- Capture and save all evidence files as specified.
- Update this log and the worksheet with PASS/FAIL results and notes for each test.
- Complete the GO/NO-GO decision block once all tests are complete.

---

## Go/No-Go Decision Record

```
PHASE 3 GO/NO-GO DECISION
Date: __/__/____

Test results summary:
[ ] All mandatory tests passed (go decision)
[ ] One or more mandatory tests failed (no-go; fallback or remediation required)

Algorithm selected for production:
[ ] ECC P-384 + SHA-384 (primary)
[ ] RSA 4096 + SHA-256 (fallback)

Decision: [ ] GO — proceed to Phase 4 key ceremony
          [ ] NO-GO — run fallback pilot or remediate

Officer A: ________________________  Date: __/__/____
Officer B: ________________________  Date: __/__/____
```
