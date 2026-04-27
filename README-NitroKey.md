# Nitrokey HSM Diagnostic and Key Validation Log

Date: 2026-04-19
Workspace: ~/rootCA
Host OS: Linux

## Purpose
This document records the smart card diagnostics and on-token key validation actions that were executed for the Nitrokey HSM currently inserted in USB.

## Scope of Work Performed
1. Verified USB and reader/token presence.
2. Verified OpenSC/PKCS#11 tool availability.
3. Verified PKCS#11 slot/token visibility.
4. Enumerated existing token objects before key generation.
5. Generated a new test key pair on-token.
6. Performed functional sign/verify validation with the new key.

## Security Note
- User PIN was provided interactively by operator during testing and is intentionally shown as [PIN_REDACTED] throughout this log.
- No workspace secrets were written to disk by these steps.
- Temporary files used for signing tests were written under /tmp.

## Activity Log

### 1) Device and Tool Presence Checks
Commands run:
- lsusb | grep -Ei 'nitrokey|opensc|smartcard|yubikey|token|card|ccid'
- command -v pkcs11-tool
- command -v opensc-tool
- command -v pcsc_scan
- opensc-tool --list-readers

Observed results:
- Nitrokey USB token detected: vendor/product 20a0:4230 (Nitrokey HSM).
- Required tooling present: pkcs11-tool, opensc-tool, pcsc_scan.
- Reader/card presence confirmed via OpenSC reader listing.

Status: PASS

### 2) PKCS#11 Module Discovery and Slot Validation
Commands run:
- test -f /usr/lib/opensc-pkcs11.so
- find /usr -name '*opensc-pkcs11*.so' 2>/dev/null | head
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --list-slots
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so -L

Observed results:
- /usr/lib/opensc-pkcs11.so was not present on this host.
- Valid module path used: /usr/lib64/opensc-pkcs11.so.
- Slot 0 reported as present with token label SmartCard-HSM.
- Token metadata visible, initialized, and PIN initialized.

Status: PASS

### 3) Existing Object Enumeration (Before New Key Generation)
Commands run:
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --type privkey
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --type pubkey
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --type cert

Observed results:
- No private key objects listed.
- No public key objects listed.
- No certificate objects listed.
- Only token/profile metadata object visible.

Status: PASS (enumeration successful; token appeared empty of key/cert objects before test generation)

### 4) Additional Token Diagnostics
Commands run:
- pkcs15-tool --dump
- smartcard-hsm-tool --device 0 --list-keys (conditional check)

Observed results:
- pkcs15-tool dump succeeded and showed PIN-related metadata objects.
- smartcard-hsm-tool not installed on host, so OpenSC tooling remained primary validation method.

Status: PASS with one optional-tool gap noted

### 5) New On-Token Key Generation
Command run:
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --keypairgen --key-type rsa:2048 --id A1 --label copilot-test-20260419

Observed results:
- New RSA 2048 key pair generated successfully on token.
- Key identifier: A1
- Label: copilot-test-20260419

Status: PASS

### 6) New Key Object Validation
Command run:
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --id A1

Observed results:
- Token lists both private and public key objects for ID A1.

Status: PASS

### 7) Functional Sign/Verify Validation
Commands run:
- echo 'nitrokey-sign-test-2026-04-19' > /tmp/nitrokey_test_data.txt
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --sign --id A1 --mechanism SHA256-RSA-PKCS --input-file /tmp/nitrokey_test_data.txt --output-file /tmp/nitrokey_test_sig.bin
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --read-object --type pubkey --id A1 > /tmp/nitrokey_test_pub.der
- openssl pkey -pubin -inform DER -in /tmp/nitrokey_test_pub.der -out /tmp/nitrokey_test_pub.pem
- openssl dgst -sha256 -verify /tmp/nitrokey_test_pub.pem -signature /tmp/nitrokey_test_sig.bin /tmp/nitrokey_test_data.txt

Observed results:
- Signing operation completed using token key A1.
- OpenSSL verification output: Verified OK.

Status: PASS

## Final Outcome
- Smart card/token detection and authenticated access: PASS
- Existing key/cert inventory before test key creation: no key/cert objects found
- New key generation on token: PASS
- Functional cryptographic use of new key (sign + verify): PASS

## Resulting Token State From This Session
- At least one test key pair now exists on token:
  - ID: A1
  - Label: copilot-test-20260419
  - Algorithm: RSA 2048

## Nitrokey Removal Note
- After validation and cleanup were completed, the Nitrokey token was removed from the USB slot.
- Test key ID A1 is no longer present on the Nitrokey (verified by post-cleanup object listing).

