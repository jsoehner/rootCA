#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${HOME}/rootCA"
PHASE2_DIR="$ROOT_DIR/phase2"
LOG_DIR="$PHASE2_DIR/logs"
TS="$(date -u '+%Y%m%dT%H%M%SZ')"
REPORT="$LOG_DIR/phase2-closeout-report-$TS.txt"

mkdir -p "$LOG_DIR"

check_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "[x] $file"
  else
    echo "[ ] $file"
  fi
}

probe_code() {
  local url="$1"
  curl --max-time 5 -s -o /dev/null -w '%{http_code}' "$url" || true
}

health_code="$(probe_code "http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth")"
ocsp_code="$(probe_code "http://127.0.0.1:8080/ejbca/publicweb/status/ocsp")"
latest_cleanup="$(ls -1t "$LOG_DIR"/phase2-cleanup-verification-*.txt 2>/dev/null | head -n 1 || true)"
cleanup_item_status="[ ]"
if [[ -n "$latest_cleanup" ]] \
  && grep -Fq "[x] No obvious transient test or CSR artifacts found" "$latest_cleanup" \
  && grep -Fq "[x] Token inventory verified empty" "$latest_cleanup"; then
  cleanup_item_status="[x]"
fi

{
  echo "Phase 2 Closeout Preparation Report"
  echo "Timestamp UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "Evidence Files"
  check_file "$PHASE2_DIR/root-ca.pem"
  check_file "$PHASE2_DIR/sub-ca.pem"
  latest_validation="$(ls -1t "$LOG_DIR"/phase2-cert-validation-*.txt 2>/dev/null | head -n 1 || true)"
  if [[ -n "$latest_validation" ]]; then
    echo "[x] $latest_validation"
  else
    echo "[ ] phase2-cert-validation-*.txt"
  fi
  echo
  echo "Runtime Readiness"
  echo "healthcheck_http=$health_code"
  echo "status_ocsp_http=$ocsp_code"
  if [[ "$health_code" == "200" && "$ocsp_code" == "200" ]]; then
    echo "[x] Runtime readiness probes passed"
  else
    echo "[ ] Runtime readiness probes passed"
  fi
  echo
  echo "Manual Sign-off Items"
  if [[ -n "$latest_cleanup" ]]; then
    echo "$cleanup_item_status Test certificates deleted and token confirmed empty"
    echo "    Source: $latest_cleanup"
  else
    echo "[ ] Test certificates deleted and token confirmed empty"
  fi
  echo "[ ] Officer A signature captured"
  echo "[ ] Officer B signature captured"
  echo
  echo "Next Step"
  echo "- After manual sign-off items are completed, update Phase 2 documents to Signed Off and start Phase 3 execution."
} | tee "$REPORT"

echo "Report written: $REPORT"
