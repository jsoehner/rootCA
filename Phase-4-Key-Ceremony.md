# Phase 4: Production Key Ceremony and Root Creation

**Phase Status:** NOT STARTED; BLOCKED PENDING PHASE 3 GO DECISION  
**Date Created:** 2026-04-19  
**Phase Dependencies:** Phase 3 (Pilot) must result in **GO** decision before Phase 4 may begin  
**Criticality:** This phase irreversibly generates the root private key and root certificate; all officers and auditors must attest approval  

---

## 1. Overview

Phase 4 executes the formal **offline key ceremony** to generate the production root CA private key (on HSM) and issue the production root certificate. After this phase, the root private key is immutable and will remain on HSM for the 20-year certificate validity period. This phase is **irreversible**:

- Root private key cannot be exported, backed up, or recovered if HSM fails (disaster recovery path: new key ceremony + reissue subordinates)
- Root certificate is fixed; cannot be modified (only expires at end of 20-year term)
- All decisions made in Phases 0-3 (algorithm, naming, constraints, policies) are locked in

**Deliverables:**
- Root CA private key (generated on-HSM; never exported)
- Root CA certificate (DER-encoded, self-signed, 20-year validity)
- Root certificate fingerprint and serial number (recorded in formal ceremony log)
- Signed ceremony attestations (three officers/auditors: Officer A, Officer B, Auditor)
- Initial root CRL (empty, no revocation entries; issued by root key immediately after cert generation)
- Formal sign-off documentation enabling Phase 5 (AD CS subordinate issuance)

---

## 2. Pre-Ceremony Verification (24 Hours Prior)

### 2.1 Ceremony Readiness Checklist

All items must be verified and checked **at least 24 hours before** the scheduled ceremony date:

```
PHASE 4 PRE-CEREMONY VERIFICATION
==================================

PERSONNEL AVAILABILITY:
  [ ] Officer A (Root CA Officer) confirmed available for full ceremony duration (4-6 hours estimated)
  [ ] Officer B (Root CA Security Officer) confirmed available for full ceremony duration
  [ ] Auditor confirmed available for full ceremony duration (optional if Officer B also records)
  [ ] All Three have reviewed Phase 4 SOP and signed acknowledgment of ceremony procedures

INFRASTRUCTURE CHECK:
  [ ] EJBCA offline host powered on; network physically disconnected
  [ ] Ethernet cable physically removed from network jack (not just disabled)
  [ ] WiFi disabled in BIOS/UEFI (rfkill block wifi confirmed)
  [ ] Network connectivity verified offline (ping test expected to fail; ssh unreachable)
  [ ] System time synchronized: chronyc tracking shows "System time correct" (within ±1 second of NTP)
  [ ] UPS backup power functional (supply 15 minutes minimum battery reserve for clean shutdown)

HSM VERIFICATION:
  [ ] SmartCardHSM or Nitrokey HSM physically present (visual inspection)
  [ ] HSM token serial number matches ceremony inventory (recorded in ceremony log template)
  [ ] pkcs11-tool --list-slots shows token present and readable
  [ ] Token status verified: "SmartCard-HSM [CCID Interface]" or "NitroKey HSM 2" label present
  [ ] HSM is in **CLEAN STATE**: pkcs11-tool --login --pin [OFFICER_A] --list-objects returns NO objects
  [ ] User PIN verified accessible to Officer A (PIN in sealed envelope in Officer A's custody)
  [ ] SO-PIN verified accessible to Officer B (SO-PIN in sealed envelope in Officer B's custody)

EJBCA CONFIGURATION VERIFICATION:
  [ ] EJBCA admin console reachable: curl -k https://localhost:8443/ejbca/healthcheck/ejbcahealthcheck.html (HTTP 200)
  [ ] Crypto token "RootCA-HSM-Primary" visible in EJBCA admin: Administration → Crypto Tokens
  [ ] Production root profile "RootCAProd-ECC384-SHA384" (or fallback RSA profile if chosen) exists and accessible
  [ ] Database verified operational: sudo mysql -u ejbca -p -e "SELECT 1;" ejbca (returns "1")
  [ ] Audit logging verified active: tail -5 /var/log/ejbca/audit.log shows recent entries

CEREMONY RESOURCES PREPARED:
  [ ] Ceremony log template printed (3 copies; one per officer/auditor; see Section 2.2 below)
  [ ] Pen and notepaper available for real-time notes during ceremony
  [ ] Video recording device (optional but recommended) positioned to record ceremony without audio (privacy)
  [ ] Camera/smartphone ready to photograph final attestation signatures and root fingerprints
  [ ] Secure media (USB key, encrypted or airgapped) available to transport root certificate and initial CRL to distribution endpoint
  [ ] Officer A PIN envelope clearly labeled and sealed (red wax seal or tamper-evident tape visible)
  [ ] Officer B SO-PIN envelope clearly labeled and sealed
  [ ] Physical custody: both envelopes locked in separate safes; keys held by respective officers
  [ ] Room access controlled: only ceremony participants admitted; door locked for duration of ceremony

APPROVALS FINAL CHECK:
  [ ] Phase 0 CA Policy signed by both officers and approved by management
  [ ] Phase 1 Platform Baseline signed by both officers
  [ ] Phase 2 Crypto Profile extensions validated and signed
  [ ] Phase 3 Pilot achieved GO decision; attestations on file
  [ ] Phase 4 Ceremony SOP (this document) reviewed and acknowledged by all participants
  [ ] Any policy exceptions or amendments documented and acknowledged pre-ceremony

```

