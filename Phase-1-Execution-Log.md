# Phase 1 Execution Log

Date: 2026-04-19
Host: fedora
Workspace: ~/rootCA
Phase status: Completed (Signed Off)

## Baseline Snapshot (UTC)

Timestamp:
- Sun Apr 19 04:18:48 PM UTC 2026

Binary availability:
- java: MISSING
- ant: MISSING
- mysql: MISSING
- mariadb: MISSING
- psql: MISSING
- opensc-tool: /usr/bin/opensc-tool
- pkcs11-tool: /usr/bin/pkcs11-tool
- pcsc_scan: /usr/bin/pcsc_scan

PKCS#11 module paths found:
- /usr/lib64/pkcs11/onepin-opensc-pkcs11.so
- /usr/lib64/pkcs11/opensc-pkcs11.so
- /usr/lib64/onepin-opensc-pkcs11.so
- /usr/lib64/opensc-pkcs11.so

Token/slot visibility:
- Slot 0 detected
- Reader: Identiv uTrust Token Flex [CCID Interface]
- Token label: SmartCard-HSM
- Token serial: USCLX100321
- Token flags: login required, rng, token initialized, PIN initialized

PC/SC service:
- systemctl is-active pcscd: active
- systemctl is-enabled pcscd: indirect

Network interfaces:
- lo: UP
- enp3s0f0: UP
- docker0: DOWN

## Readiness Summary

Ready:
- OpenSC tooling
- PKCS#11 module availability
- HSM token visibility
- pcscd service active

Not ready:
- Java runtime (required for EJBCA)
- Ant (required for EJBCA build/deploy)
- SQL client tools

Root cause detail:
- Java package is installed, but `/usr/bin/java` is broken due to alternatives pointing at `/usr/lib/jvm/java-24-openjdk/bin/java` (non-executable target).

## Action Taken

1. Phase 1 baseline executed and captured.
2. Dependency bootstrap script prepared: [phase1-bootstrap-fedora.sh](phase1/phase1-bootstrap-fedora.sh)
3. Standalone verifier prepared and executed: [phase1-verify-fedora.sh](phase1/phase1-verify-fedora.sh)
4. Bootstrap execution was started and reached sudo authentication prompt.
5. User executed sudo remediation successfully (`sudo ./phase1/phase1-remediate-fedora.sh`).
6. Verified prerequisites now present: java, ant, mysql/mariadb, psql.
7. Staged EJBCA source from GitHub tag `EJBCA_8_0_20230531`:
	- `~/rootCA/artifacts/ejbca/ejbca-ce-EJBCA_8_0_20230531.zip`
	- `~/rootCA/artifacts/ejbca/Keyfactor-ejbca-ce-7d72bd9`
8. Staged local supported appserver for detection:
	- `~/rootCA/artifacts/appserver/wildfly-10.1.0.Final`
9. Initial build failed due mixed JDK artifacts (Java 25 class files in build tree).
10. Resolved by forcing Java 21 and clean rebuild:
	 - `JAVA_HOME=/usr/lib/jvm/java-21-openjdk ... ant clean build`
	 - Result: `BUILD SUCCESSFUL`
11. Deploy stage advanced:
	- `ant deployear` copied `dist/ejbca.ear` into local appserver deployment directory.
12. Runtime compatibility testing performed:
	- WildFly 30.0.1.Final + Java 21 started successfully after adding datasource `java:/EjbcaDS`.
13. Live endpoint validation passed:
	- `http://127.0.0.1:8080/ejbca/adminweb/` -> HTTP 200
	- `http://127.0.0.1:8080/ejbca/publicweb/status/ocsp` -> HTTP 200
14. Datasource dependency resolved on WildFly 30:
	- Added `java:/EjbcaDS` via `jboss-cli.sh`.

## Current Blocker

- No active blocker for Phase 1 phase-gate closure.
- Minor runtime warning remains in log regarding BouncyCastle classloader visibility; treated as non-blocking for Phase 1 platform readiness.

Pending install items after bootstrap:
- None (prerequisites now installed and verified)

Remediation script added:
- [phase1-remediate-fedora.sh](phase1/phase1-remediate-fedora.sh)
	- Sets Java alternative to `/usr/lib/jvm/java-21-openjdk/bin/java`
	- Installs `ant`, `mariadb`, and `postgresql`
	- Runs [phase1-verify-fedora.sh](phase1/phase1-verify-fedora.sh)

Build helper added (historical, retired after WildFly 30 migration):
- [phase1-build-ejbca.sh](phase1/phase1-build-ejbca.sh)
	- Forces Java 21 for Ant execution
	- Sets APPSRV_HOME to local WildFly 10.1.0.Final
	- Runs clean build and writes log to `~/rootCA/phase1/phase1-ant-build.log`

Current runtime helper (active baseline):
- [phase1-run-wildfly30-ejbca9.sh](phase1/phase1-run-wildfly30-ejbca9.sh)
	- Runs WildFly 30.0.1.Final with EJBCA 9 runtime path

Hardening helper added:
- [phase1-hardening-fedora.sh](phase1/phase1-hardening-fedora.sh)
	- Applies sudo-level baseline hardening (auditd, service minimization, audit rules)
	- Intended for dedicated CA host execution

## Phase Gate Decision

Formal Phase 1 sign-off items closed on 2026-04-19.

Decision:
- Phase gate is clean for Phase 2 start.

Recommended next command sequence:

```bash
cd ~/rootCA
./phase1/phase1-verify-fedora.sh
```

Then proceed with:
- [Phase-2-Crypto-Profiles.md](Phase-2-Crypto-Profiles.md)

Milestone reached:
- EJBCA clean build completed successfully with Java 21 and local appserver detection.

Phase 1 runtime milestone reached:
- EJBCA deployed and serving key web contexts on WildFly 30.0.1.Final with Java 21.

Formal sign-off closure recorded:
- Phase 1 status updated to Completed (Signed Off).
- Remaining warnings documented as non-blocking for Phase 2 entry.
