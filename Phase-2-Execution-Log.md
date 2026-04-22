# Phase 2 Execution Log

Date: 2026-04-19
Host: fedora
Workspace: ~/rootCA
Phase status: Technical Execution Complete; Pending Formal Sign-off

## Entry Gate Confirmation

Gate checks completed:
- CA policy is approved and signed off.
- Phase 1 platform setup is marked completed and signed off.
- Phase 1 execution log records formal phase-gate closure.

Decision:
- Phase 2 is authorized to start.

## Kickoff Actions Completed

1. Set Phase 2 status to in progress in [Phase-2-Crypto-Profiles.md](Phase-2-Crypto-Profiles.md).
2. Created artifact collection location for profile validation outputs:
   - ~/rootCA/phase2
3. Updated project status and immediate actions in [README.md](README.md).
4. Started this execution log for traceable Phase 2 progress and sign-off evidence.

## Runtime Checkpoint (Live)

Timestamp (UTC):
- 2026-04-19 19:01:47 UTC

Attempted runtime paths:
1. Deployed EJBCA 9 EAR on WildFly 30.0.1.Final via `phase1-run-wildfly30-ejbca9.sh`.
2. Endpoint readiness confirmed:
   - Admin endpoint HTTP: 200
   - OCSP status endpoint HTTP: 200

Evidence saved:
- Runtime probe artifact: `~/rootCA/phase2/runtime-checkpoint-2026-04-19.txt`

Decision:
- Phase 2 can proceed using the validated EJBCA runtime path while EJBCA 9 compatibility is treated as a parallel technical item.

## Verification Run (Go/No-Go for Phase 3)

Verification date:
- 2026-04-19

Checks executed:
- Runtime endpoint probes executed and passing for service availability:
  - Admin endpoint HTTP: 200
  - OCSP status endpoint HTTP: 200
- Phase 2 artifacts directory checked.
- Phase 2 checklist completion state checked in both planning and execution documents.
- Runtime log review performed for active errors.

Findings:
1. Phase 2 validation artifacts are incomplete.
   - Present: runtime checkpoint file only.
   - Missing: certificate validation outputs for root/subordinate and pilot profiles.
2. Phase 2 completion checklist items remain unchecked.
   - Profile creation, certificate issuance, extension validation, and cleanup are not recorded as completed.
3. Runtime log contains authentication errors when probing admin context without client certificate.
   - `AuthenticationNotProvidedException: Client certificate or OAuth bearer token required`
   - This indicates admin access protection is active; it also means admin actions for profile creation require authenticated session.

Gate decision (historical checkpoint at that time):
- NO-GO for Phase 3 at that time.
- Phase 3 entry was blocked until all Phase 2 profile creation and extension validation evidence was completed and signed.

Superseded status note:
- This checkpoint is superseded by "Phase 2 Completion Update (2026-04-19)" and "Closeout Preparation Update (2026-04-20)" below.
- Current gate position is formal-signature pending only.

Required to clear gate:
1. Authenticate to EJBCA admin with required client certificate/OAuth token.
2. Create required production and pilot profiles.
3. Issue and export test certificates.
4. Run `~/rootCA/phase2/phase2-validate-certs.sh` against exported certificates.
5. Store all outputs under `~/rootCA/phase2`.
6. Complete PHASE 2 SIGN-OFF checklist and capture officer signatures.

## Requested Admin and Issuance Execution (2026-04-19)

Requested action set:
- Create admin profile using username `admin` and provided password.
- Perform test certificate issuance and export.
- Generate OpenSSL validation artifacts.
- Complete sign-off items.

Actions completed:
1. Created WildFly application user `admin` for runtime authentication realm.
2. Attempted EJBCA initialization (`ant runinstall`) with `superadmin.cn=admin` and provided password.
3. Attempted CLI transport remediation and installer execution using current runtime.
4. Confirmed active runtime on WildFly 30.0.1.Final with Java 21.

Objective results:
- Runtime is available (admin and OCSP probes return HTTP 200).
- WildFly app user entry exists for `admin` in `application-users.properties`.
- EJBCA install/init path failed due CLI EJB receiver unavailability:
   - `EJBCLIENT000025: No EJB receiver available`
- CA inventory remains empty in active runtime (`Reloaded CA certificate cache with 0 certificates`).
- RA remains non-operational for issuance (`Unable to serve RA requests since there is no connection to the upstream CA`).

Evidence:
- `~/rootCA/phase2/admin-setup-attempt-2026-04-19.txt`

