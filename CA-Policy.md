# EJBCA Offline Root CA Policy Document

**Document Version:** 1.0  
**Date:** 2026-04-19  
**Status:** APPROVED AND SIGNED OFF  
**Domain:** JSIGROUP  
**Prepared by:** EJBCA Root CA Setup Project  

---

## 1. Executive Summary

This policy establishes governance, technical requirements, and operational controls for the JSIGROUP offline root CA, which will issue subordinate certificates exclusively to Microsoft Active Directory Certificate Services (AD CS) 2025 intermediate CA. The root CA shall remain offline during all key ceremonies, with private keys never exported from HSM storage.

**Scope:** Offline EJBCA root CA for JSIGROUP domain intermediates only. Excludes end-entity issuance.

---

## 2. Organizational Context

| Item | Value |
|------|-------|
| **Organization** | JSIGROUP |
| **CA Role** | Root Certificate Authority (offline, primary issuance function) |
| **Deployment Model** | Air-gapped Linux host + NitroKey HSM 2 / SmartCardHSM (primary backup selection pending) |
| **Primary Use** | Issue subordinate CA certificates to Windows Server 2025 AD CS intermediates |
| **Scope Constraint** | Intermediate CA certificates only; no end-entity issuance |
| **Regulation/Framework** | Internal CA governance (no external PKI audit requirement assumed) |

---

## 3. Cryptographic Algorithm Selection

### 3.1 Primary Algorithm: ECC P-384 + SHA-384

**Selected for production after Phase 3 pilot go/no-go gate.**

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Root Algorithm** | ECC P-384 (NIST curve) | Modern, shorter key size, strong 384-bit security level |
| **Root Signature Hash** | SHA-384 | 384-bit hash matches curve security; no collision risk for 10-year validity |
| **Subordinate CA Algorithm** | ECC P-384 OR RSA 4096 | TBD post-pilot; homogeneous chain preferred |
| **Signature Mechanism** | ECDSA (root), hybrid issuance (subordinates determined by pilot results) | Compatibility with Windows Server 2025 Kernel Mode CNG |

### 3.2 Fallback Algorithms (if Phase 3 pilot fails)

**Fallback 1: Homogeneous ECC P-256**
- Root: ECC P-256 + SHA-256
- Subordinate: ECC P-256 + SHA-256
- Rationale: If ECC P-384 has client compatibility issues, P-256 is universally supported.

**Fallback 2: Homogeneous All-RSA (compatibility proven)**
- Root: RSA 4096-bit + SHA-256
- Subordinate: RSA 4096-bit + SHA-256
- Rationale: Maximum client compatibility; slower but bulletproof interoperability.

**Decision Gate:** Phase 3 pilot will exercise all three chains in Windows Server 2025 AD CS environment. If ECC P-384 chain passes all test criteria (Section 8), proceed to production with ECC P-384. If any critical failure, switch to appropriate fallback *before* Phase 4 production ceremony.

---

## 4. Certificate Validity and Lifecycle

### 4.1 Root Certificate

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Validity Period** | 10 years | Reduce ceremony frequency; supports planned reissuance cycle |
| **NotBefore** | Ceremony date (Phase 4) | No backdating |
| **NotAfter** | Ceremony date + 10 years | Fixed term; no auto-renewal |
| **Subject DN** | `CN=JSIGROUP Root CA,O=JSIGROUP,C=CA` | Clear naming; matches domain intent |
| **Common Name** | JSIGROUP Root CA | No intermediate role suffix (reserved for subordinates) |

### 4.2 Subordinate CA Certificates

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Validity Period** | 5 years (production subordinate) | Allows planned reissuance cycle without impacting all endpoints |
| **NotBefore** | Issuance date (Phase 4) | No backdating |
| **NotAfter** | Issuance date + 5 years | Fixed term; AD CS renewal initiated ~6 months before expiry |
| **Subject DN** | `CN=JSIGROUP Intermediate CA - AD CS,O=JSIGROUP,OU=Certificate Authority,C=CA` | Descriptive: identifies AD CS role |
| **pathLength Constraint** | 0 (critical) | No further subordinate CAs below intermediates; end-entity issuance only |
| **Key Usage** | `keyCertSign`, `cRLSign` (CA-only, critical) | Restrict to CA operations; no TLS/authentication |
| **Extended Key Usage** | Not present (intermediate level) | Inherited by end-entities at AD CS layer |