---

## 2.2 Ceremony Log Template

**Print three copies of the following template; one per officer/auditor.** Record real-time entries during ceremony.

```
═══════════════════════════════════════════════════════════════════════
                      ROOT CA KEY CEREMONY FORMAL RECORD
                        JSIGROUP Authority
═══════════════════════════════════════════════════════════════════════

CEREMONY DATE: __/__/____  |  START TIME: ____:____ EST  |  END TIME: ____:____ EST

CEREMONY LOCATION: ____________________________
  [typically: locked room, physical access controlled, surveillance camera installed]

ATTENDEES:
  Officer A (Root CA Officer):               _________________________ (Print Name)
                                             _________________ (Signature & Date)
  
  Officer B (Root CA Security Officer):      _________________________ (Print Name)
                                             _________________ (Signature & Date)
  
  Auditor (Independent Observer):            _________________________ (Print Name)
                                             _________________ (Signature & Date)

─────────────────────────────────────────────────────────────────────
PHASE 1: PRE-CEREMONY VERIFICATION (Officer A & B)
─────────────────────────────────────────────────────────────────────

HSM INVENTORY:
  Token Type: [ ] SmartCardHSM  [ ] Nitrokey HSM 2  [ ] Other:_____________
  Token Serial: ____________________________
  Reader Device: ____________________________
  
EJBCA READINESS:
  Admin Console Status: [ ] OK (HTTP 200) [ ] ERROR: _______________
  Crypto Token Status: [ ] OK (listed) [ ] ERROR: _______________
  Database Status: [ ] OK (responds) [ ] ERROR: _______________
  Profile Name Used: [ ] RootCAProd-ECC384-SHA384  [ ] RootCAProd-RSA4096-SHA256  [ ] Other: __________

NETWORK OFFLINE STATUS (verified by Officer A):
  Ethernet cable:  [ ] Physically disconnected
  WiFi:            [ ] Disabled in BIOS/UEFI (rfkill block wifi)
  Ping test:       [ ] Unreachable (expected fail)

TIME SYNCHRONIZATION:
  NTP Status: [ ] Synchronized (within ±1 second)
  System Clock: ____:____ (match NTP if available)
  
OFFICER PIN CUSTODY:
  Officer A PIN Envelope:   [ ] Sealed and present (Red wax seal / Tamper-evident tape visible)
  Officer B SO-PIN Envelope: [ ] Sealed and present (Red wax seal / Tamper-evident tape visible)

─────────────────────────────────────────────────────────────────────
PHASE 2: KEY GENERATION (Officer A & B PRESENT)
─────────────────────────────────────────────────────────────────────

KEY GENERATION INITIATION:
  Time Initiated: ____:____ EST
  Officer A: "I initiate root private key generation on HSM token [serial ___________]"
             Signature: _________________________ Date: __/__/__

  Officer B: "I witness and approve key generation initiation"
             Signature: _________________________ Date: __/__/__

PIN ENTRY (Both officers physically present):
  User PIN Entry (Officer A):
    Time: ____:____ EST
    Officer A Enters PIN from sealed envelope: [ ] PIN entered successfully
    Officer B observes and logs: "PIN entry at ____:____ EST; HSM response: [ ] Access granted [ ] Denied"
    
  SO-PIN Entry (Officer B):
    Time: ____:____ EST
    Officer B Enters SO-PIN from sealed envelope: [ ] PIN entered successfully
    Officer A observes and logs: "PIN entry at ____:____ EST; HSM response: [ ] Access granted [ ] Denied"

KEY GENERATION PROCESSING:
  EJBCA Command Issued: `pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [OFFICER_A] --keypairgen --key-type ec:secp384r1 --id 01 --label root-ca-key-prod`
  
  Generation Start Time: ____:____ EST
  Generation End Time: ____:____ EST
  Generation Duration: _____ seconds
  
  EJBCA Status Output:
    [ ] "Key pair generated successfully"  [ ] ERROR: ___________________________
  
  Key ID (on-HSM): 01  |  Key Label: root-ca-key-prod  |  Key Type: ECDSA  |  Curve: secp384r1  |  Key Size: 384-bit

AUDITOR VERIFICATION:
  Auditor observes key generation process and verifies:
    [ ] Both officers present during PIN entry
    [ ] No unauthorized personnel present
    [ ] HSM LED/indicators showing activity
    [ ] EJBCA console output consistent with successful key generation
    [ ] Real-time audit logging occurring (Officer A verifies /var/log/ejbca/audit.log contains key generation event)
    
  Auditor Signature: _________________________ Date: __/__/__ Time: ____:____ EST

─────────────────────────────────────────────────────────────────────
PHASE 3: CERTIFICATE ISSUANCE (Officer A & B PRESENT)
─────────────────────────────────────────────────────────────────────

CERTIFICATE REQUEST SUBMISSION:
  Time Submitted: ____:____ EST
  Officer A action: "I initiate root certificate generation using profile RootCAProd-ECC384-SHA384"
                    Signature: _________________________ Date: __/__/__

CERTIFICATE GENERATION:
  EJBCA Command/Action: Via admin web console: [select profile] → [Enter subject DN] → [Click Generate]
  Subject DN Used: CN=JSIGROUP Root CA,O=JSIGROUP,C=CA
  
  Generation Start Time: ____:____ EST
  Generation End Time: ____:____ EST
  
  Officer B Monitors EJBCA Console:
    [ ] Web interface responsive during generation
    [ ] No error messages in console
    [ ] Certificate appears in certificate list after generation

CERTIFICATE VERIFICATION (Officer A & B):
  Export root certificate (DER):
    Export Command: `keytool -export -alias rootca -keystore /opt/ejbca/...` (or via web console)
    
    Certificate Details (verified via `openssl x509 -in root.cer -text -noout`):
    
    Subject: _________________________________________________
    Issuer: _________________________________________________
    Serial: _________________________________________________
    Not Before: ____/____/____ ____:____ EST
    Not After: ____/____/____ (20 years from issue date)
    Public Key Algorithm: ECDSA
    Public Key Curve: secp384r1 (384-bit)
    Signature Algorithm: ecdsa-with-SHA384
    
    CRITICAL EXTENSIONS PRESENT:
      [ ] Basic Constraints: CA:TRUE, pathLen=NONE
      [ ] Key Usage: keyCertSign, cRLSign
    
    ROOT CERTIFICATE FINGERPRINT (SHA-256):
      ________________________________________________________________________
      
      [Record this fingerprint in multiple locations for audit trail]

CERTIFICATE ACCEPTANCE:
  Officer A: "I accept the generated root certificate as valid and conforming to this ceremony SOP"
             Signature: _________________________ Date: __/__/__ Time: ____:____ EST
  
  Officer B: "I independently verify the generated root certificate and approve acceptance"
             Signature: _________________________ Date: __/__/__ Time: ____:____ EST
  
  Auditor: "I attest that the root certificate was generated under dual-control and full ceremony procedures were followed"
           Signature: _________________________ Date: __/__/__ Time: ____:____ EST

─────────────────────────────────────────────────────────────────────
PHASE 4: CRL ISSUANCE (Officer A & B, Initial CRL)
─────────────────────────────────────────────────────────────────────

INITIAL CRL GENERATION:
  Time Initiated: ____:____ EST
  Officer A: "I request generation of initial root CRL (empty, no revocation entries)"
  
  CRL Generation Command: `ejbca.sh gencrl RootCAProd` (or via web admin)
  
  Time Generated: ____:____ EST
  
  CRL Verification:
    CRL Fingerprint (SHA-256): ________________________________________
    CRL Issuer: _______________________________________________________
    This Update: ____/____/____ ____:____ EST
    Next Update: ____/____/____ ____:____ EST (recommend: 90 days for pilot; annual for production)
    Revocation Entries: 0 (empty; no revoked certs yet)
    
  [ ] CRL signature verified (signed by root key on HSM)
  [ ] CRL will be published to: http://ca.jsiggroup.local/crl/root.crl

─────────────────────────────────────────────────────────────────────
PHASE 5: AUDIT LOG & EVIDENCE PRESERVATION
─────────────────────────────────────────────────────────────────────

AUDIT LOG CAPTURE:
  Officer A: "I preserve all real-time system audit logs"
  
  Commands Executed:
    1. cp /var/log/ejbca/audit.log /tmp/ceremony-audit-20260419.log
    2. tar -czf ceremony-evidence-20260419.tar.gz /tmp/ceremony-audit-20260419.log [other logs]
    3. sha256sum ceremony-evidence-20260419.tar.gz > ceremony-evidence-20260419.tar.gz.sha256
    
  SHA-256 Hash of Evidence Archive:
    ________________________________________________________________________

EVIDENCE CHAIN:
  Root Certificate:
    Filename: root-ca-prod-ecc384-20260419.cer (DER)
    SHA-256 Hash: ________________________________________________________________________
    Storage Media: [ ] USB Key (encrypted)  [ ] CD-R (WORM)  [ ] Other: _____________
    Secure Custody: Locked safe, Location: _________________________ , Key Held By: _________

  Ceremony Log (Signed):
    [ ] PDF scanned (this document, printed and hand-signed by all three officers/auditor)
    SHA-256: ________________________________________________________________________
    Storage: As above

  EJBCA Audit Trail:
    [ ] Copied to secure media
    SHA-256: ________________________________________________________________________
    Storage: As above

─────────────────────────────────────────────────────────────────────
PHASE 6: FINAL ATTESTATION & CEREMONY CLOSE
─────────────────────────────────────────────────────────────────────

ROOT CA OFFICER (Officer A) FINAL ATTESTATION:

"I attest that the JSIGROUP Root CA private key was generated on the authorized hardware security module (Serial: _________) and never exported to external storage or uncontrolled systems. I further attest that the root certificate (Serial: ___________, Fingerprint: ______________________) was generated in conformance with this ceremony SOP, witnessed by Officer B and Auditor, and is ready for subordinate CA issuance."

  Officer A: _________________________ Date: __/__/__  Time: ____:____ EST

ROOT CA SECURITY OFFICER (Officer B) FINAL ATTESTATION:

"I independently verify and attest that this ceremony was conducted in strict accordance with Phase 4 procedures. Officer A and I jointly controlled PIN entry and key authorization. I verify that the root certificate meets all policy requirements defined in Phase 0 CA Policy. The HSM and EJBCA systems remain under secure custody, and no private key material left the HSM during this ceremony."

  Officer B: _________________________ Date: __/__/__  Time: ____:____ EST

AUDITOR FINAL ATTESTATION:

"I observed the complete 6-phase ceremony procedure and attest that:
  (a) Both officers were present and verified PIN entry and key generation
  (b) Network was offline (Ethernet disconnected, WiFi blocked)
  (c) Time was synchronized via NTP
  (d) All audit logs were preserved in tamper-evident packaging
  (e) The resulting root certificate meets Phase 2 crypto profile specifications
  (f) No process deviations or policy violations occurred
  
I recommend approval to proceed to Phase 5 (AD CS subordinate issuance)."

  Auditor: _________________________ Date: __/__/__  Time: ____:____ EST

CEREMONY END TIME: ____:____ EST

═══════════════════════════════════════════════════════════════════════
END OF ROOT CA KEY CEREMONY RECORD
═══════════════════════════════════════════════════════════════════════

DISTRIBUTION:
  Original (printed, hand-signed): Locked safe, location ___________________________
  Scanned PDF copy 1: Storage media (USB/CD)
  Scanned PDF copy 2: Secure encrypted email to [officer-email]@jsiggroup.local (optional)

NEXT PHASE: Upon completion and archival of this ceremony record, proceed to Phase 5
(AD CS Integration) to issue the subordinate CA certificate and install it in Windows
Server 2025 AD CS in the production JSIGROUP domain.

```

