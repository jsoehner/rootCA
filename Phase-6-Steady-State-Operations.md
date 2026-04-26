# Phase 6: Steady-State Controls and Audit Program

**Phase Status:** NOT STARTED; BLOCKED PENDING PHASE 5 COMPLETION  
**Date Created:** 2026-04-19  
**Phase Dependencies:** Phase 5 must be complete with subordinate CA operational  

## 1. Objective

Define repeatable governance and technical controls for long-term PKI reliability, including CRL cadence, audit evidence retention, and incident drills.

Deliverables:
- Annual operating calendar
- Recurring CRL and integrity procedures
- Incident tabletop drill program
- Compliance artifact inventory and retention model

## 2. Operating Calendar

Minimum cadence:
- Monthly: CA health review (AD CS + distribution endpoints)
- Quarterly: chain validation spot checks and endpoint sampling
- Semiannual: SOP review and access/custody recertification
- Annual: root CRL ceremony and publication
- Annual: disaster recovery tabletop exercise

## 3. Routine Maintenance Procedures

### 3.1 Root CRL Refresh

1. Schedule offline maintenance window.
2. Perform dual-control token activation.
3. Generate new root CRL on offline root.
4. Verify CRL signature and dates:
   - openssl crl -in root.crl -text -noout
5. Publish to distribution endpoint.
6. Validate from representative clients:
   - certutil -urlcache https://ca.jsigroup.local/crl/root.crl

SLO:
- New CRL available within 4 hours of signing
- Overlap of at least 7 days before prior CRL expiry

### 3.2 Chain Integrity Check

Quarterly checks:
- Validate root and subordinate fingerprints against approved inventory
- Validate AIA/CDP URLs are reachable
- Validate certutil -verify -urlfetch on representative issued certificates

### 3.3 Access and Custody Review

Semiannual review:
- Officer role assignment verification
- Safe access logs review
- PIN custody and dual-control verification
- EJBCA admin account review and least privilege check

## 4. Incident and Recovery Program

### 4.1 Scenarios to Drill

At minimum annually:
- HSM loss or failure
- Subordinate CA compromise
- Distribution endpoint outage
- Expired or stale CRL event

### 4.2 Drill Output Requirements

For each drill capture:
- Trigger description and timestamp
- Steps executed and timings
- Gaps/defects found
- Corrective actions, owner, and due date
- Sign-off by officers and auditor

## 5. Compliance Artifact Register

Maintain and retain:
- CA policy approvals and amendments
- Key ceremony records and fingerprints
- Issuance logs (subordinate and major changes)
- CRL history and publication evidence
- Access reviews and custody attestations
- Incident drill reports and corrective action tracking

Retention baseline:
- Ceremony and root records: permanent
- Operational logs: minimum 7 years
- Incident evidence: minimum 7 years

## 6. Monitoring and KPIs

Track at least:
- CRL on-time publication percentage
- Chain validation success rate across sample endpoints
- Mean time to recover for simulated incidents
- Number of policy exceptions per quarter

Target examples:
- CRL publication on-time: 100%
- Quarterly chain validation success: 100%
- Critical unresolved findings: 0

## 7. Change Management

Any change to algorithms, validity, extensions, custody model, or publication endpoints requires:
1. Written change request
2. Risk assessment and rollback plan
3. Approval by Officer A and Officer B
4. Audit entry and updated SOP versioning

## 8. Phase 6 Exit Criteria (Steady State Achieved)

All must be true for operational maturity:
- Annual calendar adopted
- CRL refresh process executed successfully at least once
- At least one tabletop drill completed with corrective actions tracked
- Compliance artifact register populated and reviewed
- KPI dashboard baseline established

Sign-off:
- Officer A: ____________________ Date: __/__/__
- Officer B: ____________________ Date: __/__/__
- Auditor: ______________________ Date: __/__/__