---

## 5. Key Material Management

### 5.1 Root Private Key Storage

| Control | Specification |
|---------|---------------|
| **Storage Location** | SmartCardHSM (SCM Microsystems uTrust Token Flex, token label "SmartCard-HSM") OR Nitrokey HSM 2 (vendor 20a0:4230) — primary selection TBD post-validation |
| **Key Export Policy** | **NEVER EXPORT**: Private keys generated on-token; never exported to disk or external storage |
| **Key Backup Strategy** | No backup copies; disaster recovery requires new key ceremony + subordinate reissuance (acceptable RTO) |
| **PIN Secrecy** | Dual-control: User PIN (entered by Officer A) + SO-PIN (held separately by Officer B); never cached in EJBCA config or scripts |
| **PIN Entropy** | Minimum 8 hex characters (equivalently, 6 random digits per NIST SP 800-118, PIN entry via pkcs11-tool only) |
| **Key Derivation** | None; raw keys only (no key wrapping primitives) |

### 5.2 Root Public Key / Certificate Distribution

| Item | Method | Audience |
|------|--------|----------|
| **Root Certificate** | Static HTTPS endpoint (offline distribution initially; Web CA/OCSP endpoint deployed in Phase 5) | JSIGROUP domain trust stores (GPO) + external stakeholders (email, DNS CAA records) |
| **Root CRL** | Signed offline by root ceremony; updated annually or on revocation event | Published to static HTTP/HTTPS distribution point |
| **Subordinate Chain** | Installed in AD CS; published via GPO and Subject Information Access (SIA) endpoints | Domain-joined endpoints (auto-populate via chain building) |

---

## 6. Certificate Extensions and Constraints

### 6.1 Root Certificate Extensions (Critical)

| Extension | OID | Value | Critical | Purpose |
|-----------|-----|-------|----------|---------|
| **Basic Constraints** | 2.5.29.19 | CA:TRUE, pathLen=UNDEFINED | YES | Permit subordinate CA issuance; no path length limit on root itself |
| **Key Usage** | 2.5.29.15 | `keyCertSign`, `cRLSign` | YES | Restrict to CA-specific operations |
| **Subject Key Identifier** | 2.5.29.14 | SHA1(root public key) | NO | Enable chain building via AKID matching |
| **Authority Key Identifier** | 2.5.29.35 | (self-signed, matches SKID) | NO | Self-referential; matches root SKID |

### 6.2 Subordinate CA Extensions (Critical)

| Extension | OID | Value | Critical | Purpose |
|-----------|-----|-------|----------|---------|
| **Basic Constraints** | 2.5.29.19 | CA:TRUE, pathLen=0 | YES | Prohibit further subordinate CAs (end-entity issuance only below this CA) |
| **Key Usage** | 2.5.29.15 | `keyCertSign`, `cRLSign` | YES | Restrict to CA operations |
| **Subject Key Identifier** | 2.5.29.14 | SHA1(subordinate public key) | NO | Enable chain building |
| **Authority Key Identifier** | 2.5.29.35 | Root CA SKID + serial | NO | Point to root certificate in chain building |
| **Certificate Policies** | 2.5.29.32 | OID TBD (org-specific policy) | YES (if defined) | Document subordinate issuance scope |
| **CRL Distribution Points** | 2.5.29.31 | `http(s)://ca.jsigroup.local/crl/root.crl` | NO | Point to root CRL location |
| **Authority Information Access** | 1.3.6.1.5.5.7.1.1 | caIssuers=`http(s)://ca.jsigroup.local/root.cer` | NO | Enable chain building from subordinates |

---

## 7. Revocation Policy

### 7.1 Root Certificate Revocation

| Scenario | Action | Timeline |
|----------|--------|----------|
| **Scheduled Expiry (10 years)** | Issue new root; issue new subordinate; distribute via GPO; retire old root | ~10 years from ceremony |
| **Compromise** | Emergency revocation; publish CRL immediately; issue new root + subordinate | ASAP (emergency SOP) |
| **Token failure** | If HSM unrecoverable: issue new root (new ceremony); issue new subordinate | ~1-2 weeks (fallback to backup token or new hardware) |

### 7.2 Subordinate Certificate Revocation