---

## 3. Ceremony Execution Procedure

### 3.1 Day-of Ceremony Steps (Scheduled Time)

**Sequence:** 0-30 min (Pre-flight), 30-90 min (Key Generation), 90-180 min (Certificate Issuance), 180-210 min (Attestation & Evidence Preservation)

#### Step 1: Welcome & Acceptance (0-5 min)

- [ ] All three participants enter ceremony room; door locked behind them
- [ ] Auditor starts video recording (no audio; focus on console/HSM indicators only)
- [ ] Officer A: "I am Root CA Officer and I initiate this formal key ceremony for the JSIGROUP Root CA"
- [ ] Officer B: "I am Root CA Security Officer and I verify all pre-ceremony checks completed successfully"
- [ ] Auditor: "I begin independent observation and recording of this ceremony"
- [ ] All three sign ceremony log template (Section 2.2): date, time, signatures

#### Step 2: HSM & EJBCA Verification (5-20 min)

- [ ] Officer A unseals Officer A's PIN envelope (red wax seal or tamper tape visible); PIN not announced
- [ ] Officer B unseals Officer B's SO-PIN envelope; SO-PIN not announced
- [ ] Both: Verify EJBCA admin console reachable (`curl -k https://localhost:8443/ejbca/healthcheck/...`)
- [ ] Auditor: Photograph/document both sealed envelopes BEFORE opening (for evidence chain)
- [ ] Officer A: Run `pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --list-slots` (verify HSM present)
- [ ] Officer B: Run `pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [REDACT] --list-objects` (verify token empty)
  - **NOTE:** Output shown in ceremony log with PIN REDACTED; complete PIN never written to disk
