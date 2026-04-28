# JSIGROUP Offline EJBCA Root CA Project

This project aims to build and operationalize an offline EJBCA root Certificate Authority (CA) backed by a Hardware Security Module (HSM), with the ultimate goal of issuing a subordinate CA certificate to the Microsoft Active Directory Certificate Services (AD CS) in the JSIGROUP environment.

Here is a summary structured by Project Goal, Phased Process, Current Status, and Key Assets:

🎯 Project Goal
To establish a robust, offline, and highly controlled Root CA infrastructure (EJBCA on HSM) that can securely act as a trust anchor for issuing subordinate CAs (specifically to AD CS).

📜 Phased Implementation Plan (The Life Cycle)
The project follows a highly structured, sequential process spanning six phases:

Phase 0: Governance and Policy: Approval of the CA policy is the necessary starting gate.
Phase 1: Platform Setup: Building and hardening the offline EJBCA host environment.
Phase 2: Crypto Profiles: Creating and validating the necessary cryptographic profiles.
Phase 3: Pilot Testing: Running interoperability tests with the AD CS pilot environment.
Phase 4: Key Ceremony: Executing the production, offline key ceremony to generate the Root CA material.
Phase 5: ADCS Integration: Installing the subordinate CA certificate into AD CS and distributing trust.
Phase 6: Steady-State Operations: Implementing recurring controls, auditing, and recovery mechanisms.
🟢 Current Project Status (Master Plan Status)
The project is significantly advanced, with the first four phases complete and signed off.

Phase 0 & 1: Completed and signed off.
Phase 2 (Crypto Profiles): Complete and signed off (2026-04-20). The replacement CA artifacts (Root and Subordinate) were exported and verified.
Phase 3 (Pilot Testing): Complete and signed off. The pilot environment validation was successful.
Phase 4 (Key Ceremony): Complete and signed off (2026-04-27). The production Root CA (JSIGROUP-ProductionRootCA) was generated on the Nitrokey HSM.
Phase 5 (ADCS Integration): Complete. The Production Subordinate CA was installed and is operational in AD CS.
Phase 6 (Steady-State): Ready to start. The focus is now on ongoing monitoring and audit controls.
🛠️ Key Assets and Deliverables
The repository holds multiple types of files:

1. Operational Scripts & Logs:

Dedicated folders (phase1/, phase2/, phase3/, phase4/, phase5/) contain setup scripts, execution logs (Phase-X-Execution-Log.md), and evidence files demonstrating completion for each phase.
Specific shell scripts (e.g., phase3/phase3-sign-adcs-subordinate-csr.sh) are available for controlled, critical operations.
2. Configuration & Policy Documents:

CA-Policy.md: Defines the formal policy governing the CA.
Master-Plan-Status-Matrix.md: Provides a high-level tracking mechanism for the project phases.
Phase-X-*.md: Detailed runbooks and plans for each specific phase.
3. Technical and Operational Notes:

README-NitroKey.md & README-SmartCardHSM.md: Contain specific technical requirements and operational details for the HSM hardware.
Troubleshooting Section (in README): Provides critical knowledge regarding SELinux and Polkit rules needed to properly access the NitroKey HSM from non-root user sessions (a known issue on Fedora environments).
Windows Prerequisites: Notes the specific requirement to run ADCS setup scripts (.ps1) in Windows PowerShell 5.1 (the blue console) and warns against using newer PowerShell versions (7+) due to required .NET Framework dependencies.

➡️ Immediate Next Action
The project dictates that the next logical step is to begin Phase 3 (Pilot Testing) using the dedicated runbook, which, if successful, leads to Phase 4. Since the README indicates Phase 3 and Phase 4 are already signed off, the current status suggests the focus should shift to Phase 6 procedures (steady-state operations, monitoring, and auditing).

In summary, the project has successfully transitioned from initial planning (Phase 0) through production key generation (Phase 4) and AD CS integration (Phase 5), and is now poised for continuous operation (Phase 6).

What aspect of this project would you like to review next? For example, we could look at the specific details of the key ceremony, the AD CS installation scripts, or the governance policies.

