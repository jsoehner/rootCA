# Phase 4 Execution Log: Production Root CA Ceremony

**Ceremony Date:** 2026-04-27  
**Start Time:** 11:45:00 EST  
**End Time:** 13:13:00 EST  
**Location:** jsoehner/rootCA Workspace (Linux)  
**Operators:** Antigravity (AI Assistant), jsoehner (User)

---

## 1. Executive Summary

The Production Root CA Key Ceremony was successfully completed. The **JSIGROUP-ProductionRootCA** is now live, backed by a non-extractable ECDSA P-384 private key stored on the **Nitrokey HSM 2**. All technical hurdles related to Java module encapsulation and HSM key visibility were resolved.

---

## 2. Technical Findings & Deviations

### 2.1 Java 21 Module Encapsulation (IllegalAccessException)
*   **Issue:** EJBCA (WildFly) running on Java 21 was blocked from accessing the `SunPKCS11` wrapper due to strict module encapsulation.
*   **Resolution:** Patched `standalone.conf` to inject `--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED`.

### 2.2 HSM Key Visibility (SunPKCS11 Orphan Key Issue)
*   **Issue:** Keys generated via `pkcs11-tool` were invisible to Java/EJBCA because they lacked a matching certificate object on the token.
*   **Resolution:** **DEVIATION:** Keys were regenerated natively via EJBCA (`cryptotoken generatekey`). This automatically injects the required dummy certificate object, making the key pair visible to the Java KeyStore provider.
*   **New Alias:** `root-ca-key-prod-v2` (successfully created and verified).

### 2.3 Subject DN Collision
*   **Issue:** A pilot CA (`JSIGROUP-RootCA`) created in earlier phases shared the exact Subject DN of the intended production root. EJBCA uses a hash of the Subject DN as the primary key (`cAId`), causing a database collision.
*   **Resolution:** Manually purged `JSIGROUP-RootCA` records from MariaDB (`CAData`, `CertificateData`, `CRLData`, `UserData`) and flushed EJBCA caches.

---

## 3. Ceremony Artifacts

### 3.1 Production Root Certificate
*   **CA Name:** `JSIGROUP-ProductionRootCA`
*   **Subject DN:** `CN=JSIGROUP Root CA, O=JSIGROUP, C=CA`
*   **Serial Number:** `75:05:09:8c:e7:96:95:fb:b9:13:71:74:ea:52:98:91:db:30:40:3f`
*   **Validity:** 10 Years (2026-04-27 to 2036-04-24)
*   **Algorithm:** `ECDSA with SHA-384` (secp384r1)
*   **SHA-256 Fingerprint:** `6D:03:22:29:AD:94:F1:48:6E:34:FE:7C:A1:E9:26:E0:36:95:91:99:C2:47:A1:93:6D:5F:C7:A9:45:D8:78:DA`

### 3.2 Initial CRL
*   **CRL Number:** 1
*   **Status:** Empty (No revocations)
*   **SHA-256 Fingerprint:** `51:19:90:4E:98:4A:C4:67:6A:CE:5D:4D:6E:BD:FD:00:03:C0:33:C8:3C:F3:6D:A3:2E:F4:8F:28:EA:E1:37:09`

---

## 4. Chronological Audit Trail

1.  **11:45:** Verified HSM presence and slot labeling (`SmartCard-HSM`).
2.  **11:57:** Detected missing EJBCA CLI binaries; triggered `ant ejbca-ejb-cli` rebuild.
3.  **12:04:** Initial `ca init` failed; diagnosed Java `SunPKCS11` "orphan key" invisibility issue.
4.  **12:07:** Successfully generated key pair `root-ca-key-prod-v2` natively via EJBCA.
5.  **13:02:** Detected Subject DN collision with existing Pilot CA.
6.  **13:05:** Executed MariaDB purge of Pilot CA records and flushed EJBCA caches.
7.  **13:13:** Successfully executed `ca init` for **JSIGROUP-ProductionRootCA**.

---

## 5. Next Steps
*   [ ] Export Root CA certificate to production distribution endpoint (`http://ca.jsigroup.local/root.cer`).
*   [ ] Proceed to **Phase 5** for AD CS Subordinate CSR signing.