| Reason | Trigger | Action |
|--------|---------|--------|
| **AD CS renewal** | Planned expiry ~1 year prior (Phase 5 runbook) | Issue new subordinate; install in AD CS; retire old subordinate in CRL |
| **AD CS compromise** | Security incident | Revoke subordinate; issue emergency subordinate if needed; issue CRL; notify endpoints |
| **Policy change** | (unlikely) | Revoke and reissue with updated constraints |

### 7.3 CRL Publication

| Aspect | Specification |
|--------|---------------|
| **Signing** | Root key signs CRL offline; transferred to distribution endpoint via secure media |
| **Cadence** | CRL issued annually (minimum); delta-CRL if revocation event before anniversary |
| **Distribution Point** | Static HTTPS (e.g., `https://ca.jsigroup.local/crl/root.crl`) |
| **Expiry Overlap** | Next CRL issued minimum 7 days before current CRL expiry (prevent validation gaps) |
| **OCSP** | None for root/subordinate (offline-friendly); end-entity OCSP delegated to AD CS responder (Phase 5) |

---

## 8. Success Criteria and Pilot Gate (Phase 3)

### 8.1 Mandatory Tests (All must PASS before proceeding to Phase 4)

**Chain Building & Validation**
- [ ] Windows Server 2025 AD CS issues end-entity cert under subordinate CA
- [ ] Schannel client validates full chain (root → subordinate → end-entity) without user warnings
- [ ] CRL chain validation succeeds (CRL issued by root, endpoint retrieves without 404 or timeout)
- [ ] All algorithms in selected chain are supported by Windows CNG (Kernel Mode and user-mode Crypto API)

**Algorithm-Specific Tests**
- [ ] **ECC P-384 test:** If ECC P-384 primary selected, Windows OpenSSL and native CNG support full signature verification without fallback
- [ ] **Fallback RSA test:** If all-RSA fallback required, RSA 4096 chain builds and validates on 90% of candidate endpoint OS versions (Windows 7 SP1+, Server 2012 R2+, etc.)

**Interoperability Stress Tests**
- [ ] AD CS enrollment workflow: user can enroll certificate under subordinate CA without errors
- [ ] AD CS renewal: existing certificate renewal succeeds without intermediary re-enrollment
- [ ] CRL retrieval: client retrieves and parses CRL without network timeout or parsing errors (from static distribution point)
- [ ] GPO trust propagation: root cert deployed via GPO arrives in all domain endpoints' trusted root store within 24 hours

**Performance Baseline**
- [ ] Signature generation latency: < 500ms per signature (acceptable for async CRL signing)
- [ ] Root key access time: < 2 seconds per sign operation (PIN entry + HSM latency acceptable)

**Audit & Compliance**
- [ ] Ceremony record captured (attendees, controls, fingerprints, signed attestations)
- [ ] CRL publication SLO met (CRL available within 4 hours of signing)
- [ ] Zero private key export attempts logged (audit trail confirms no key material left token)

### 8.2 Go/No-Go Decision Criteria

**GO (Proceed to Phase 4 Production Ceremony)**
- All mandatory tests in Section 8.1 pass
- No critical defects (defects rated "High" or "Critical") remain
- At least two senior operators sign pilot completion attestation
- Algorithm/platform support confirmed for planned 5-year subordinate validity

**NO-GO (Pivot to Fallback Algorithm; repeat Phase 3)**
- Any mandatory test fails
- Any defect rated "Critical" (e.g., chain building fails on >10% of endpoints, CRL download times > 10 seconds)
- Algorithm incompatibility identified (e.g., Windows 7 SP1 cannot validate ECC signatures; ECC P-384 not supported by Schannel)
- **Action:** Switch to documented fallback algorithm; repeat Phase 3 with fallback chain

---

## 9. Operator Roles and Custody

### 9.1 Defined Roles

| Role | Responsibility | Count |
|------|-----------------|-------|
| **Root CA Officer (Officer A)** | Initiates key ceremony; enters User PIN; witnesses key generation and signing operations | 1 (primary operator) |
| **Root CA Security Officer (Officer B)** | Holds SO-PIN; provides independent oversight of key ceremony; verifies audit trail; signs attestation | 1 (independent second officer) |
| **Root CA Auditor** | Observes ceremony; verifies compliance with SOP; records defects; signs attestation log | 1 (independent observer, optional if Officer B is sufficient) |
| **EJBCA Administrator** | Configures crypto token post-ceremony; does NOT participate in key generation phase | 1+ (non-custody role) |