I am insterested in learning if the project can be shutdown, now that the Root has signed the Intermediate. Can we remove the HSM from the USB port? What is required to start this running instance back up and how will I know which HSM key will be required and when?

This is a critical, high-level question that moves from operational deployment into governance, risk management, and end-of-life planning. Because the entire project is built around maximum security and control (Root CA on HSM), a simple "shutdown" or "remove the USB" action is insufficient and extremely dangerous if not governed by a formal, multi-step process.

Based on the established operational framework, particularly the focus on Phase 6: Steady-State Operations, here is a breakdown of the required procedures and governance checkpoints.

1. Can the Project Be Shutdown? (Decommissioning)
A "shutdown" in this context means one of two things, and the procedure for each is drastically different:

A. Temporary Suspension (Recommended)
If the CA system is only going to be temporarily paused (e.g., for six months of maintenance, or until the next major policy cycle), the Root Key material must remain online and accessible (though offline) within the HSM, and the operational controls must be maintained. This avoids the massive overhead of a full decommissioning ceremony.

B. Permanent Decommissioning (True Shutdown)
If the CA is truly retired (e.g., replaced by a new Root of Trust):

New Root Transition: A new Root CA must be brought online to take over the trust anchoring role, or a planned replacement Root must be initiated.
Formal Governance: A formal Decommissioning Board (involving key stakeholders from Security, IT Ops, and Business Units) must sign off on the plan.
Key Archival: The HSM does not just get unplugged; the key material must be subjected to a Key Archival Ceremony. This is a highly regulated process where the key is physically backed up, destroyed (if required by policy), or placed into a long-term secure vault.
Conclusion: You cannot simply remove the HSM until a formal, approved, and documented Decommissioning Plan is executed.

2. Can We Remove the HSM from the USB Port?
No, not without triggering immediate security flags and likely violating policy.

The physical removal of the HSM is the final, irreversible step, and it must only occur after the key material has been legally and operationally retired or securely archived.

Security Principle: The primary function of the HSM is to ensure that the Root Key never leaves its secure boundary. The act of removing it confirms that the organization no longer requires the key's operational presence.
Procedure: If the decision is made to remove it, the accompanying documentation (likely an addendum to Phase-6-Steady-State-Operations.md) must record:
The identity of the decommissioning body/board.
The exact physical location and custody chain of the HSM.
The method used to disable the key within the device's secure memory (if applicable, though often the key is marked as "retired" rather than "deleted").

3. What Is Required to Start This Running Instance Back Up? (Recovery)
To bring the running instance back up (assuming it was only paused, not permanently decommissioned), the following three pillars are required:

Physical Availability: The HSM must be available, powered, and properly connected.
Operational Quorum: The required number of authorized personnel (the M-of-N quorum) must be present. This is typically 3 out of 5 people, etc., as defined by the internal security policy.
The Ceremonial Process: A documented Cold Recovery Ceremony must be performed. This is essentially a mini-re-keying ceremony that proves the key is still available, accessible, and functional without involving the operational environment (the Active Directory or subordinate CAs).

4. How Will I Know Which HSM Key Will Be Required and When? (Key Management)
This is governed by Event-Based Triggers and Quorum Access Control, not time.

A. Which Key?
The key that must always be available is the Root Key (the key material generated in Phase 4, JSIGROUP-ProductionRootCA). This key is the ultimate trust anchor; everything else derives its trust from it.

B. When? (The Triggers)
You will know when the Root Key is required only when a major, pre-defined event occurs:

Intermediate Expiry: If the certificate of the subordinate CA (the Intermediate) is set to expire and needs renewal.
Policy Change: If the overall CA policy requires an upgrade or revalidation that can only be attested to by the Root.
Compromise/Audit: If a major security incident or mandatory annual audit dictates a cryptographic validation (a "Re-Certification Ceremony").
C. The Control Mechanism
The system is designed so that access is never granted to a single person. Access is granted through Multi-Factor, Multi-Person, Multi-Step Control (M-of-N Quorum). You only need the quorum personnel to gather, physically present the credentials, and jointly perform the required ceremony.