- [ ] Auditor: Verify network offline (run `ping 8.8.8.8`; expect "Unreachable"; log result)

#### Step 3: Key Generation Phase (20-90 min)

**Both officers physically present; Auditor observes**

- [ ] Officer A announces: "I initiate ECDSA private key generation on HSM for root CA"
- [ ] Officer A enters User PIN when prompted by EJBCA (via `pkcs11-tool` or EJBCA web UI key generation wizard)
- [ ] Officer B enters SO-PIN when prompted (dual-control activation)
- [ ] EJBCA invokes: `pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [REDACTED] --keypairgen --key-type ec:secp384r1 --id 01 --label root-ca-key-prod`
- [ ] **Wait for completion** (typically 30-60 seconds on fast hardware; variable on HSM operations)
- [ ] Auditor observes real-time `/var/log/ejbca/audit.log` for key generation event:
  ```bash
  tail -f /var/log/ejbca/audit.log | grep -i "key.*generat"
  ```
- [ ] Officer A: Verify EJBCA output: "RSA/ECC key pair generated successfully" or similar
- [ ] Auditor: Photograph on-screen EJBCA output (evidence of successful key generation)
- [ ] Record in ceremony log: Key generation timestamp, key ID (01), key label (root-ca-key-prod)

#### Step 4: Key Integrity Verification (90-110 min)

