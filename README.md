# JSIGROUP Offline EJBCA Root CA Project

Date: 2026-04-23
Status: Phase 1-4 complete and signed off; Phase 5 ready for integration.

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
	- Signed off by: Jeff Soehner, 2026-04-20. Closeout refresh details: [Phase-2-Execution-Log.md](Phase-2-Execution-Log.md).
4. Phase 3: **Complete and signed off.** Pilot environment validation successful.
5. Phase 4: **Complete and signed off (2026-04-27).** Production Root CA generated on Nitrokey HSM.
	- Root CA: `JSIGROUP-ProductionRootCA`, SHA-256: `6D:03:22:29:AD:94:F1:48:6E:34:FE:7C:A1:E9:26:E0:36:95:91:99:C2:47:A1:93:6D:5F:C7:A9:45:D8:78:DA`
	- Key: `root-ca-key-prod-v2` (ECDSA P-384, on-HSM)
	- Verification: `Verification: OK` (openssl x509 check complete).
6. Phase 5: **Ready to start.** Proceeding to AD CS integration and subordinate issuance.
7. Phase 6: Not started. Still blocked by Phase 5 operationalization.

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
