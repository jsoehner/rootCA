## Plan: Offline EJBCA Root for AD CS Intermediate

Build a strict offline root CA in EJBCA backed by Nitrokey HSM 2 (OpenSC/PKCS#11), dedicated to issuing one Microsoft AD CS intermediate for the JSIGROUP domain. Because you selected ECC P-384 + SHA-384, the plan uses a gated pilot-first approach with explicit go/no-go criteria and documented fallback to homogeneous all-ECC or all-RSA if interoperability issues appear.

**Steps**
1. Phase 0: Governance, scope, and success criteria (blocks all later phases)
2. Define CA policy set: naming, validity, key sizes, path length, revocation model, allowed issuance scope (intermediate CA only), and operator roles/custody.
3. Approve hard requirements: strict offline root, no network interfaces during ceremonies, two-person ceremony quorum, signed ceremony records, and immutable audit retention.
4. Freeze acceptance criteria: chain validation on Windows Server 2025 AD CS, supported client matrix, CRL publication SLO, and recovery RTO/RPO for token failure.
5. Phase 1: Offline root platform baseline (depends on Phase 0)
6. Build hardened Linux offline host baseline for EJBCA root operations; enforce no network route, removable-media controls, time handling, and local audit logging.
7. Initialize Nitrokey HSM 2 securely (user/SO PIN policy, retry-lock policy, custody logging) and verify OpenSC PKCS#11 module, slot visibility, token serial capture, and object-label conventions.
8. Configure EJBCA CA crypto token to use the Nitrokey PKCS#11 module with label-based key selection (not slot hardcoding), activation procedure, and operator unlock sequence.
9. Phase 2: Crypto profile and hierarchy design (depends on Phase 1)
10. Define root certificate profile for ECC P-384 + SHA-384 with CA-only usages (`keyCertSign`, `cRLSign`), critical basic constraints, and no end-entity issuance rights.
11. Define subordinate issuance profile for Microsoft AD CS intermediate with critical CA constraints and pathLen=0 (no further subordinate CAs).
12. Define extension policy: offline-root-friendly AIA/CRL strategy (static distribution endpoints, no root OCSP dependency), publication cadence, and expiry overlap windows.
13. Phase 3: Interoperability pilot and decision gate (depends on Phase 2)
14. Stand up isolated pilot hierarchy and issue a pilot AD CS subordinate from the offline EJBCA root.
15. Run validation matrix: AD CS enrollment/renewal behavior, chain building, CRL retrieval, Schannel/TLS validation, GPO trust propagation, and representative endpoint/client verification.
16. Execute algorithm stress tests for your selected architecture and fallback architectures:
17. Option A: ECC root -> ECC subordinate (preferred if ECC retained).
18. Option B: All-RSA chain (safest compatibility fallback).
19. Capture defects and classify by severity and blast radius; apply go/no-go criteria.
20. Decision Gate: proceed to production only if pilot passes all critical checks; otherwise pivot to approved fallback profile before any production ceremony.
21. Phase 4: Production key ceremony and root creation (depends on pilot go decision)
22. Execute formal key ceremony on offline host to generate root private key on Nitrokey only; record attendees, controls, evidence, and resulting fingerprints.
23. Create production root CA certificate and publish trust-anchor package for controlled distribution into JSIGROUP domain trust stores.
24. Generate/sign AD CS subordinate certificate request offline and deliver signed subordinate certificate chain package for AD CS installation.
25. Phase 5: AD CS integration and operationalization (depends on Phase 4)
26. Install subordinate CA certificate in Windows Server 2025 AD CS and complete subordinate activation/restart steps.
27. Deploy trust chain in domain via GPO and validate enterprise trust behavior across target systems.
28. Publish root CRL/cert artifacts to static distribution points; validate reachability/parseability and renewal schedule adherence.
29. Complete runbooks: ceremony SOP, CRL refresh SOP, emergency revocation SOP, and token-loss disaster procedure.
30. Phase 6: Steady-state controls and audit program (parallel with late Phase 5 items where noted)
31. Schedule recurring offline maintenance windows for CRL signing/publication and integrity checks.
32. Run periodic restore-and-rebuild tabletop drills (token failure, subordinate compromise, distribution outage) and update procedures.
33. Maintain compliance artifacts: approvals, ceremony evidence, key fingerprints, issuance logs, CRL history, and exception register.

**Parallelism and dependencies**
1. Governance/policy work can run in parallel with host hardening prep, but no key generation before policy sign-off.
2. CRL/AIA endpoint design can run in parallel with AD CS template prep, but subordinate issuance blocks until profile and pilot gates pass.
3. Runbook drafting can begin during pilot and is finalized after production ceremony outcomes are known.

**Relevant files**
- No repository files currently exist in the workspace; this plan assumes a greenfield project and prioritizes infrastructure runbooks, policy records, and controlled ceremony artifacts before code/config automation.

**Verification**
1. PKCS#11 verification: token visible, key objects discoverable by label, EJBCA crypto token activation succeeds repeatedly after reboot/operator unlock.
2. Certificate profile verification: root and subordinate certs contain required key usage/basic constraints/pathLen settings and expected signature algorithms.
3. AD CS integration verification: subordinate installation succeeds on Windows Server 2025 AD CS, chain builds to root on domain-joined hosts, and issuance works for representative templates.
4. Revocation verification: root CRL is generated offline, published, retrievable, and accepted by Windows chain engine before expiration.
5. Security verification: offline controls enforced (no network), dual-control ceremony logs complete, no private key export paths, and operator/audit logs preserved.
6. Fallback readiness verification: all-RSA and all-ECC fallback procedures are documented and testable if ECC P-384 path fails pilot gates.

**Decisions**
- In scope: offline EJBCA root on Nitrokey HSM 2 with OpenSC PKCS#11, issuing a Microsoft AD CS intermediate for JSIGROUP.
- Selected: Windows Server 2025 AD CS, strict offline operation, pathLen=0, and initial preference for ECC P-384 + SHA-384.
- Constraint: do not proceed to production until interoperability pilot passes critical checks.
- Excluded for now: migration of all existing enterprise templates/cert consumers beyond pilot-defined representative workloads.

**Further Considerations**
1. ECC production profile recommendation: prefer ECC root -> ECC subordinate for consistency; avoid mixed ECC->RSA chain unless mandatory legacy dependency is proven and validated.
2. Trust distribution approach recommendation: choose between pure domain GPO trust distribution versus hybrid GPO + managed endpoint channels for non-domain assets.
3. Artifact governance recommendation: define where signed ceremony records and CRL publication evidence are retained (records system, retention period, approvers).