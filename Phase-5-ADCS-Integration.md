# Phase 5: AD CS Integration and Operationalization

**Phase Status:** READY FOR EXECUTION
**Date Created:** 2026-04-19  
**Phase Dependencies:** Phase 4 root key ceremony must be completed and signed  

## 1. Objective

Install the subordinate CA certificate issued by the offline EJBCA root into Windows Server 2025 AD CS, publish chain artifacts, and validate trust behavior across the JSIGROUP environment.

Deliverables:
- AD CS subordinate CA certificate installed and active
- Full chain published (root + subordinate)
- Root trust distributed through GPO
- CRL distribution points reachable and parsable
- Runbooks finalized for routine operations

## 2. Inputs Required

From Phase 4:
- Root certificate (DER/PEM)
- Root CRL
- Root fingerprint record (SHA-256)
- Signed ceremony record and audit evidence

From AD CS server:
- Subordinate CSR generated from target CA instance
- Hostname/FQDN and target publication URLs

## 3. Subordinate Certificate Workflow

### 3.1 Generate CSR on AD CS

On Windows Server 2025 AD CS host:
1. Install AD CS role as Subordinate CA (do not finalize with self-signed cert).
2. Generate subordinate CSR using CA setup wizard.
3. **IMPORTANT WORKAROUND:** Because the Enterprise SubCA wizard corrupts the ECDSA signature, regenerate the CSR immediately using `certreq -new` with `UseExistingKeySet=TRUE`. This is now automated in `Prepare-Enterprise.ps1`.
   - **NOTE:** All PowerShell scripts (`Prepare-Enterprise.ps1`, etc.) MUST be run in **Windows PowerShell 5.1** (the blue console) as Administrator. They are incompatible with PowerShell 7/Core due to AD CS module dependencies.
4. Export CSR to secure transfer media.
5. Record CSR hash:
   - certutil -hashfile subordinate.req SHA256

### 3.2 Sign CSR on Offline EJBCA Root

On offline EJBCA host:
1. Validate CSR integrity and PoPO before EJBCA signing:
   - `openssl req -in subordinate.req -verify -noout`
   - If verification fails, regenerate CSR on AD CS before continuing.
2. Import/sign CSR in EJBCA using subordinate profile approved in Phase 2 and an EE profile mapped for ADCS subordinate issuance (`ADCS2025_SubCA_EE_Profile`).
2. Verify profile constraints before signing:
   - Basic Constraints: CA:TRUE, pathLen=0 (critical)
   - Key Usage: keyCertSign, cRLSign (critical)
   - Validity: 5 years
3. Officer A and Officer B perform dual-control token activation.
4. Sign subordinate CSR with root key on HSM (CLI helper path):
   - `./phase3/phase3-sign-adcs-subordinate-csr.sh --csr subordinate.req --ee-profile ADCS2025_SubCA_EE_Profile`
5. Export artifacts:
   - subordinate-ca.cer
   - root-ca.cer
   - chain bundle (if needed)
6. Record cert fingerprints and serials in issuance log.

### 3.3 Install Subordinate Cert in AD CS

On AD CS host:
1. Import signed subordinate certificate into pending CA request.
2. Complete AD CS configuration.
3. Restart AD CS services:
   - net stop certsvc
   - net start certsvc
4. Verify CA health:
   - certutil -ping
   - certutil -cainfo

Expected result:
- AD CS service starts cleanly
- CA is issuing-ready
- No chain or private key mismatch errors in Event Viewer

## 4. Trust Distribution (GPO)

### 4.1 Root Certificate Distribution

1. Open Group Policy Management.
2. Edit domain GPO for trusted roots.
3. Import root certificate under:
   - Computer Configuration > Policies > Windows Settings > Security Settings > Public Key Policies > Trusted Root Certification Authorities
4. Force update on pilot/target clients:
   - gpupdate /force
5. Verify trust store:
   - certutil -store root | findstr /I "JSIGROUP Root CA"

### 4.2 Intermediate Distribution

If needed, publish subordinate cert via:
- Intermediate Certification Authorities GPO store
- AIA/caIssuers URL endpoint

## 5. CRL and AIA Publication

### 5.1 Root Artifacts

Publish to static endpoint:
- root cert: https://ca.jsigroup.local/root.cer
- root crl: https://ca.jsigroup.local/crl/root.crl

Validation commands:
- certutil -URL root-ca.cer
- certutil -dump root.crl

### 5.2 Subordinate CRL

Configure AD CS CDP/AIA extensions to organization endpoints.
Validate with:
- certutil -getreg CA\CRLPublicationURLs
- certutil -getreg CA\CACertPublicationURLs

## 6. Validation Matrix

Required checks:
- End-entity enrollment succeeds from domain clients
- Issued certs chain to root without warnings
- certutil -verify -urlfetch succeeds
- TLS services using issued certs show valid chain in Schannel
- CRL retrieval succeeds without timeout or parse errors

Recommended sample clients:
- Windows 11
- Windows Server 2025
- Any legacy systems still in support scope

### 6.1 Known Cryptographic Gotchas

> **Note:** If deploying an **ECDSA (ECC P-384)** Enterprise CA, Native AD CS Auto-Enrollment with default Version 1 templates (e.g., DomainController, Machine) will fail during certificate installation with `ERROR_INVALID_PARAMETER (0x80070057)`. This is due to a CryptoAPI chain verification bug where legacy Cryptographic Service Providers (forced by V1 templates) cannot parse ECDSA CA signatures.
> 
> See the `Phase-5-Execution-Log.md` for the full technical breakdown and the **"Decoupled Enrollment"** workaround using `certreq -new` via CNG KSPs.

## 7. Operational Runbooks (Initial)

Finalize and store runbooks for:
- Subordinate renewal process
- Emergency subordinate revocation
- Root CRL refresh and publication
- Distribution endpoint outage handling

## 8. Phase 5 Exit Criteria

All must be true:
- Subordinate CA certificate installed and active
- Root trust deployed through GPO
- CRL/AIA endpoints verified reachable
- End-to-end issuance and chain validation successful
- Operations runbooks approved by officers

Sign-off:
- Officer A: ____________________ Date: __/__/__
- Officer B: ____________________ Date: __/__/__
- Auditor: ______________________ Date: __/__/__