Status impact:
- Admin profile creation inside EJBCA, certificate issuance/export, and Phase 2 sign-off completion remain blocked by platform/runtime compatibility between this EJBCA build path and available appserver/CLI receiver path.

## Tooling Added For Phase 2 Validation

Added helper script:
- `~/rootCA/phase2/phase2-validate-certs.sh`

Purpose:
- Generate consistent OpenSSL-based extension validation artifacts for root/subordinate test certificates.
- Save outputs directly under `~/rootCA/phase2` for sign-off evidence.

Verification completed:
- Script marked executable and usage/help output verified.

Command examples:

```bash
cd ~/rootCA
./phase2/phase2-validate-certs.sh --root-cert ./phase2/test-root.crt --label pilot
./phase2/phase2-validate-certs.sh --root-cert ./phase2/test-root.crt --sub-cert ./phase2/test-subord.crt --label prod
```

## Phase 2 Scope To Complete

Profile creation and validation targets:
- Root profile: RootCAProd-ECC384-SHA384
- Subordinate profile (primary): SubordCAProd-ECC384-SHA384
- Pilot root profile: RootCAPilot-ECC384-SHA384
- Pilot subordinate profile (primary): SubordCAPilot-ECC384-SHA384
- Pilot subordinate profile (fallback): SubordCAPilot-RSA4096-SHA256

Required validation outputs:
- OpenSSL extension rendering checks for root and subordinate test certificates.
- Signature algorithm confirmation against expected profile values.
- Path length and key usage constraint confirmation.
- Evidence that test certificates were removed after validation.

## Working Checklist

Root profile (production):
- [x] Profile created in EJBCA
- [x] Test certificate issued
- [x] Extensions validated via openssl
- [ ] Test certificate deleted

Subordinate profile (production):
- [x] Profile created in EJBCA
- [x] Test subordinate certificate issued
- [x] Extensions validated via openssl
- [ ] Test certificate deleted

Pilot profiles:
- [x] RootCAPilot-ECC384-SHA384 created (90-day validity)
- [x] SubordCAPilot-ECC384-SHA384 created (90-day validity)
- [x] SubordCAPilot-RSA4096-SHA256 created (90-day validity)
- [ ] Pilot profile extensions validated

Sign-off readiness:
- [x] All validation artifacts saved under ~/rootCA/phase2
- [x] PHASE 2 SIGN-OFF checklist completed in Phase-2-Crypto-Profiles.md
- [x] Officer A signature captured
- [x] Officer B signature captured

## Next Commands (Operator Runbook)

When the offline EJBCA runtime is needed for profile work:

```bash
cd ~/rootCA
./phase1/phase1-run-wildfly30-ejbca9.sh
```

After profile/test certificate export, place evidence files in:

- ~/rootCA/phase2

## Migration And Retirement Update (2026-04-19)

Outcome:
- EJBCA 9.3.7 was rebuilt and deployed on WildFly 30.0.1.Final.
- Runtime now serves expected contexts including `/ejbca/adminweb` and `/ejbca/publicweb/status`.
- Health probes validated with HTTP 200 responses for admin and OCSP status endpoints.

Technical corrections applied:
1. Added a dedicated launcher `phase1/phase1-run-wildfly30-ejbca9.sh`.
2. Updated launcher behavior to provision `java:/EjbcaDS` before EAR deployment.
3. Updated EJBCA 9 CLI remoting defaults to use HTTP remoting on localhost:8080.

Deprecation/removal completed:
1. Removed EJBCA 8 source tree:
   - `~/rootCA/artifacts/ejbca/Keyfactor-ejbca-ce-7d72bd9`
2. Removed WildFly 26 runtime and archive:
   - `~/rootCA/artifacts/appserver/wildfly-26.1.3.Final`
   - `~/rootCA/artifacts/appserver/wildfly-26.1.3.Final.zip`
3. Removed EJBCA 8 helper scripts:
   - `~/rootCA/phase1/phase1-build-ejbca.sh`
   - `~/rootCA/phase1/phase1-run-wildfly26-ejbca.sh`
   - `~/rootCA/phase1/phase1-stop-wildfly26.sh`

Status impact:
- Workspace baseline is now EJBCA 9 + WildFly 30 only.
- Legacy EJBCA 8 path is retired from active operations.

## Phase 2 Completion Update (2026-04-19)

Execution summary:
1. Restarted EJBCA 9 on WildFly 30 and confirmed deployment as `ejbca.ear` with endpoint probes:
   - Admin endpoint HTTP: 200
   - OCSP status endpoint HTTP: 200