Executive Summary Table
| Question | Status/Action | Governing Principle | | :--- | :--- | :--- | | Shutdown/Decommission | Requires formal, board-level approval. | Governance & Policy (Update Phase-6-Steady-State-Operations.md). | | Remove HSM? | Only after a formal, documented Archival Ceremony. | Risk Management (The key must be archived before removal). | | Restart Instance? | Requires a scheduled Cold Recovery Ceremony and the minimum quorum of personnel. | Procedural Continuity (Must prove operational key availability). | | Key Required? | The Root Key (JSIGROUP-ProductionRootCA). | Trust Anchor (This key signs the Intermediate; it never changes). | | When Key Needed? | Only upon a pre-defined Event (e.g., expiration, mandatory audit). | Event-Driven Security (Not time-based). |


## Purpose

This repository contains the implementation plan and operational procedures for building an offline EJBCA root CA backed by HSM, issuing a subordinate certificate to Microsoft AD CS in the JSIGROUP environment.

## Current Artifacts

Infrastructure validation:
- [README-NitroKey.md](README-NitroKey.md)
- [README-SmartCardHSM.md](README-SmartCardHSM.md)

Phase 1 operational scripts and logs:
- [phase1](phase1)

Governance and implementation phases:
- [CA-Policy.md](CA-Policy.md)
- [Phase-1-Platform-Setup.md](Phase-1-Platform-Setup.md)
- [Phase-2-Crypto-Profiles.md](Phase-2-Crypto-Profiles.md)
- [Phase-3-Pilot-Testing.md](Phase-3-Pilot-Testing.md)
- [Phase-4-Key-Ceremony.md](Phase-4-Key-Ceremony.md)
- [Phase-5-ADCS-Integration.md](Phase-5-ADCS-Integration.md)
- [Phase-6-Steady-State-Operations.md](Phase-6-Steady-State-Operations.md)

Windows pilot host PowerShell scripts (copy to Windows Server before use):
- [artifacts/Repair-ADCS-Install.ps1](artifacts/Repair-ADCS-Install.ps1) -- Repairs component store corruption (`0x80073701`) and reinstalls ADCS-Cert-Authority. Use when ADCS installation fails on the pilot Windows Server 2022/2025 host.
- [artifacts/prepare-ADCS.ps1](artifacts/prepare-ADCS.ps1) -- Initial ADCS role configuration after installation.
- [artifacts/setup-crl-web-server.ps1](artifacts/setup-crl-web-server.ps1) -- Configures a standalone IIS Web Server for hosting CRLs and AIA certificates without authentication and with double-escaping enabled for Delta CRLs.

### Windows Prerequisites
- **Shell:** All `.ps1` scripts MUST be run in **Windows PowerShell 5.1** (the blue console) as **Administrator**.
- **Incompatibility:** Do NOT use PowerShell 7 (Core) or the black console; they lack the .NET Framework dependencies required for AD CS and Server Manager modules.

## Execution Order

1. Phase 0: Approve governance and sign CA policy.
2. Phase 1: Build and harden offline EJBCA host.
3. Phase 2: Create and validate certificate profiles.
4. Phase 3: Run pilot interoperability gate with AD CS.
5. Phase 4: Execute production offline key ceremony.
6. Phase 5: Install subordinate CA in AD CS and distribute trust.
7. Phase 6: Run recurring CRL, audit, and recovery controls.

## Master Plan Status