## Suggested Next Actions
1. Create and validate an ECC P-384 test key to align with planned root CA algorithm.
2. Define production key labels/IDs for CA signing and related token objects.
3. Remove temporary test key A1 after confirmation it is no longer needed.

## Formal Change-Control and Audit Record Template

Use this section as a structured record for ticketing, approvals, and evidence collection.

### Change Metadata
- Change Title:
- Change/Ticket ID:
- Requestor:
- Operator:
- Approver:
- Environment: Offline Root CA Lab / Production
- Date Started (UTC):
- Date Completed (UTC):
- Change Window:

### Objective and Scope
- Objective:
- In Scope:
- Out of Scope:
- Rollback Needed: Yes/No
- Rollback Plan Reference:

### Preconditions
- Nitrokey token physically present and custody verified.
- Two-person control in place (if required by policy).
- OpenSC tools available and verified.
- Correct PKCS#11 module path validated.
- PIN entry performed securely (not logged).

### Execution Checklist
- [ ] USB/token detection completed.
- [ ] Reader presence validated.
- [ ] PKCS#11 slot/token visibility validated.
- [ ] Existing object inventory captured.
- [ ] New key generation executed (if applicable).
- [ ] New key object listing validated.
- [ ] Sign operation completed.
- [ ] Signature verification completed.

### Commands Executed (Sanitized)
Record exact commands with sensitive values redacted.

1. Command:
  - Purpose:
  - Output Summary:
  - Status: PASS/FAIL

2. Command:
  - Purpose:
  - Output Summary:
  - Status: PASS/FAIL

3. Command:
  - Purpose:
  - Output Summary:
  - Status: PASS/FAIL

### Evidence Artifacts
- Console log location:
- Screenshot or transcript references:
- Generated object identifiers (ID/Label):
- Temporary file paths used:
- Verification output excerpt (for example: Verified OK):

### Risk and Impact Assessment
- Security Impact:
- Availability Impact:
- Data/Key Material Exposure Risk:
- Residual Risk After Change:

### Exceptions and Deviations
- Any deviation from approved procedure:
- Reason for deviation:
- Approval for deviation (name/date):

### Final Validation and Outcome
- Overall Result: PASS/FAIL
- Existing keys status summary:
- New key status summary:
- Production readiness: Yes/No

### Sign-Off
- Operator Sign-Off (name/date):
- Reviewer Sign-Off (name/date):
- Security/PKI Approver Sign-Off (name/date):

## Completed Change-Control Record (2026-04-19)

### Change Metadata
- Change Title: Nitrokey HSM diagnostics and on-token key validation
- Change/Ticket ID: TBD
- Requestor: User (interactive session)
- Operator: GitHub Copilot (assisted terminal execution)
- Approver: TBD
- Environment: Offline Root CA Lab
- Date Started (UTC): 2026-04-19
- Date Completed (UTC): 2026-04-19
- Change Window: Interactive validation session

### Objective and Scope
- Objective: Verify Nitrokey HSM presence, validate existing key inventory, create a new test key, and prove cryptographic usability with sign/verify.
- In Scope: OpenSC/PKCS#11 diagnostics, object enumeration, test key generation, signature validation.
- Out of Scope: EJBCA configuration, production key ceremony, AD CS issuance integration.
- Rollback Needed: No (for diagnostics). Optional cleanup exists for test key removal.
- Rollback Plan Reference: Remove test key ID A1 when no longer needed.

### Preconditions
- Nitrokey token physically present and detected over USB: Met.
- Two-person control in place (if required by policy): Not validated in tooling; procedural control to be confirmed by operator.
- OpenSC tools available and verified: Met.
- Correct PKCS#11 module path validated: Met (/usr/lib64/opensc-pkcs11.so).
- PIN entry performed securely (not logged): Met ([PIN_REDACTED] used in this file).

### Execution Checklist
- [x] USB/token detection completed.
- [x] Reader presence validated.
- [x] PKCS#11 slot/token visibility validated.
- [x] Existing object inventory captured.
- [x] New key generation executed (if applicable).
- [x] New key object listing validated.
- [x] Sign operation completed.
- [x] Signature verification completed.

### Commands Executed (Sanitized)

1. Command: lsusb | grep -Ei 'nitrokey|opensc|smartcard|yubikey|token|card|ccid'
  - Purpose: Validate token presence on USB bus.
  - Output Summary: Nitrokey HSM detected (20a0:4230).
  - Status: PASS