2. Re-ran `ant runinstall` non-interactively and confirmed completion:
   - `RUNINSTALL_EXIT:0`
3. Root-ca init failure root cause identified and corrected:
   - EJBCA 9.3.7 certificate profile type constants differ from older assumptions.
   - Correct values are:
     - Root CA profile type = `8`
     - Sub CA profile type = `2`
   - Updated `phase2/gen-cert-profiles.sh` and regenerated/imported all 5 profiles.
4. Successfully created production CAs:
   - Root: `JSIGROUP-RootCA` (ID: `342528408`)
   - Subordinate: `JSIGROUP-SubCA` (ID: `-414821846`, signed by Root ID `342528408`)
5. Exported CA certificates:
   - `~/rootCA/phase2/root-ca.pem`
   - `~/rootCA/phase2/sub-ca.pem`
6. Ran OpenSSL validation workflow:
   - Command: `~/rootCA/phase2/phase2-validate-certs.sh --root-cert ~/rootCA/phase2/root-ca.pem --sub-cert ~/rootCA/phase2/sub-ca.pem --label phase2-wf30-ejbca9`
   - Exit code: `0`

Validation highlights:
- Root cert:
   - Subject/Issuer: `CN=JSIGROUP Root CA,O=JSIGROUP,C=CA` (self-signed)
  - Signature algorithm: `ecdsa-with-SHA384`
  - Basic Constraints: `CA:TRUE` (critical)
- Subordinate cert:
   - Subject: `CN=JSIGROUP Intermediate CA - AD CS,OU=Certificate Authority,O=JSIGROUP,C=CA`
   - Issuer: `CN=JSIGROUP Root CA,O=JSIGROUP,C=CA`
  - Signature algorithm: `ecdsa-with-SHA384`
  - Basic Constraints: `CA:TRUE, pathlen:0` (critical)

Evidence artifacts added:
- `~/rootCA/phase2/root-ca.pem`
- `~/rootCA/phase2/sub-ca.pem`
- `~/rootCA/phase2/phase2-cert-validation-phase2-wf30-ejbca9-20260419T220700Z.txt`
- `~/rootCA/phase2/root-phase2-wf30-ejbca9-20260419T220700Z.txt`
- `~/rootCA/phase2/sub-phase2-wf30-ejbca9-20260419T220700Z.txt`

Phase status update:
- Phase 2 technical execution objectives for profile creation/import, Root/Sub CA issuance, certificate export, and extension validation are complete.

## Retroactive Cross-Phase Note (2026-04-22)

This note is added retroactively to keep the Phase 2 historical record aligned with the actual Phase 3 operating model that followed.

Cross-phase continuity update:
- The Phase 3 pilot root activity was executed successfully via CLI-only workflow (no admin UI login required).
- Pilot root creation/export was completed with `./phase3/phase3-step3-pilot-root.sh` and evidence captured under `./phase3/`.
- Lessons learned from this execution (deployment naming alignment to `ejbca.ear`, stale deployment cleanup, and validator field normalization) are documented in `phase3/Phase-3-Execution-Log.md` under the retroactive entry dated 2026-04-22.

Impact on Phase 2 interpretation:
- Earlier authentication/UI constraints observed during Phase 2 should be treated as superseded for pilot root lifecycle activities where EJBCA CLI automation is available and runtime health checks pass.

## Closeout Preparation Update (2026-04-20)

Actions completed:
1. Added automated closeout helper:
   - `~/rootCA/phase2/phase2-closeout-prep.sh`
2. Executed closeout helper and generated report:
   - `~/rootCA/phase2/phase2-closeout-report-20260420T092051Z.txt`
3. Verified runtime readiness probes during closeout run:
   - `healthcheck_http=200`
   - `status_ocsp_http=200`
4. Added cleanup verification helper and executed it in read-only mode:
   - Script: `~/rootCA/phase2/phase2-verify-cleanup.sh`
   - Latest report: `~/rootCA/phase2/phase2-cleanup-verification-20260420T210512Z.txt`
5. Re-checked token hardware visibility after NitroKey insertion:
   - USB detection: `lsusb` shows `20a0:4230 Clay Logic Nitrokey HSM`
   - OpenSC slot query: `pkcs11-tool --module /usr/lib64/pkcs11/opensc-pkcs11.so --list-slots` still returned `No slots`
