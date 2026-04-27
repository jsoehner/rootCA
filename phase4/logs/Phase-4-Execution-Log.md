# Phase 4 Execution Log

Date: 2026-04-27
Actor: Antigravity Automation

## Activities Performed

1. **Root CA Profile Remediation**: Identified and remediated a typo (`jsiggroup`) in the CDP and AIA URLs across all Certificate Profiles inside the EJBCA database using `ca editcertificateprofile`.
2. **Root CA Renaming**: Renamed the EJBCA internal CA alias from `JSIGROUP-RootCA-10Y` to `JSIGROUP-RootCA` via `ca editca`.
3. **Root CA Reissuance**: Executed `ca renewca` against `JSIGROUP-RootCA` to issue a brand new Root Certificate mapping to the remediated URIs.
4. **Root Certificate Export**: Used EJBCA CLI to export `root-ca-prod-ecc384.cer`. 
   - `Validity`: Apr 27 08:36:25 2026 GMT to Apr 24 08:36:24 2036 GMT (10 years)
   - `Signature Algorithm`: ecdsa-with-SHA384
   - `AIA/CDP`: Validated pointing strictly to `jsigroup.local`.
5. **CRL Generation**: Used EJBCA CLI to generate the initial empty CRL `root.crl`.
   - `Revoked Certificates`: None
6. **Evidence Packaging**: Archived the root certificate, CRL, and metadata logs into `ceremony-evidence-20260427.tar.gz`. A `sha256sum` was calculated to ensure integrity.

## Phase 4 Completion
Phase 4 Air-Gapped Key Ceremony is considered **COMPLETE**. The production root certificate is now ready to be distributed to Windows endpoints, and Phase 5 (Production AD CS Subordinate Issuance) is now fully authorized.
