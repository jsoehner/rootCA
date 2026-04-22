#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${HOME}/rootCA"
PHASE2_DIR="$ROOT_DIR/phase2"
ARTIFACT_DIR="$PHASE2_DIR"
LOG_DIR="$PHASE2_DIR/logs"
PKCS11_MODULE=""
PKCS11_PIN="${PKCS11_PIN:-}"
TS="$(date -u '+%Y%m%dT%H%M%SZ')"
REPORT="$LOG_DIR/phase2-cleanup-verification-$TS.txt"

detect_pkcs11_module() {
  local candidate
  for candidate in \
    /usr/lib64/pkcs11/opensc-pkcs11.so \
    /usr/lib64/opensc-pkcs11.so \
    /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so \
    /usr/local/lib/opensc-pkcs11.so
  do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

usage() {
  cat <<'EOF'
Usage:
  phase2-verify-cleanup.sh [--artifact-dir PATH] [--pkcs11-module PATH] [--pin PIN]

Purpose:
  Verifies Phase 2 cleanup state without deleting retained evidence.

Behavior:
  - Confirms expected retained evidence files still exist.
  - Searches for obvious transient test artifacts under the Phase 2 artifact directory.
  - Optionally logs into a PKCS#11 token and records whether objects are present.

Notes:
  - Do not delete root-ca.pem or sub-ca.pem. These are retained evidence artifacts.
  - For HSM-backed verification, prefer passing the PIN via PKCS11_PIN env var.
  - If --pkcs11-module is omitted, the script will try to auto-detect an OpenSC module.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir)
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --pkcs11-module)
      PKCS11_MODULE="$2"
      shift 2
      ;;
    --pin)
      PKCS11_PIN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PKCS11_MODULE" ]]; then
  PKCS11_MODULE="$(detect_pkcs11_module || true)"
fi

mkdir -p "$LOG_DIR"

check_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "[x] $file"
  else
    echo "[ ] $file"
  fi
}

collect_transient_artifacts() {
  find "$ARTIFACT_DIR" -maxdepth 1 -type f \( \
    -iname 'test-*' -o \
    -iname '*pilot*.crt' -o \
    -iname '*pilot*.cer' -o \
    -iname '*test*.crt' -o \
    -iname '*test*.cer' -o \
    -iname '*.csr' -o \
    -iname '*.req' \
  \) | sort
}

probe_pkcs11_inventory() {
  if [[ -z "$PKCS11_MODULE" ]]; then
    echo "[ ] Token inventory not checked: --pkcs11-module not provided"
    return 0
  fi
  if ! command -v pkcs11-tool >/dev/null 2>&1; then
    echo "[ ] Token inventory not checked: pkcs11-tool not installed"
    return 0
  fi
  if [[ ! -f "$PKCS11_MODULE" ]]; then
    echo "[ ] Token inventory not checked: module not found at $PKCS11_MODULE"
    return 0
  fi
  if [[ -z "$PKCS11_PIN" ]]; then
    echo "[ ] Token inventory not checked: no PIN provided"
    return 0
  fi

  local token_output
  if ! token_output="$(pkcs11-tool --module "$PKCS11_MODULE" --login --pin "$PKCS11_PIN" --list-objects 2>&1 || true)"; then
    token_output="pkcs11-tool invocation failed"
  fi
  echo "$token_output"
  if grep -qiE 'no objects|no object' <<<"$token_output"; then
    echo "[x] Token inventory verified empty"
  elif [[ -z "$token_output" ]]; then
    echo "[x] Token inventory verified empty"
  else
    echo "[ ] Token inventory not empty or verification inconclusive"
  fi
}

latest_validation="$(ls -1t "$LOG_DIR"/phase2-cert-validation-*.txt 2>/dev/null | head -n 1 || true)"
mapfile -t transient_artifacts < <(collect_transient_artifacts || true)

{
  echo "Phase 2 Cleanup Verification"
  echo "Timestamp UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "Retained Evidence Files"
  check_file "$ARTIFACT_DIR/root-ca.pem"
  check_file "$ARTIFACT_DIR/sub-ca.pem"
  if [[ -n "$latest_validation" ]]; then
    echo "[x] $latest_validation"
  else
    echo "[ ] phase2-cert-validation-*.txt"
  fi
  echo
  echo "Transient Artifact Scan"
  if [[ ${#transient_artifacts[@]} -eq 0 ]]; then
    echo "[x] No obvious transient test or CSR artifacts found in $ARTIFACT_DIR"
  else
    echo "[ ] Potential transient artifacts remain:"
    printf ' - %s\n' "${transient_artifacts[@]}"
  fi
  echo
  echo "PKCS#11 Token Inventory"
  if [[ -n "$PKCS11_MODULE" ]]; then
    echo "Module path: $PKCS11_MODULE"
  fi
  probe_pkcs11_inventory
  echo
  echo "Operator Interpretation"
  echo "- root-ca.pem and sub-ca.pem are retained evidence and should remain in place."
  echo "- Mark 'Test certificates deleted' only after confirming any transient pilot/test artifacts are absent or intentionally retained."
  echo "- Mark 'Token inventory verified empty' only after the PKCS#11 check returns no objects under officer-controlled login."
} | tee "$REPORT"

echo "Report written: $REPORT"