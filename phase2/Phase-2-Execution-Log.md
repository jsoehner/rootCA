# Phase 2 Execution Log

Date: 2026-04-23
Phase: 2 - Cryptographic Profile and Hierarchy Design
Status: Closeout refresh complete

## Objective

Refresh and validate the full Phase 2 evidence set after the 10-year root and 5-year subordinate material update.

## Activities Performed

1. Regenerated Phase 2 certificate profile XML artifacts.
2. Reissued/exported CA certificate material using existing production CA names:
   - Root CA: JSIGROUP-RootCA-10Y
   - Subordinate CA: JSIGROUP-SubCA-5Y
3. Re-ran certificate validation and produced fresh root/subordinate OpenSSL evidence.
4. Re-ran cleanup verification with HSM PIN and verified token inventory empty for key/cert/data object classes.
5. Re-ran closeout report generation and confirmed checklist auto-marks token/cleanup item complete from current evidence.

## Evidence Artifacts

- phase2/logs/phase2-reissue-20260423T003231Z.log
- phase2/logs/phase2-cert-validation-prod-jsigroup-ca-final-20260422-20260423T003244Z.txt
- phase2/logs/root-prod-jsigroup-ca-final-20260422-20260423T003244Z.txt
- phase2/logs/sub-prod-jsigroup-ca-final-20260422-20260423T003244Z.txt
- phase2/logs/phase2-cleanup-verification-20260423T003737Z.txt
- phase2/logs/phase2-closeout-report-20260423T003847Z.txt

## Validation Summary

- Runtime health probes passed (EJBCA healthcheck and OCSP status returned HTTP 200).
- Root certificate validated as ECDSA P-384, SHA-384, self-signed, 10-year validity window.
- Subordinate certificate validated as ECDSA P-384, SHA-384, issuer-root chained, pathLen=0, 5-year validity window.
- Token inventory verification passed under user login for privkey/pubkey/cert/data classes (no objects present).

## Closeout Checklist State

- [x] Test certificates deleted and token confirmed empty
- [ ] Officer A signature captured
- [ ] Officer B signature captured

## Notes

- Phase 2 is technically complete and closed.
- Remaining actions are governance signatures for Officer A and Officer B.

## Officer Attestation (Closeout Capture)

Officer A Name: ______________________
Officer A Signature: _________________
Officer A Date: __/__/____

Officer B Name: ______________________
Officer B Signature: _________________
Officer B Date: __/__/____

Recorded By: _________________________
Recorded Date: __/__/____