- [ ] Officer B: Run `pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [REDACTED] --list-objects`
  - Expected output: Private Key Object (ID=01, label=root-ca-key-prod, type=ECDSA, sensitive, never-extractable)
- [ ] Officer A: Verify private key cannot be exported: run `pkcs11-tool --login --pin [REDACTED] --read-object --type privkey --id 01` (should fail or refuse export)
- [ ] Record confirmation in ceremony log: "Private key verified on-token; export confirmed impossible"

#### Step 5: Certificate Issuance Phase (110-180 min)

**Both officers present; Auditor continues observation**

- [ ] Officer A announces: "I initiate root certificate issuance using profile RootCAProd-ECC384-SHA384"
- [ ] Via EJBCA web admin console:
  - Navigate: Certification Authorities → Create CA
  - Select Profile: `RootCAProd-ECC384-SHA384`
  - Confirm Settings:
    - Subject: CN=JSIGROUP Root CA,O=JSIGROUP,C=CA
    - Validity: 20 years (auto-calculated from today)
    - Crypto Token: RootCA-HSM-Primary (with PIN already activated from Step 3)
  - Click: "Generate CA" or "Create Root Certificate"
- [ ] **Wait for issuance** (typically 10-30 seconds)
- [ ] EJBCA generates root certificate signed by root private key (on HSM; signature never visible)
- [ ] Officer A: Export root certificate (DER format):
  ```bash
  keytool -export -alias rootca -keystore /path/to/ejbca/... -file root-ca-prod.cer
  # OR via EJBCA web admin: Download Certificate button
  ```
