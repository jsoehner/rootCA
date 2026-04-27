# Phase 1: Offline EJBCA Root Platform Baseline

**Phase Status:** COMPLETED AND SIGNED OFF  
**Date Created:** 2026-04-19  
**Phase Dependencies:** Phase 0 (Governance) completed; dependency satisfied  

---

## 1. Overview

Phase 1 builds the hardened Linux host that will run EJBCA as an offline root CA. This platform must **have zero network connectivity** during key ceremonies and maintain strict physical/logical controls over HSM access.

**Deliverables:**
- Hardened Linux baseline (no network interfaces active during ceremonies)
- EJBCA installation with PKCS#11 crypto token configured
- SmartCardHSM or Nitrokey HSM initialized and authenticated
- Health checks passing (EJBCA web admin responsive, token accessible via pkcs11-tool)
- Formal platform sign-off via Phase 1 completion checklist

### 1.1 Fedora Fast Path (Current Host)

If executing on Fedora (current environment), use these local helper scripts:

```bash
cd ~/rootCA
chmod +x ./phase1/phase1-bootstrap-fedora.sh ./phase1/phase1-verify-fedora.sh
sudo ./phase1/phase1-bootstrap-fedora.sh
./phase1/phase1-verify-fedora.sh
```

These scripts install Java/Ant/SQL clients and verify OpenSC/HSM readiness.

---

## 2. Host Platform Selection

### 2.1 Recommended Configuration

| Component | Specification | Rationale |
|-----------|---------------|-----------|
| **OS** | Ubuntu Server 22.04 LTS (latest patched kernel) or RHEL 9 | Long-term support; container-free; stable PKCS#11 bindings |
| **CPU** | 2+ cores | Sufficient for async CRL signing; no performance requirement |
| **RAM** | 4 GB minimum (8 GB preferred) | Java JVM for EJBCA; no large endpoint database |
| **Storage** | 50 GB SSD (offline storage only; no cloud/networked storage) | Local filesystem only; no SMB/NFS mounted datastores |
| **Network Interfaces** | Disable during ceremonies (no Ethernet, no WiFi) | Strict offline requirement during key generation and signing |
| **USB Ports** | 1+ USB 3.0 (HSM token only) | Nitrokey or SmartCardHSM connection |
| **Boot Media** | Encrypted USB key or SATA SSD | Boot OS image, EJBCA binaries, audit logs |

### 2.2 Host Acquisition & Isolation

- **Physical Location:** Locked room or secure cabinet; video surveillance (optional but recommended)
- **Network:** Physically disconnect Ethernet cable; disable WiFi in BIOS/UEFI (if present)
- **Power:** UPS recommended for clean shutdown during ceremony
- **Access:** Two-person physical custody rule (both officers must be present to power on during ceremonies)

---

## 3. Hardened Linux Baseline

### 3.1 OS Installation & Initial Hardening

```bash
# Step 1: Install Ubuntu 22.04 LTS with minimal services
# Use text-mode installer; do NOT install extra packages (skip "LAMP", "Docker", etc.)

# Step 2: Update kernel and packages
sudo apt update && sudo apt full-upgrade -y
sudo apt autoremove -y

# Step 3: Disable unnecessary services
sudo systemctl disable bluetooth.service
sudo systemctl disable cups.service
sudo systemctl disable avahi-daemon.service
sudo systemctl mask systemd-resolved.service  # Use static /etc/hosts instead

# Step 4: Disable IPv6 (if not required)
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee /etc/sysctl.d/99-disable-ipv6.conf
sudo sysctl -p

# Step 5: Configure firewall (UFW) - ALLOW SSH only if needed for admin access (locked down with key-based auth)
# OR disable UFW entirely if direct console access is standard
sudo systemctl disable ufw.service
sudo systemctl mask ufw.service

# Step 6: Set strong SSH key (if SSH needed for administration from secure jump box)
# Generate 4096-bit RSA key on secure admin workstation; copy public key to ~/.ssh/authorized_keys
# Disable password auth in /etc/ssh/sshd_config:
#   PasswordAuthentication no
#   PermitRootLogin no
#   PubkeyAuthentication yes

# Step 7: Configure NTP (for time-of-sign accuracy in ceremonies)
sudo apt install -y chrony
# Create /etc/chrony/chrony.conf:
#   server ntp.ubuntu.com iburst
#   local stratum 10
sudo systemctl restart chrony
sudo chronyc tracking  # Verify NTP is synchronized

# Step 8: Set up audit logging (auditd)
sudo apt install -y auditd audispd-plugins
# Add audit rules (example):
sudo auditctl -w /root -p wa -k root_changes  # Monitor root dir for write/attr changes
sudo auditctl -w /etc/ejbca -p wa -k ejbca_config  # Monitor EJBCA config
sudo service auditd restart
```

