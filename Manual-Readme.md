# Manual Execution Guide & Technical Retrospective
## Project: JSIGROUP Offline HSM-Backed EJBCA Root CA

This document provides a comprehensive manual walkthrough of the entire project hierarchy from Phase 1 through Phase 5. It includes the technical rationale for command choices, critical "gotchas" discovered during execution, and the manual commands required to reproduce the environment without relying solely on automation scripts.

---

## 0. Technical Baseline
*   **OS:** Fedora (Workstation/Server)
*   **JDK:** OpenJDK 21 (Required for WildFly 30 / EJBCA 9 compatibility)
*   **App Server:** WildFly 30.0.1.Final
*   **Database:** MariaDB (Schema: `ejbca_pilot`)
*   **PKI:** EJBCA Community Edition 9.3.7
*   **HSM:** Nitrokey HSM 2 (SmartCard-HSM)

---

## Phase 1: Platform Hardening and Installation

### 1.1 Java 21 Module Export Gotcha
**The Problem:** Java 9+ module encapsulation prevents EJBCA from accessing the internal SunPKCS11 wrapper classes required for HSM communication.
**The Fix:** You must manually edit `bin/standalone.conf` in WildFly.
**Rationale:** Without this, EJBCA will fail to load the PKCS#11 provider even if the `.so` file is correct.
```bash
# Add to JAVA_OPTS in standalone.conf:
--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED
```

### 1.2 Database Initialization
**Rationale:** We used MariaDB with a schema name `ejbca_pilot`. 
**Gotcha:** The database name remains `ejbca_pilot` even in production. This is an infrastructure artifact. To maintain connectivity, do not rename the schema without a full WildFly `standalone.xml` update and EJBCA re-deployment.

---

## Phase 2 & 3: Crypto Profiles and Pilot

### 2.1 Profile Design
**Rationale:** We chose **ECC P-384** with **SHA-384** to meet modern security standards while maintaining compatibility with Windows Server 2025.
**Gotcha:** Windows AD CS "Enterprise" wizard often corrupts ECDSA signatures in the CSR.
**Manual Fix:** Always regenerate the CSR using `certreq -new` with an `.inf` file and `UseExistingKeySet=TRUE`.

---

## Phase 4: Production Key Ceremony

### 4.1 HSM Key Visibility (The "Orphan Key" Problem)
**The Problem:** Keys generated via `pkcs11-tool` are often invisible to Java's `SunPKCS11` provider unless a matching "Certificate Object" exists on the token.
**The Fix:** Generate keys natively inside EJBCA using the CLI.
**Rationale:** EJBCA's `generatekey` command automatically creates the necessary metadata on the HSM to make the private key visible to the Java Virtual Machine.
```bash
# Manual Command (Inside EJBCA bin):
./ejbca.sh cryptotoken generatekey --alias root-ca-key-prod-v2 --keyspec secp384r1 --token <TOKEN_NAME>
```

### 4.2 Subject DN Uniqueness (The `cAId` Collision)
**The Problem:** EJBCA uses a hash of the Subject DN as the database Primary Key (`cAId`). 
**Gotcha:** If your "Pilot Root" and "Production Root" share the exact same DN (e.g., `CN=JSIGROUP Root CA,O=JSIGROUP,C=CA`), you cannot create the second CA.
**Manual Fix:** You must manually purge the pilot CA from the database or use a slightly different DN for production.
```sql
-- Manual Purge (Extreme Caution):
DELETE FROM CAData WHERE subjectDN = '...';
```

---

## Phase 5: AD CS Integration

### 5.1 Windows PowerShell 5.1 Requirement
**Gotcha:** PowerShell 7 (Core) cannot load the `ServerManager` or `ADCSDeployment` modules required to manage Windows Roles.
**Manual Fix:** Always use the blue **Windows PowerShell 5.1** console as Administrator.

### 5.2 Proof-of-Possession (PoPO) Rejection
**The Problem:** EJBCA rejects CSRs from Windows if the signature is in the "Specified" format (OID 1.2.840.10045.4.3).
**The Fix:** Add `AlternateSignatureAlgorithm = FALSE` to the `certreq` `.inf` file.
**Rationale:** This forces Windows to use a standard "Named" signature (e.g., `ecdsa-with-sha384`) which BouncyCastle can verify reliably.

### 5.3 Manual CSR Signing Command
If the helper scripts are unavailable, use this canonical EJBCA command to sign a subordinate CA:
```bash
./ejbca.sh createcert \
  --username <EE_USER> \
  --password <EE_PWD> \
  -c subordinate.req \
  -f subordinate.cer
```
**Rationale:** This separates the registration (RA) from the issuance, ensuring strict policy enforcement.

### 5.4 Mandatory CRL Update
**Gotcha:** If you sign a new certificate but do not update the CRL, AD CS may reject the new certificate during installation because the existing CRL (from the pilot phase) will have an AKI mismatch.
**Manual Fix:** Always run `createcrl` followed by `getcrl` immediately after signing.
```bash
./ejbca.sh ca createcrl JSIGROUP-ProductionRootCA
./ejbca.sh ca getcrl --caname JSIGROUP-ProductionRootCA -f artifacts/root.crl
```

---

## Summary of Manual Rationale
| Action | Command/Setting | Rationale |
| :--- | :--- | :--- |
| **HSM Access** | `--add-exports` | Bypasses Java 21 module isolation for PKCS#11. |
| **Key Gen** | `ejbca.sh generatekey` | Ensures Java-visibility on the Nitrokey. |
| **CSR Sign** | `AlternateSignatureAlgorithm=FALSE` | Standardizes OIDs for BouncyCastle compatibility. |
| **Shell Choice** | `PowerShell 5.1` | Required for legacy .NET Framework COM objects in AD CS. |
| **Revocation** | `createcrl / getcrl` | Synchronizes offline root status with AD CS infrastructure. |

---
*Created: 2026-04-27*
*Last Update: Phase 5 Integration*