- [ ] Officer B: Verify certificate contents:
  ```bash
  openssl x509 -in root-ca-prod.cer -text -noout | head -40
  # Verify: Subject, Serial, Validity (20 years), Signature Algorithm (ecdsa-with-SHA384)
  ```
- [ ] Calculate root certificate fingerprints:
  ```bash
  openssl x509 -in root-ca-prod.cer -noout -fingerprint -sha256
  # SHA-256 fingerprint: ________________________
  
  openssl x509 -in root-ca-prod.cer -noout -serial
  # Serial: ________________________
  ```
- [ ] Record in ceremony log:
  - Subject DN: `CN=JSIGROUP Root CA,O=JSIGROUP,C=CA`
  - Serial: (from above)
  - SHA-256 Fingerprint: (from above)
  - Signature Algorithm: ecdsa-with-SHA384
  - Validity: (NotBefore, NotAfter dates)
- [ ] Auditor: Photograph EJBCA certificate details screen (for evidence chain)

#### Step 6: CRL Issuance Phase (180-195 min)

- [ ] Officer A: "I request initial root CRL issuance (empty, no revocation entries)"
- [ ] Via EJBCA CLI or web admin: `ejbca.sh gencrl RootCAProd`
  - CRL is signed by root private key on HSM (signature never visible; occurs on-token)
- [ ] Officer B: Export CRL and verify:
  ```bash
  openssl crl -in root.crl -text -noout
  # Verify: Issuer (root CA), This Update (today), Next Update (90 or 365 days), revoked certificates: NONE
  
  openssl crl -in root.crl -noout -fingerprint -sha256
  # SHA-256 fingerprint: ________________________
  ```
- [ ] Record in ceremony log:
  - CRL SHA-256 Fingerprint
  - This Update, Next Update dates

#### Step 7: Attestations & Evidence Preservation (195-210 min)