### 3.2 File System Encryption (Recommended for Production)

```bash
# LUKS encryption for data partition (do this at OS install time if possible)
# If post-install, use full-disk encryption via:
#   sudo cryptsetup luksFormat /dev/sdX      # Replace X with actual device
#   sudo cryptsetup luksOpen /dev/sdX crypt1
#   sudo mkfs.ext4 /dev/mapper/crypt1
#   sudo mount /dev/mapper/crypt1 /mnt
# Ensure /etc/fstab includes crypt1 entry with noauto flag (decrypt on boot)

# For offline-only host, filesystem encryption provides defense-in-depth
# but is not mandatory if physical security is strong

---

## 4. Lessons Learned & Evidence (2026-04-19)

### Operator Notes & Execution Summary
- Fedora baseline scripts required sudo remediation due to Java alternatives misconfiguration; resolved by running `phase1-remediate-fedora.sh`.
- Java 21 and Ant must be explicitly set for EJBCA build compatibility; Java 25 artifacts caused initial build failure.
- EJBCA 9.3.7 deployed successfully on WildFly 30.0.1.Final with Java 21 after datasource configuration.
- **Critical Java 21 Finding:** WildFly `standalone.conf` requires `--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED` to allow EJBCA access to the HSM PKCS#11 module (discovered/remediated during Phase 4).
- **Critical Windows Requirement:** All PowerShell automation for AD CS (e.g., `Prepare-Enterprise.ps1`) must be executed in **Windows PowerShell 5.1**. Newer PowerShell 7/Core versions fail to load the `ServerManager` and `ADCSDeployment` modules due to missing .NET Framework dependencies (discovered/remediated during Phase 5).
- All health checks (admin web, OCSP) passed post-deployment.
- Minor BouncyCastle classloader warning in logs, but not blocking for phase gate.

### Evidence Artifacts
- [phase1/phase1-bootstrap-fedora.sh](phase1/phase1-bootstrap-fedora.sh)
- [phase1/phase1-verify-fedora.sh](phase1/phase1-verify-fedora.sh)
- [phase1/phase1-remediate-fedora.sh](phase1/phase1-remediate-fedora.sh)
- [phase1/phase1-build-ejbca9.sh](phase1/phase1-build-ejbca9.sh)
- [phase1/phase1-run-wildfly30-ejbca9.sh](phase1/phase1-run-wildfly30-ejbca9.sh)
- [phase1/logs/Phase-1-Execution-Log.md](phase1/logs/Phase-1-Execution-Log.md)

### Closeout Checklist (as of 2026-04-19)
- [x] All platform prerequisites installed and verified
- [x] EJBCA clean build and deployment validated
- [x] Health checks (admin, OCSP) passed
- [x] Phase 1 sign-off recorded (no active blockers)

**Phase 1 is formally closed. Proceed to Phase 2.**
```

### 3.3 Network Interface Configuration

```bash
# Verify network connectivity is disabled during ceremonies
# For wired Ethernet:
sudo ip link set eth0 down  # Disable interface
# Verify:
ip link show  # Should show eth0 DOWN if offline

# For WiFi:
sudo rfkill block wifi  # Disable WiFi at BIOS level / via rfkill
# Verify:
rfkill list  # wifi should show "Soft blocked: yes"

# For USB network adapters: physically remove or don't install drivers
```

---

## 4. EJBCA Installation

### 4.1 Prerequisites

```bash
# Install Java Development Kit (minimum supported: Java 21)
sudo apt install -y openjdk-21-jdk-headless
java -version  # Verify

# Install Ant (build tool for EJBCA)
sudo apt install -y ant

# Install MariaDB or PostgreSQL (local database for EJBCA)
# Example: MariaDB (lightweight)
sudo apt install -y mariadb-server
sudo mysql_secure_installation  # Set root password, remove test databases

# Create EJBCA database user
sudo mysql -u root -p << 'EOF'
CREATE DATABASE ejbca;
CREATE USER 'ejbca'@'localhost' IDENTIFIED BY 'CHANGE_THIS_PASSWORD';
GRANT ALL PRIVILEGES ON ejbca.* TO 'ejbca'@'localhost';
FLUSH PRIVILEGES;
EXIT;
EOF
```

### 4.2 EJBCA Download & Configuration

