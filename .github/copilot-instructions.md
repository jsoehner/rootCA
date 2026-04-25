# Copilot Instructions

## Project shape

This repository is an **operational runbook plus helper-script repo**, not a conventional application. The markdown phase documents are the source of truth for sequencing, gate conditions, and evidence requirements; the shell scripts automate the approved execution paths for the current platform baseline:

- **EJBCA 9.3.7**
- **WildFly 30.0.1.Final**
- **Java 21**
- **MariaDB**
- workspace rooted at **`~/rootCA`**

Read `README.md`, `Master-Plan-Status-Matrix.md`, and the relevant phase document before changing scripts or procedures. The project flow is phase-gated: governance/policy -> platform baseline -> certificate profiles -> pilot interoperability gate -> production key ceremony -> AD CS integration -> steady-state operations.

## Build and validation commands

### Platform and runtime

- Fedora bootstrap: `./phase1/phase1-bootstrap-fedora.sh`
- Host readiness check: `./phase1/phase1-verify-fedora.sh`
- MariaDB + WildFly datasource setup: `./phase1/phase1-setup-mariadb.sh`
- Build EJBCA EAR: `./phase1/phase1-build-ejbca9.sh`
- Start the production runtime with readiness failure surfaced immediately: `./phase1/phase1-run-wildfly30-ejbca9.sh --fail-fast`

### Certificate/profile validation

- Generate Phase 2 certificate profile XMLs: `./phase2/gen-cert-profiles.sh`
- Validate a **single** certificate artifact: `./phase2/phase2-validate-certs.sh --root-cert ./phase2/root-ca.pem --label manual`
- Validate the root + subordinate pair: `./phase2/phase2-validate-certs.sh --root-cert ./phase2/root-ca.pem --sub-cert ./phase2/sub-ca.pem --label prod`

### Phase 3 pilot flow

- Create isolated pilot DB/user: `./phase3/phase3-setup-pilot.sh`
- Switch EJBCA to the pilot database: `./phase3/phase3-run-wildfly30-pilot.sh --fail-fast`
- Create/export the pilot root CA: `./phase3/phase3-step3-pilot-root.sh`
- Run a **single** pilot validation against the pilot root only: `./phase3/phase3-validate-pilot-certs.sh --root-cert ./phase3/pilot-root.pem --label pilot-ecc-root`
- Validate the pilot chain: `./phase3/phase3-validate-pilot-certs.sh --root-cert ./phase3/pilot-root.pem --sub-cert ./phase3/pilot-sub.pem --label pilot-ecc-chain`
- Sign an AD CS subordinate CSR through the CLI path: `./phase3/phase3-sign-adcs-subordinate-csr.sh --csr <path-to.req> --ee-profile ADCS2025_SubCA_EE_Profile`
- Restore the production datasource after pilot work: `./phase3/phase3-run-wildfly30-prod.sh --fail-fast`

## High-level architecture

The repo is organized by **project phase**, and each phase combines three layers:

1. **Governance and runbooks** in top-level markdown files (`CA-Policy.md`, `Phase-*.md`, `README.md`, `Master-Plan-Status-Matrix.md`).
2. **Execution helpers** in `phase1/`, `phase2/`, and `phase3/` that implement the documented steps as repeatable shell workflows.
3. **Evidence outputs** under `phase*/logs/` plus exported certificates and generated profile artifacts that support sign-off and go/no-go decisions.

The most important runtime split is:

- **Production context**: `phase1/.db-credentials` + the `ejbca` MariaDB database + `phase1/phase1-run-wildfly30-ejbca9.sh`
- **Pilot context**: `phase3/.pilot-db-credentials` + the `ejbca_pilot` MariaDB database + `phase3/phase3-run-wildfly30-pilot.sh`

Both contexts deploy the same EJBCA EAR from `artifacts/ejbca/ejbca-ce-r9.3.7/dist/ejbca.ear` into the same WildFly 30 installation under `artifacts/appserver/wildfly-30.0.1.Final`. Phase 3 does not create a second app server; it **re-points the datasource and redeploys the same EAR** so pilot work stays isolated at the database/artifact level.

Phase 2 defines and exports the EJBCA certificate profiles that Phase 3 consumes. The important profile families are the exact named production/pilot pairs:

- `RootCAProd-ECC384-SHA384`
- `SubordCAProd-ECC384-SHA384`
- `RootCAPilot-ECC384-SHA384`
- `SubordCAPilot-ECC384-SHA384`
- `SubordCAPilot-RSA4096-SHA256`

Phase 3 is intentionally a **CLI-first** pilot. The current workflow creates the pilot root with `ejbca.sh ca init`, signs the external Windows AD CS CSR with `createcert`, and writes validation evidence to `phase3/logs/` for the formal go/no-go gate before any production ceremony work.

## Key repository conventions

- **Do not rename the deployed EAR.** Keep the deployment name aligned to **`ejbca.ear`**. The Phase 3 docs and logs explicitly call out that EJBCA CLI lookup breaks when deployment naming drifts.
- **Preserve the current platform baseline.** Scripts assume **WildFly 30 + EJBCA 9.3.7 + Java 21**. Do not introduce alternate runtime paths unless the phase docs are updated with the new baseline.
- **Prefer the scripted CLI workflows over ad hoc admin-web steps** when a script already exists, especially in Phase 3. The repo has moved toward non-UI execution for pilot root creation, CSR signing, and validation.
- **Keep pilot and production isolated.** Production credentials live in `phase1/.db-credentials`; pilot credentials live in `phase3/.pilot-db-credentials`. Phase 3 work should not point back at the production `ejbca` schema except when explicitly restoring the production context.
- **Use the exact certificate/profile names from the docs and scripts.** The project relies on frozen naming across docs, profile XMLs, validation scripts, and operator worksheets.
- **Treat `phase*/logs/` as part of the workflow, not just debug output.** Validation scripts write timestamped evidence files there, and the markdown logs reference those artifacts for phase closure and decision records.
- **Follow the shell style already used here.** The scripts consistently use `#!/usr/bin/env bash`, `set -euo pipefail`, explicit preflight checks, UTC timestamps in generated evidence, and explicit localhost health probes against `http://127.0.0.1:8080/ejbca/...`.
- **When changing runtime scripts, preserve the cleanup/redeploy pattern.** The WildFly launchers intentionally remove stale `EjbcaDS` datasource state and stale managed deployments before redeploying so pilot/production switching stays repeatable.