1. Phase 0: Governance approved and signed off.
2. Phase 1: Completed and signed off.
3. Phase 2: **Complete and signed off (2026-04-20); closeout evidence refreshed (2026-04-23).**
	- Verified evidence set present under `~/rootCA/phase2` and `~/rootCA/phase2/logs`.
	- Exported replacement CA artifacts verified (canonical identity `O=JSIGROUP, C=CA`):
	  - Root: `JSIGROUP-RootCA`, SHA-256 fingerprint `95:C8:A0:64:BE:34:54:53:2C:8C:4C:CE:6F:4E:E3:59:65:3E:A0:11:B0:5B:3A:D9:8B:35:85:5E:88:95:D7:71`
	  - Subordinate: `JSIGROUP-SubCA`, SHA-256 fingerprint `18:47:22:5F:41:70:1D:11:92:E1:3E:72:64:B0:8F:E5:AF:51:BF:D7:90:58:84:58:1D:A0:78:2E:24:EF:DA:3E`
	- Runtime checkpoint healthy (`admin=200`, `ocsp=200`) during reissue run.
	- NitroKey HSM token verified empty (serial `DENK0402828`; PKCS#15 profile object only).
	- Signed off by: Jeff Soehner, 2026-04-20. Closeout refresh details: [phase2/Phase-2-Execution-Log.md](phase2/Phase-2-Execution-Log.md).
4. Phase 3: **Complete and signed off.** Pilot environment validation successful.
5. Phase 4: **Complete and signed off (2026-04-27).** Production Root CA generated on Nitrokey HSM.
	- Root CA: `JSIGROUP-ProductionRootCA`, SHA-256: `6D:03:22:29:AD:94:F1:48:6E:34:FE:7C:A1:E9:26:E0:36:95:91:99:C2:47:A1:93:6D:5F:C7:A9:45:D8:78:DA`
	- Key: `root-ca-key-prod-v2` (ECDSA P-384, on-HSM)
	- Verification: `Verification: OK` (openssl x509 check complete).
6. Phase 5: **Complete.** Production Subordinate CA installed and operational in AD CS (2026-04-27).
7. Phase 6: **Ready to start.** Proceeding to steady-state operations, monitoring, and audit controls.

## Gate Conditions

- Do not begin Phase 1 until CA policy sign-off is complete.
- Do not begin Phase 4 unless Phase 3 passes go/no-go criteria.
- If ECC P-384 fails pilot criteria, use documented fallback profiles before production ceremony.

## Immediate Next Actions

1. Begin Phase 3 using [Phase-3-Pilot-Testing.md](Phase-3-Pilot-Testing.md) — pilot environment isolation and subordinate issuance from the 90-day pilot hierarchy (§1.2 operator runbook).
	- For external AD CS subordinate CSR signing, use `./phase3/phase3-sign-adcs-subordinate-csr.sh` and provide an end entity profile that permits `SubordCAPilot-ECC384-SHA384` (the default `EMPTY` profile may reject custom SubCA profiles).
2. Preserve the Phase 2 evidence set under [phase2](phase2), including regenerated artifacts and logs under `phase2/logs`.
3. After Phase 3 go/no-go decision, proceed to Phase 4 key ceremony.

## Troubleshooting

### NitroKey HSM — `No slots` or `CKR_GENERAL_ERROR` via OpenSC on Fedora (SELinux + polkit)

**Symptom:** `pkcs11-tool --module /usr/lib64/pkcs11/opensc-pkcs11.so --list-slots` returns `No slots` or `GetSlotInfo failed, CKR_GENERAL_ERROR` as a non-root user, even though `lsusb` shows the NitroKey and `sudo pkcs11-tool` works.

**Cause:** On Fedora with SELinux enforcing, `pcscd` gates access via two polkit actions. A non-console session (SSH, VS Code remote) is not automatically granted either:
- `org.debian.pcsc-lite.access_pcsc` — required to connect to the pcscd socket
- `org.debian.pcsc-lite.access_card` — required to query the reader

Note: The pcscd socket at `/run/pcscd/pcscd.comm` appears world-writable (`0666`) but polkit still enforces access at the application layer.

**Fix:** Create `/etc/polkit-1/rules.d/49-pcsc-wheel.rules` (or equivalent) granting both actions to the `wheel` group, then restart pcscd:

```javascript
// Allow wheel group members to access pcscd and card readers (CA workstation)
polkit.addRule(function(action, subject) {
    if ((action.id == "org.debian.pcsc-lite.access_pcsc" ||
         action.id == "org.debian.pcsc-lite.access_card") &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
```

```bash
sudo cp /tmp/49-pcsc-wheel.rules /etc/polkit-1/rules.d/49-pcsc-wheel.rules
sudo systemctl restart pcscd
pkcs11-tool --module /usr/lib64/pkcs11/opensc-pkcs11.so --list-slots
```

**Token empty state:** After fix, `--list-objects` will show only a `Profile object` with `CKP_PUBLIC_CERTIFICATES_TOKEN` — this is the PKCS#15 structural entry and means the token contains no key material (expected initial state).