```bash
# Download EJBCA 9.3.7 (current project baseline)
mkdir -p /opt/ejbca
cd /opt/ejbca
wget https://github.com/Keyfactor/ejbca-ce/archive/refs/tags/r9.3.7.zip -O ejbca-ce-r9.3.7.zip
unzip ejbca-ce-r9.3.7.zip
cd ejbca-ce-r9.3.7

# Configure EJBCA for offline root
# Edit conf/cesecore.properties (create if missing):
cat > conf/cesecore.properties << 'EOF'
# Database connection
db.datasource=org.mariadb.jdbc.MariaDbDataSource
db.url=jdbc:mariadb://localhost/ejbca
db.driver=org.mariadb.r1.mysql.Driver
db.username=ejbca
db.password=CHANGE_THIS_PASSWORD
db.pool.size=10

# PKCS#11 token configuration (will be defined in Section 4.4)
# Placeholder; actual values set post-installation

# Disable external connectivity (no OCSP/AIA lookups during ceremonies)
ocsp.enabled=false
crl.enabled=true
crl.renewal.enabled=false  # Manual CRL signing only

# TLS certificate settings
web.https.enabled=true
web.https.keystore.path=/opt/ejbca/ejbca-ce-r9.3.7/p12/tomcat.jks
web.https.keystore.password=CHANGE_THIS_PASSWORD

# Audit logging
audit.log.enabled=true
audit.log.dir=/var/log/ejbca
EOF

# Configure EJBCA database
ant create-db  # Creates tables in MariaDB

# Build EJBCA
ant clean build  # Compiles all EJBCA modules

# Deploy EJBCA EAR to WildFly 30 (project runtime baseline)
export APPSRV_HOME=~/rootCA/artifacts/appserver/wildfly-30.0.1.Final
ant deployear

# Start runtime using project launcher (Java 21 + WildFly 30)
cd ~/rootCA
./phase1/phase1-run-wildfly30-ejbca9.sh
```

### 4.3 EJBCA Web Admin Access

```bash
# Generate admin client certificate (temp; for initial configuration only)
# This cert is used to authenticate to EJBCA web admin via mutual TLS

# Default URL: https://localhost:8443/ejbca/adminweb/
# Default credentials: superadmin (internal; configured in cesecore.properties)

# Verify EJBCA is running:
curl -k https://localhost:8443/ejbca/healthcheck/ejbcahealthcheck.html
# Expected response: HTTP 200 OK with "ALLOK-status.properties" output
```

---

## 5. PKCS#11 HSM Integration

### 5.1 OpenSC Module Installation

```bash
# Install OpenSC and PKCS#11 tools
sudo apt install -y opensc opensc-pkcs11 libpcsclite1 pcscd

# Verify PKCS#11 module is discoverable
find /usr/lib -name '*opensc-pkcs11*.so'
# Expected output: /usr/lib64/opensc-pkcs11.so (or /usr/lib/opensc-pkcs11.so on 32-bit systems)

# Verify pcscd daemon is running
sudo systemctl status pcscd
# If not running:
sudo systemctl enable pcscd
sudo systemctl start pcscd

# Test HSM detection
pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --list-slots
# Expected output: Token label "SmartCard-HSM" or "NitroKey HSM 2"
```

### 5.2 HSM Initialization (SmartCardHSM / Nitrokey)

#### 5.2.1 SmartCardHSM (Primary Production Selection, Post-Validation)

```bash
# Verify token is initialized (perform Phase 0 validation first)
pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin 69657145 --list-objects
# Expected: User PIN 69657145 accepted; objects listed

# No further initialization needed if token is pre-initialized by validation phase
# If re-initialization required:
pkcs15-init --erase-card  # DESTRUCTIVE; erases all keys
pkcs15-init --create-pkcs15 --so-pin 1234567890 --pin 1234567890
# (Use strong replacement PINs per Phase 0 policy)
```

#### 5.2.2 Nitrokey HSM 2 (Backup Selection, Post-Validation)

```bash
# Similar to SmartCardHSM; verify token accessible
pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --list-slots
# Look for "NitroKey" in token name

# Use validated PIN from HSM validation phase (Section 9.1 of Session Memory)
# No re-initialization during Phase 1 (preserve validated state)
```

---

## 6. EJBCA Crypto Token Configuration

### 6.1 Create Crypto Token for Root CA Signing

**Via EJBCA Web Admin:**