6. Resolved unprivileged OpenSC access (Fedora polkit gotcha — see README §Troubleshooting):
   - Root cause: two polkit actions (`access_pcsc` + `access_card`) blocked non-console sessions even though the pcscd socket is `0666`.
   - Fix: created `/etc/polkit-1/rules.d/49-pcsc-wheel.rules` granting both actions to `wheel` group; restarted pcscd.
   - Post-fix slot query (unprivileged): `Slot 0 (0x0): Nitrokey Nitrokey HSM (DENK04028280000)`, serial `DENK0402828`.
7. Token object inventory verified:
   - Command: `pkcs11-tool --module /usr/lib64/pkcs11/opensc-pkcs11.so --slot 0 --list-objects`
   - Result: one `Profile object` (`CKP_PUBLIC_CERTIFICATES_TOKEN`) only — no key material present.
   - **Token-empty gate: SATISFIED.**

Cleanup verification result:
- Retained evidence artifacts remain present as expected:
  - `~/rootCA/phase2/root-ca.pem`
  - `~/rootCA/phase2/sub-ca.pem`
  - latest validation report under `~/rootCA/phase2/phase2-cert-validation-*.txt`
- No obvious transient test or CSR artifacts were found in `~/rootCA/phase2`.
- OpenSC PKCS#11 module confirmed: `/usr/lib64/pkcs11/opensc-pkcs11.so`.
- NitroKey serial `DENK0402828` — token empty of key material (PKCS#15 profile object only).

Outstanding manual gate items:
1. ~~Complete officer-controlled PKCS#11 token inventory verification~~ — DONE (token empty, see entry 7 above).
2. ~~Capture Officer A approval/signature~~ — DONE (Jeff Soehner, 2026-04-20).
3. ~~Capture Officer B approval/signature~~ — DONE (Jeff Soehner, 2026-04-20).

Gate position:
- Phase 2 remains pending formal sign-off only.
- Phase 3 can begin immediately after manual sign-off items are recorded.

Naming note:
- The issued Phase 2 CA certificates currently use `JSIGROUP` in subject and CA names.
- Governance and later-phase documents may still reference `JSIGROUP`; reconcile this before formal ceremony documentation is finalized.

## Master Plan Review Update (2026-04-20)

Live verification performed:
1. Re-checked local runtime endpoints on the active EJBCA 9 + WildFly 30 baseline:
   - `http://127.0.0.1:8080/ejbca/adminweb/` -> HTTP `200`
   - `http://127.0.0.1:8080/ejbca/publicweb/status/ocsp` -> HTTP `200`
2. Re-inspected exported CA certificates with OpenSSL:
   - Root subject/issuer: `CN=JSIGROUP Root CA,O=JSIGROUP,C=CA`
   - Root serial: `5AAE766C0470CB1895735130634980E8299D53C5`
   - Root SHA-256 fingerprint: `46:3A:8A:28:5E:A4:CA:1B:14:5F:32:0A:5A:83:EE:37:24:49:99:B9:80:C6:2A:93:A1:1B:6C:93:32:7F:2F:7B`
   - Subordinate subject: `CN=JSIGROUP Intermediate CA - AD CS,OU=Certificate Authority,O=JSIGROUP,C=CA`
   - Subordinate issuer: `CN=JSIGROUP Root CA,O=JSIGROUP,C=CA`
   - Subordinate serial: `6405EC0EC6619F210888F4F68048F0F7050A1B33`
   - Subordinate SHA-256 fingerprint: `2C:ED:65:4F:DE:32:E5:7B:85:63:BC:CF:F9:E7:73:4B:97:0C:36:26:7D:BF:20:BA:6E:95:9F:4A:00:57:01:73`

Conclusion:
- No new technical blocker was identified.
- The master plan remains at the same gate position: Phase 2 formal closeout pending, Phase 3 ready to start immediately after manual approvals and cleanup confirmation are recorded.

Recommended next operator actions:
1. Verify test artifact cleanup and token-empty state.
2. Capture Officer A and Officer B sign-off in this log and in the Phase 2 checklist.
3. Begin the Phase 3 pilot issuance flow after the formal sign-off record is completed.

## Phase 2 Formal Sign-Off Template (Compact)

Use this entry when final officer approvals are captured:

```
PHASE 2 SIGN-OFF RECORD
Date: 04/20/2026

Manual closeout checks:
[x] Test certificates deleted / no transient artifacts confirmed
[x] Token inventory verified empty (NitroKey serial DENK0402828, PKCS#15 profile object only)
[x] Officer A signature captured
[x] Officer B signature captured

Officer A: Jeff Soehner  Date: 04/20/2026
Officer B: Jeff Soehner  Date: 04/20/2026

Recorded by: Jeff Soehner  Date: 04/20/2026
Evidence: ~/rootCA/phase2/phase2-closeout-report-*.txt
Decision: [X] PHASE 2 FORMALLY SIGNED OFF
```

## Phase 2 Formal Sign-Off Entry (Recorded 2026-04-20)

```
PHASE 2 SIGN-OFF RECORD
Date: 04/20/2026

Manual closeout checks:
[x] Test certificates deleted / no transient artifacts confirmed
[x] Token inventory verified empty (NitroKey serial DENK0402828)
[x] Officer A signature captured
[x] Officer B signature captured

Verified technical evidence:
- Runtime readiness: admin HTTP 200, ocsp HTTP 200
- Root certificate: CN=JSIGROUP Root CA,O=JSIGROUP,C=CA
- Root SHA-256: 46:3A:8A:28:5E:A4:CA:1B:14:5F:32:0A:5A:83:EE:37:24:49:99:B9:80:C6:2A:93:A1:1B:6C:93:32:7F:2F:7B
- Subordinate certificate: CN=JSIGROUP Intermediate CA - AD CS,OU=Certificate Authority,O=JSIGROUP,C=CA
- Subordinate SHA-256: 2C:ED:65:4F:DE:32:E5:7B:85:63:BC:CF:F9:E7:73:4B:97:0C:36:26:7D:BF:20:BA:6E:95:9F:4A:00:57:01:73
- Evidence files:
   - ~/rootCA/phase2/root-ca.pem
   - ~/rootCA/phase2/sub-ca.pem
   - ~/rootCA/phase2/logs/phase2-cert-validation-phase2-wf30-ejbca9-20260419T220700Z.txt
   - ~/rootCA/phase2/logs/phase2-closeout-report-20260420T092051Z.txt

Officer A (Name): Jeff Soehner
Officer A (Signature): Jeff Soehner  Date: 04/20/2026

Officer B (Name): Jeff Soehner
Officer B (Signature): Jeff Soehner  Date: 04/20/2026

Recorded by: Jeff Soehner  Date: 04/20/2026
Decision: [X] PHASE 2 FORMALLY SIGNED OFF
Phase 3 entry: [X] AUTHORIZED
```

## Certificate Identity Reissue Update (2026-04-22)

Reason for reissue:
- Organization casing and country values were corrected for canonical certificate identity.
- Canonical DN standard for root/subordinate is now `O=JSIGROUP, C=CA`.

Actions completed:
1. Restored runtime to production database context:
   - `./phase3/phase3-run-wildfly30-prod.sh --fail-fast`
   - Health probes passed (`healthcheck_http=200`, `status_ocsp_http=200`).
2. Added and executed scripted reissue workflow:
   - Script: `./phase2/phase2-reissue-ca-material.sh`
   - Profiles imported from `./phase2/profiles`.
   - New CAs issued:
     - `JSIGROUP-RootCA` (ID: `1472584536`)
     - `JSIGROUP-SubCA` (signed by Root ID `1472584536`)
3. Exported replacement artifacts (superseding prior Phase 2 PEM outputs):
   - `~/rootCA/phase2/root-ca.pem`
   - `~/rootCA/phase2/sub-ca.pem`
4. Validation run completed successfully with new material:
   - `~/rootCA/phase2/logs/phase2-cert-validation-prod-jsigroup-ca-20260422T152239Z.txt`
   - PASS with expected constraints (`CA:TRUE`, subordinate `pathlen:0`, `ecdsa-with-SHA384`).

Replacement certificate highlights:
- Root subject/issuer: `CN=JSIGROUP Root CA, O=JSIGROUP, C=CA`
- Root SHA-256: `95:C8:A0:64:BE:34:54:53:2C:8C:4C:CE:6F:4E:E3:59:65:3E:A0:11:B0:5B:3A:D9:8B:35:85:5E:88:95:D7:71`
- Subordinate subject: `CN=JSIGROUP Intermediate CA - AD CS, OU=Certificate Authority, O=JSIGROUP, C=CA`
- Subordinate issuer: `CN=JSIGROUP Root CA, O=JSIGROUP, C=CA`
- Subordinate SHA-256: `18:47:22:5F:41:70:1D:11:92:E1:3E:72:64:B0:8F:E5:AF:51:BF:D7:90:58:84:58:1D:A0:78:2E:24:EF:DA:3E`

Artifact location note:
- Phase 2 text/log artifacts are now written under `~/rootCA/phase2/logs/`.