- [ ] Officer A & B jointly verify: Ceremony log completely filled in (all timestamps, fingerprints, signatures sections)
- [ ] Auditor completes final audit attestation (Section 2.2 in log)
- [ ] **All three sign ceremony log** in ink (printed document; hand-signature required)
- [ ] Officer A: Photograph final ceremony log (including all three signatures) with Auditor's camera
- [ ] Officer A: Package evidence for secure storage:
  ```bash
  cd /tmp
  mkdir ceremony-evidence-20260419
  cp root-ca-prod.cer root.crl /tmp/ceremony-evidence-20260419/
  cp /var/log/ejbca/audit.log ceremony-evidence-20260419/audit.log-20260419
  tar -czf ceremony-evidence-20260419.tar.gz ceremony-evidence-20260419/
  sha256sum ceremony-evidence-20260419.tar.gz > ceremony-evidence-20260419.sha256
  cat ceremony-evidence-20260419.sha256  # Record hash in ceremony log
  ```
- [ ] Record SHA-256 hash in ceremony log (Step 7 section, "Evidence Preservation")
- [ ] Officer B: Store evidence archive on secure media:
  - USB key (encrypted) or CD-R (WORM), labeled with: `JSIGROUP Root CA Ceremony Evidence - 2026-04-19`
  - Locked in safe (location: ________________); keys held by Officer B
- [ ] All three: Final attestation signatures recorded in ceremony log (Section 6 in log template)

#### Step 8: Ceremony Conclusion (210 min +)

- [ ] Auditor: Stop video recording
- [ ] Officer A: "This ceremonial proceeding is concluded. All officers have attested."
- [ ] All three: Sign and date ceremony log one final time (bottom of log)
- [ ] **Physically seal ceremony log** (3 copies):
  - Original: locked in Officer B's safe; key held by Officer B
  - Copy 1: scanned to PDF; encrypted and stored on USB key (locked in separate safe; key held by Officer A)
  - Copy 2: scanned to PDF; email to root-ca-committee@jsiggroup.local (encrypted email preferred)
- [ ] Physically disconnect HSM from USB (if removable); store in HSM custody case or separate locked container
- [ ] Document HSM custody transfer (who took possession, when, where; record in evidence archive)
- [ ] **Door remains locked** for 15 minutes post-ceremony (cool-down period; no one enters); then unlocked by Auditor

---

## 4. Post-Ceremony (Within 24 Hours)

### 4.1 Formal Handoff to Phase 5

Once ceremony is complete and all attestations are signed:

1. **Review attestations:** Each officer independently confirms their own signature and endorsement in ceremony log
2. **Archive evidence:** Secure media locked in safes; hashes recorded; chain of custody documented
3. **Notify next phase team:** "Root certificate now ready for subordinate issuance. Proceed to Phase 5 (AD CS Integration)"
4. **Generate subordinate CSR template:** Provide Windows AD CS team with CSR submission procedure (offline transfer, e.g., USB key)

### 4.2 Root Certificate Distribution Preparation

- [ ] Root certificate exported to distribution endpoint: `/var/www/html/root.cer` or `https://ca.jsiggroup.local/root.cer`
- [ ] Root CRL copied to distribution endpoint: `/var/www/html/crl/root.crl` or `https://ca.jsiggroup.local/crl/root.crl`
- [ ] Verify distribution endpoint is reachable from test Windows endpoints (Phase 5 prep)

---

## 5. Disaster Recovery (If Ceremony Fails)

### 5.1 Ceremony Halted Before Key Generation

If ceremony is halted **before step 3 (key generation)** is complete:

1. **Document halt reason** in ceremony log (e.g., "ECDSA key generation timed out; HSM unresponsive")
2. **Preserve all evidence** (partial ceremony log, audit trail up to halt point)
3. **Schedule rescheduled ceremony:** Same procedures; new ceremony date TBD by officers
4. **No private key was generated; return to Phase 4 start**

### 5.2 Key Generation Success, Certificate Issuance Fails

If ceremony **completes key generation (step 3) but fails at certificate issuance (step 5)**:

1. **Root private key exists on HSM** but no root certificate was created
2. **Do NOT perform new key generation** (would create duplicate key on HSM)
3. **Retry certificate issuance** (step 5 only):
   - Verify EJBCA recover from error
   - Retry: `ejbca.sh gencert RootCAProd --sign-with-hsm`
   - If retry succeeds: continue ceremony from step 5 (certificate already generated; proceed to CRL issuance)
   - If retry fails permanently: **Escalate to EJBCA support** (root private key is stranded on HSM; may require SO-PIN token reset + new ceremony)

### 5.3 Ceremony Fully Successful But root.cer Export Fails

If ceremony completes **but root certificate cannot be exported** to distribution endpoint:

1. **Root certificate and private key are confirmed on HSM**
2. **Attempt export retry:**
   ```bash
   keytool -export -alias rootca -keystore /path/to/ejbca/... -file retry-root.cer
   ```
3. **If export succeeds:** Continue with normal handoff (Phase 5)
4. **If export fails:** Root cert is locked in EJBCA; manual export via EJBCA CLI or support intervention required (does not affect private key or ceremony validity; just distribution mechanics)

---

## 6. Success Metrics (Post-Ceremony Review)

### 6.1 Ceremony Completion Criteria (ALL Must Be True)

```
✓ Root private key generated on HSM (never exported)
✓ Root certificate issued and signed by root private key
✓ Root certificate contains all required extensions (Basic Constraints: CA:TRUE, Key Usage: keyCertSign, cRLSign)
✓ Root certificate signature algorithm confirmed: ecdsa-with-SHA384 (or fallback RSA-SHA256 if applicable)
✓ Root certificate validity: 20 years (from ceremony date to expiry date in certificate)
✓ Both officers and auditor physically present and signed ceremony log
✓ Network confirmed offline throughout ceremony  (Ethernet disconnected, WiFi blocked)
✓ All PINs entered correctly; no lock-out events or authentication failures
✓ Initial root CRL issued and verified (empty, no revocation entries)
✓ All evidence (root cert, CRL, audit logs) archived in tamper-evident packaging and locked in safes
✓ Formal attestations signed and scanned
```

### 6.2 Verification Command (Post-Ceremony; 24 Hours Later)

Officer A or Auditor, while holding the root certificate artifact:

```bash
# Verify root certificate structure:
openssl x509 -in root-ca-prod.cer -text -noout -verify

# Expected output (truncated):
# Certificate:
#   Data:
#     Version: 3 (0x2)
#     Serial Number: _________________ (random 8-byte number)
#     Signature Algorithm: ecdsa-with-SHA384
#     Issuer: CN=JSIGROUP Root CA,O=JSIGROUP,C=CA
#     Subject: CN=JSIGROUP Root CA,O=JSIGROUP,C=CA (self-signed: issuer == subject)
#     Validity:
#       Not Before: Apr 19 ____:____ 2026 GMT
#       Not After : Apr 19 ____:____ 2046 GMT  (20 years later)
#     Public Key Algorithm: id-ecPublicKey
#       Public-Key: (384 bit) [ECDSA curve secp384r1]
#     X509v3 Extensions:
#       X509v3 Basic Constraints: critical
#         CA:TRUE
#       X509v3 Key Usage: critical
#         Digital Signature, Key Cert Sign, CRL Sign
#       ...
# Verification: OK

# Verify CRL structure:
openssl crl -in root.crl -text -noout

# Expected output (sample):
# Certificate Revocation List (CRL):
#   Version 2 (0x1)
#   Signature Algorithm: ecdsa-with-SHA384
#   Issuer: CN=JSIGROUP Root CA,O=JSIGROUP,C=CA
#   This Update: Apr 19 ____:____ 2026 GMT
#   Next Update: Jul 18 ____:____ 2026 GMT  (90 days later for pilot; 1 year for production)
#   CRL extensions:
#     ...
#   Revoked Certificates: None  (expected for initial empty CRL)
```

---

**End of Phase 4 Documentation**