1. **Navigate:** Administration → Crypto Tokens
2. **Create New Token:**
   - **Token Name:** `RootCA-HSM-Primary`
   - **Token Type:** PKCS#11
   - **Properties:**
     - **PKCS#11 Module:** `/usr/lib64/opensc-pkcs11.so`
     - **Token Label:** `SmartCard-HSM` (or `NitroKey` if backup selected)
     - **Slot ID:** 0 (auto-detect; verify via pkcs11-tool output)
     - **PIN:** *(enter User PIN from HSM; see Phase 0 policy)*
     - **PIN Cache Duration:** 0 (no caching; require PIN per operation)
   
3. **Activate Token:**
   - Click **Generate New Key** to verify token responds
   - **Key Size:** 384 (for ECC P-384 root)
   - **Key Algorithm:** ECDSA  (*or* RSA 4096 if fallback selected)
   - **Key Label:** `root-ca-key-prod-ecc384` 
   - Click **Generate** (this creates test key on HSM)
   
4. **Delete Test Key** (cleanup):
   - Delete the test key label from token (via EJBCA admin or pkcs11-tool)
   - Verify token is empty before production ceremony:
     ```bash
     pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin 69657145 --list-objects
     # Should return: no objects (clean token)
     ```

---

## 7. Health Checks & Validation

### 7.1 Pre-Ceremony Validation Checklist

```bash
# 1. EJBCA Admin Console responds
curl -k https://localhost:8443/ejbca/adminweb/ -o /dev/null -s -w "%{http_code}\n"
# Expected: 200 (or 302 redirect)

# 2. Database is accessible
sudo mysql -u ejbca -p -e "SELECT 1;" ejbca
# Expected: 1 row returned

# 3. HSM token is present and accessible
pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --list-slots
# Expected: SmartCard-HSM or NitroKey listed

# 4. HSM authentication works
pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --pin 69657145 --list-objects
# Expected: Login successful; no objects (clean token for production)

# 5. Audit logging is active
tail -20 /var/log/ejbca/audit.log
# Expected: Messages showing EJBCA configured correctly

# 6. Time synchronization verified
date && chronyc tracking
# Expected: Correct date/time; NTP synchronized

# 7. Network is offline
ip link show | grep state
# Expected: eth0 DOWN (or only loopback UP)
rfkill list
# Expected: WiFi "Soft blocked: yes"
```

### 7.2 Formal Phase 1 Completion Checklist

Recorded closure (2026-04-19):

```
[x] Linux baseline hardened (service minimization and audit baseline implemented)
[x] EJBCA installed and deployed (admin/status endpoints validated)
[x] Database datasource initialized and connected (java:/EjbcaDS bound)
[x] PKCS#11 module discovered and tested
[x] HSM token initialized and authenticated
[x] Crypto token workflow validated in platform prep context
[x] Test deployment and runtime validation completed
[x] Network control procedure defined for ceremony mode
[x] Time verification checks available in runbook
[x] Audit baseline configured and tested for Phase 1 scope
[x] Health checks passing (EJBCA admin/status + PKCS#11 visibility)
[x] Phase 1 sign-off: Recorded (Officer A attestation captured in project record)
[x] Phase 1 sign-off: Recorded (Officer B attestation captured in project record)
[x] Date: 2026-04-19
```

Sign-off evidence sources:
- [Phase-1-Execution-Log.md](Phase-1-Execution-Log.md)
- [phase1](phase1)

---

## 8. Post-Phase-1 Handoff to Phase 2

Phase 1 sign-off is complete. Next actions:

1. **Lock down the host:** Disable remote access (powerdown SSH if it was enabled for installation)
2. **Preserve audit trail:** Copy `/var/log/ejbca/*` to secure external media
3. **Proceed to Phase 2:** Define root and subordinate CA certificate profiles in EJBCA

---

## 9. Emergency Recovery

### 9.1 Password Recovery (If Admin Lost)

If EJBCA admin password or database password is lost, recreate via database directly:
```sql
-- Connect as root and reset EJBCA admin user
USE ejbca;
DELETE FROM AdminEntity WHERE adminname='superadmin';
INSERT INTO AdminEntity (adminname, caid, admintype, admingroupid) 
  VALUES ('superadmin', 0, 0, 1);
```

### 9.2 HSM Token Lock-Out (If Incorrect PIN Entered 3 Times)

If PIN lock-out occurs:
```bash
# Unlock via SO-PIN (requires Officer B present)
pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --login --so-pin 1234567890 --unlock-pin
# (Replace with actual SO-PIN from safe)

# Or reinitialize token (DESTRUCTIVE; requires new key ceremony):
pkcs15-init --erase-card
pkcs15-init --create-pkcs15 --so-pin 1234567890 --pin 1234567890
```

---

**End of Phase 1 Documentation**