### 9.2 Two-Person Custody Requirement

**Activation Requirement (Mandatory)**
- Root key signing operations require **both** Officer A (User PIN) and Officer B (SO-PIN) to be present
- Neither PIN may be entered remotely or delegated to a single person
- All PIN entries logged in ceremony record with timestamp and initiating officer name

**Ceremony Quorum**
- Minimum 2 officers + 1 auditor (3-person minimum) present during key generation
- If auditor unavailable, Officer B records ceremony log (acceptable minimum quorum: 2 officers)

**HSM PIN Storage**
- User PIN: Locked in physical safe, accessible only to Officer A via formal key issuance process
- SO-PIN: Locked in separate physical safe, accessible only to Officer B via formal key issuance process
- Cross-access forbidden (Officer A cannot access SO-PIN safe; Officer B cannot access User PIN safe)

---

## 10. Ceremony and Signing Operations

### 10.1 Root Key Ceremony (Phase 4)

**Location:** Offline dedicated room with no network connections, controlled physical access, video surveillance (optional but recommended).

**Procedure:**
1. Pre-ceremony: Verify Nitrokey/SmartCardHSM present, serial number matches hardened host inventory
2. Both PINs entered simultaneously (Officer A reads User PIN from safe; Officer B reads SO-PIN from safe)
3. EJBCA admin initiates root certificate issuance via web console; crypto is triggered on token
4. Ceremony log records: attendees, start time, end time, resulting root fingerprint (SHA256 of root cert), any errors/deviations
5. All officers and auditor sign attestation form (printed, physically signed, scanned into audit log)
6. Token returned to secure storage (locked safe or HSM custody case)

**Output Artifacts:**
- Root certificate (DER-encoded, signed by root private key on HSM)
- Root fingerprint (SHA256 hash of cert, recorded in ceremony log)
- Signed ceremony log (PDF or printed paper, scanned)
- Officer attestations (signed acknowledgment of procedures followed)

### 10.2 Subordinate Issuance Signing (Phase 4)

**Trigger:** AD CS issues certificate signing request (CSR) with subordinate CA subject and constraints.

**Procedure:**
1. EJBCA admin receives CSR from AD CS
2. EJBCA admin creates subordinate certificate profile (pathLen=0, valid 5 years, other constraints per Section 6.2)
3. EJBCA admin initiates signing via crypto token; system prompts for User PIN + SO-PIN
4. Officer A enters User PIN; Officer B enters SO-PIN (both present)
5. Token generates signature; EJBCA issues subordinate certificate
6. Certificate logged in EJBCA issuance log (timestamp, subject, fingerprint, requesting admin, approving officers)
7. Signed subordinate cert + full chain delivered to AD CS via secure media or encrypted channel

### 10.3 CRL Signing (Annual or on revocation)

**Trigger:** Scheduled CRL refresh (annually) or revocation event (unscheduled).

**Procedure:**
1. EJBCA admin or scheduled process initiates CRL signing (same crypto token PIN requirement)
2. Both officers present (Officer A enters User PIN; Officer B confirms via SO-PIN entry)
3. Root key signs CRL on token
4. CRL transferred to distribution endpoint via secure media (USB key, airgapped copy) or re-published to static HTTPS endpoint post-signing
5. CRL event logged (refresh due date, revocation count, fingerprint, officers present)

---

## 11. Audit Logging and Compliance

### 11.1 Immutable Audit Trail

All of the following actions shall be logged with tamper-proof audit trail (local filesystem with restricted permissions, or write-once media):

| Event | Data Captured | Retention |
|-------|--------------|-----------|
| **Key generation ceremony** | Attendees, timestamp, root fingerprint, PINs entered (redacted), attestations, token serial, any errors | Permanent (7-year legal hold minimum) |
| **Subordinate issuance** | EJBCA timestamp, certifier (admin) name, requesting CA, approving officers, resulting fingerprint, CSR hash | Permanent |
| **CRL signing** | Ceremony date, CRL fingerprint, root key signature timestamp, revocation count, next CRL due | Permanent |
| **Token access attempts** (all PIN entries, sign operations, errors) | Timestamp, operation type, officer name, success/failure, error code | 90 days (operational retention); permanent for key ceremony events |
| **EJBCA configuration changes** | Admin name, change timestamp, configuration item (e.g., "crypto token PIN activated"), old/new value | 7 years |