2. Command: command -v pkcs11-tool
  - Purpose: Confirm pkcs11-tool is installed.
  - Output Summary: Tool present in /usr/bin.
  - Status: PASS

3. Command: command -v opensc-tool
  - Purpose: Confirm opensc-tool is installed.
  - Output Summary: Tool present in /usr/bin.
  - Status: PASS

4. Command: command -v pcsc_scan
  - Purpose: Confirm pcsc_scan is installed.
  - Output Summary: Tool present in /usr/bin.
  - Status: PASS

5. Command: opensc-tool --list-readers
  - Purpose: Validate reader/card presence through PC/SC.
  - Output Summary: Nitrokey reader detected with card present.
  - Status: PASS

6. Command: find /usr -name '*opensc-pkcs11*.so' 2>/dev/null | head
  - Purpose: Discover the installed OpenSC PKCS#11 module path.
  - Output Summary: Located module under /usr/lib64, including /usr/lib64/opensc-pkcs11.so.
  - Status: PASS

7. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --list-slots
  - Purpose: Validate PKCS#11 slot visibility.
  - Output Summary: Slot 0 present with token label SmartCard-HSM.
  - Status: PASS

8. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so -L
  - Purpose: Inspect token metadata and initialization state.
  - Output Summary: Token metadata visible, initialized, and PIN initialized.
  - Status: PASS

9. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects
  - Purpose: Enumerate all visible token objects before key generation.
  - Output Summary: Only token/profile metadata object visible.
  - Status: PASS

10. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --type privkey
  - Purpose: Enumerate existing private keys before generation.
  - Output Summary: No pre-existing private key objects listed.
  - Status: PASS

11. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --type pubkey
  - Purpose: Enumerate existing public keys before generation.
  - Output Summary: No pre-existing public key objects listed.
  - Status: PASS

12. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --type cert
  - Purpose: Enumerate existing certificates before generation.
  - Output Summary: No certificate objects listed.
  - Status: PASS

13. Command: pkcs15-tool --dump
  - Purpose: Inspect PKCS#15 metadata objects on the token.
  - Output Summary: PIN-related metadata objects visible.
  - Status: PASS

14. Command: smartcard-hsm-tool --device 0 --list-keys
  - Purpose: Attempt SmartCard-HSM-native key listing.
  - Output Summary: Tool not installed on host.
  - Status: SKIPPED

15. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --keypairgen --key-type rsa:2048 --id A1 --label copilot-test-20260419
  - Purpose: Create test key pair on token.
  - Output Summary: RSA 2048 key pair generated successfully with ID A1.
  - Status: PASS

16. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --id A1
  - Purpose: Validate the generated key objects are present on token.
  - Output Summary: Private and public key objects for ID A1 listed.
  - Status: PASS

17. Command: echo 'nitrokey-sign-test-2026-04-19' > /tmp/nitrokey_test_data.txt
  - Purpose: Create deterministic test payload for signing.
  - Output Summary: Test payload written to /tmp/nitrokey_test_data.txt.
  - Status: PASS

18. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --sign --id A1 --mechanism SHA256-RSA-PKCS --input-file /tmp/nitrokey_test_data.txt --output-file /tmp/nitrokey_test_sig.bin
  - Purpose: Validate private key signing capability.
  - Output Summary: Signing completed successfully for key ID A1.
  - Status: PASS

19. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --read-object --type pubkey --id A1 > /tmp/nitrokey_test_pub.der
  - Purpose: Export public key for offline verification.
  - Output Summary: Public key exported to /tmp/nitrokey_test_pub.der.
  - Status: PASS

20. Command: openssl pkey -pubin -inform DER -in /tmp/nitrokey_test_pub.der -out /tmp/nitrokey_test_pub.pem
  - Purpose: Convert exported DER public key to PEM for OpenSSL verification.
  - Output Summary: PEM public key created at /tmp/nitrokey_test_pub.pem.
  - Status: PASS

21. Command: openssl dgst -sha256 -verify /tmp/nitrokey_test_pub.pem -signature /tmp/nitrokey_test_sig.bin /tmp/nitrokey_test_data.txt
  - Purpose: Validate signature correctness using exported public key.
  - Output Summary: Verified OK.
  - Status: PASS

22. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --id A1
  - Purpose: Confirm key A1 existed before cleanup.
  - Output Summary: Private and public key objects for ID A1 listed.
  - Status: PASS

23. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --delete-object --type privkey --id A1
  - Purpose: Remove temporary private key object.
  - Output Summary: Private key deletion completed successfully.
  - Status: PASS

24. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --delete-object --type pubkey --id A1
  - Purpose: Remove temporary public key object.
  - Output Summary: Returned object-not-found; no matching object remained at deletion time.
  - Status: PASS

25. Command: pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --id A1
  - Purpose: Verify cleanup completion.
  - Output Summary: No objects listed for ID A1.
  - Status: PASS

### Evidence Artifacts
- Console log location: Interactive terminal session logs in this workspace session.
- Screenshot or transcript references: Chat/terminal transcript for 2026-04-19 run.
- Generated object identifiers (ID/Label): A1 / copilot-test-20260419.
- Temporary file paths used: /tmp/nitrokey_test_data.txt, /tmp/nitrokey_test_sig.bin, /tmp/nitrokey_test_pub.der, /tmp/nitrokey_test_pub.pem.
- Verification output excerpt: Verified OK.

### Risk and Impact Assessment
- Security Impact: Low for diagnostics; moderate if test keys are left unmanaged on production token.
- Availability Impact: Minimal; read-only checks plus one key-generation operation.
- Data/Key Material Exposure Risk: Low; PIN shown as [PIN_REDACTED], private key remained on token.
- Residual Risk After Change: Test key A1 persists until explicitly removed.

### Exceptions and Deviations
- Any deviation from approved procedure: smartcard-hsm-tool utility was not installed.
- Reason for deviation: Host package gap; equivalent validation completed with OpenSC pkcs11-tool.
- Approval for deviation (name/date): TBD

### Final Validation and Outcome
- Overall Result: PASS
- Existing keys status summary: No pre-existing private/public/cert objects were enumerated before test key generation.
- New key status summary: ID A1 created and functionally validated (sign + verify).
- Production readiness: Partial. Token and toolchain are validated; production policy/ceremony controls still required.

### Sign-Off
- Operator Sign-Off (name/date): TBD
- Reviewer Sign-Off (name/date): TBD
- Security/PKI Approver Sign-Off (name/date): TBD

## Key Cleanup Procedure (Test Key A1)

Use this procedure when the temporary validation key is no longer required.

### Step 1: Confirm Key Exists
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --id A1

Expected result:
- Private/public objects for ID A1 are listed.

### Step 2: Delete Private Key Object
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --delete-object --type privkey --id A1

### Step 3: Delete Public Key Object
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --delete-object --type pubkey --id A1

### Step 4: Verify Removal
- pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin [PIN_REDACTED] --list-objects --id A1

Expected result:
- No objects returned for ID A1.

### Optional: Record Cleanup in Audit Trail
- Cleanup Date (UTC): 2026-04-19
- Operator: GitHub Copilot (assisted terminal execution)
- Reviewer: TBD
- Verification Result: PASS

### Cleanup Execution Result (2026-04-19)
- Pre-check: Objects for ID A1 were present (private and public key objects listed).
- Private-key delete command: Completed successfully.
- Public-key delete command: Returned object-not-found (no remaining matching object at deletion time).
- Post-check: No objects listed for ID A1.
- Final state: Test key ID A1 removed.

## Technical Lessons Learned (2026-04-27)

During the formal Phase 4 Key Ceremony, several critical technical constraints were identified regarding the integration of Nitrokey HSM with Java 21 and EJBCA.

### 1. Java 21 Module Encapsulation
**Issue:** Java 21 enforces strict module boundaries that prevent EJBCA from accessing internal `SunPKCS11` wrappers required for HSM interaction.
**Resolution:** The WildFly `standalone.conf` must be patched to export the `jdk.crypto.cryptoki` module:
```bash
# Add to JAVA_OPTS in standalone.conf
--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED
```

### 2. Java "Orphan Key" Invisibility
**Issue:** If a key pair is generated via `pkcs11-tool` (OpenSC) without a corresponding certificate object, the Java `SunPKCS11` KeyStore provider will treat the slot as empty (0 entries). Java requires an X.509 certificate object (even a dummy one) with a matching CKA_ID to recognize a private key as a "KeyStore Entry".
**Resolution:** Keys should be generated **natively via EJBCA** (`ejbca.sh cryptotoken generatekey`). EJBCA automatically handles the creation of the required dummy certificate object, ensuring the key is visible to the Java environment.

### 3. Subject DN Uniqueness in EJBCA
**Issue:** EJBCA uses a hash of the Subject DN as the primary key (`cAId`) for CA records. Multiple CAs (e.g., a Pilot Root and a Production Root) cannot share the exact same Subject DN even if their internal names are different.
**Resolution:** Any existing pilot/test CAs with the same Subject DN must be fully purged from the database (and caches cleared) before the production CA can be initialized with that DN.
