# Master Plan Status Matrix

Date: 2026-04-26
Workspace: ~/rootCA

---

## 🎯 Overall Project Status

**Current Focus:** Phase 5 (Production AD CS Integration and Trust Rollout) preparation underway.
**Gate Status:** Phase 4 formally closed. The Production Root Key Ceremony is complete, and the Root Certificate has been successfully generated and exported. Phase 5 is fully authorized.

---

## 🗺️ Phase Status Summary

| Phase | Plan Objective | Current Status | Supporting Evidence | Gate State |
| :--- | :--- | :--- | :--- | :--- |
| Phase 0 | Governance and policy approval | ✅ Closed (Signed Off) | CA-Policy.md (Status: APPROVED AND SIGNED OFF) | Closed |
| Phase 1 | Offline platform baseline | ✅ Closed (Signed Off) | Phase-1-Platform-Setup.md, Phase-1-Execution-Log.md | Closed |
| **Phase 2** | Crypto profiles and validation | ✅ Closed (Formal Sign-Off Complete) | Phase-2-Crypto-Profiles.md, Phase-2-Execution-Log.md, phase2/logs/phase2-closeout-report-20260423T003847Z.txt, phase2/logs/phase2-cleanup-verification-20260423T003737Z.txt | Closed |
| **Phase 3** | Pilot interoperability and go/no-go | ✅ **Closed (GO Decision Reached)** | Phase-3-Pilot-Testing.md, phase3/logs/Phase-3-Execution-Log.md | Closed |
| **Phase 4** | Production key ceremony | ✅ **Closed** | Phase-4-Key-Ceremony.md, phase4/logs/Phase-4-Execution-Log.md | Closed |
| **Phase 5** | AD CS integration and trust rollout | 🟡 **Ready for Execution** | Phase-5-ADCS-Integration.md | Open |
| Phase 6 | Steady-state operations and audit | 🔴 Blocked | Phase-6-Steady-State-Operations.md | Blocked by Phase 5 completion |

---

## ✅ Key Milestones Achieved (To Date)

*   **Governance:** Policy/governance approval is complete and signed off.
*   **Baseline:** Phase 1 baseline is complete and signed off.
*   **Runtime Environment:** Runtime baseline successfully migrated and normalized to EJBCA 9.3.7 + WildFly 30.
*   **Retirement:** Legacy EJBCA 8 and WildFly 26 runtime paths have been retired.
*   **Phase 2 Core:** Production root/subordinate CA creation and export are complete.
*   **Validation:** OpenSSL validation evidence has been generated and archived under `phase2/` and `phase2/logs/`.
*   **Closeout:** Phase 2 closeout helper was run, and the closeout report was generated under `phase2/logs/`.
*   **GO:** Phase 2 formal sign-off complete on 2026-04-20; refreshed closeout verification completed on 2026-04-23. All prerequisites for Phase 3 are met.
*   **Retroactive Phase 3 Update (2026-04-22):** Pilot root creation/export completed using CLI-only workflow (`phase3-step3-pilot-root.sh`) with validation evidence in `phase3/`.
*   **Test 2 PASSED (2026-04-25):** New Windows Server 2022 VM provisioned. Subordinate CSR generated and signed via CLI helper.
*   **Phase 3 GO Decision (2026-04-27):** Interoperability pilot successfully executed via the consolidated `Prepare-Standalone.ps1` and `Test-Standalone.ps1` scripts. ECC P-256 certificate issuance, Windows TLS/Schannel negotiation (via native `curl.exe`), and CRL CDP retrieval all passed validation on AD CS.
*   **Enterprise Tooling Created:** Deployed `Prepare-Enterprise.ps1` and `Test-Enterprise.ps1` for zero-touch auto-enrollment and auto-renewal testing against the upcoming Production Primary Domain Controller.
*   **Phase 4 Key Ceremony Completed (2026-04-27):** The Production Root CA (`JSIGROUP-RootCA-10Y`) was verified. The ECC P-384 root certificate and initial empty CRL were exported and archived into a tamper-evident tarball, completing the offline ceremony.

---

## 🚀 Phase 5 Immediate Action Plan (Execution Focus)

**Objective:** Integrate the Production Root with the Active Directory domain and issue the Production Subordinate CA certificate.

**Key Tasks:**
1. **Root Trust Distribution:** Deploy the new `root-ca-prod-ecc384.cer` to all domain endpoints via GPO.
2. **Subordinate AD CS Installation:** Run `Prepare-Enterprise.ps1` on the production PDC to generate the Subordinate CSR.
3. **Subordinate Signing:** Sign the PDC's CSR using the offline Production Root CA in EJBCA.
4. **Certificate Installation:** Install the signed Subordinate CA and finalize the Enterprise AD CS role.

---

## ⚠️ Risks and Notes

*   **Historical Context:** A historical NO-GO checkpoint earlier in the Phase 2 log has been superseded by later completion updates and closeout-prep evidence.
*   **Operational Guidance:** Operational scripts must exclusively use the WildFly 30 launcher path.
*   **Lesson Applied:** Preserve deployment name `ejbca.ear` for EJBCA CLI compatibility and clean stale managed deployments before redeploy.

## 🗓️ Recommended Next Update Trigger

Update this matrix after the Phase 3 GO/NO-GO decision is finalized.