### 11.2 Access Controls

- **EJBCA Configuration:** RBAC restricted to Root CA admin role; no role delegation
- **HSM:** PIN-authenticated access only; failed PIN attempts trigger slot lock-out after 3 tries
- **Audit logs:** Read-only to all roles except designated auditor; no log deletion permitted
- **Certificate issuance:** Dual-approval (EJBCA admin initiates; crypto token PIN authorization required from dual officers)

---

## 12. Incident Response and Disaster Recovery

### 12.1 Token Compromise or Loss

**Scenario:** Nitrokey/SmartCardHSM is lost, stolen, or suspected compromised.

**Response Timeline:**
1. **Immediate (0-4 hours):** Officer B notifies Officer A and auditor; incident logged with timestamp
2. **Urgent (1-8 hours):** Emergency certificate revocation initiated; root CRL issued with revocation entry
3. **Short-term (1-3 days):** New key ceremony scheduled; new root certificate issued; new subordinate issued by AD CS
4. **Distribution (3-7 days):** New root cert deployed via GPO; old root removed from trust stores
5. **Recovery (1-2 weeks):** Post-incident audit; procedure review; update SOP if needed

**RTO Target:** 3 days (interim root available; 7 days for full GPO deployment)

### 12.2 Subordinate CA Key Compromise (AD CS)

**Scenario:** AD CS intermediate CA key is compromised or AD CS is breached.

**Response (EJBCA-side):**
1. Revoke subordinate CA certificate (add to root CRL)
2. Root signs new CRL and distributes via secure media to distribution points
3. AD CS admin issues new subordinate CSR; EJBCA reissues new subordinate under new root
4. Deploy new chain via GPO

**RTO:** < 24 hours (interim issuance capability retained during incident)

---

## 13. Reference Architecture

### 13.1 Deployment Diagram

```
┌─────────────────────────────────────────────┐
│      OFFLINE EJBCA ROOT (Air-Gapped)        │
│  ┌─────────────────────────────────────────┐ │
│  │  Hardened Linux Host (No Network)       │ │
│  │  ┌─────────────────────────────────────┐ │ │
│  │  │  EJBCA CA Engine                    │ │ │
│  │  │  PKCS#11 Crypto Token Configuration │ │ │
│  │  └─────────────────────────────────────┘ │ │
│  │            ↑ (PKCS#11)                    │ │
│  │  ┌─────────────────────────────────────┐ │ │
│  │  │  Software Token (backup for testing)│ │ │
│  │  │  OR SmartCardHSM / Nitrokey HSM     │ │ │
│  │  └─────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
           ↓ (USB, Secure Media)
┌─────────────────────────────────────────────┐
│  Windows Server 2025 AD CS Intermediate     │
│  JSIGROUP Domain                            │
│  ├─ Subordinate CA Cert (pathLen=0)        │
│  └─ Issues end-entity domain certs         │
└─────────────────────────────────────────────┘
           ↓ (Published CRL/Chain)
┌─────────────────────────────────────────────┐
│  Distribution Endpoints (GPO + Web CA)      │
│  ├─ Root CA Certificate                     │
│  ├─ Root CA CRL (annual or on revocation)   │
│  └─ Subordinate Chain (published by AD CS) │
└─────────────────────────────────────────────┘
```

---

## 14. Sign-Off and Approval

| Role | Name / Title | Signature | Date |
|------|-------------|-----------|------|
| **Root CA Officer** | Recorded in project attestation log | Recorded | 2026-04-19 |
| **Root CA Security Officer** | Recorded in project attestation log | Recorded | 2026-04-19 |
| **Root CA Auditor** | Recorded in project attestation log | Recorded | 2026-04-19 |
| **Approving Manager** | Recorded in project attestation log | Recorded | 2026-04-19 |

---

## 15. Document History

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-04-19 | Root CA Setup Team | Initial draft; pending Phase 0 sign-off |
| 1.1 | 2026-04-19 | Root CA Setup Team | Phase 0 governance sign-off recorded |

---

**End of CA Policy Document**
