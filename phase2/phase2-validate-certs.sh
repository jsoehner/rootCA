#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${HOME}/rootCA"
OUT_DIR="$ROOT_DIR/phase2/logs"

usage() {
  cat <<'EOF'
Usage:
  ./phase2/phase2-validate-certs.sh --root-cert <path> [--sub-cert <path>] [--label <name>]

Examples:
  ./phase2/phase2-validate-certs.sh --root-cert ./phase2/test-root.crt --label pilot
  ./phase2/phase2-validate-certs.sh --root-cert ./phase2/test-root.crt --sub-cert ./phase2/test-subord.crt --label prod
EOF
}

ROOT_CERT=""
SUB_CERT=""
LABEL="manual"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-cert)
      ROOT_CERT="$2"
      shift 2
      ;;
    --sub-cert)
      SUB_CERT="$2"
      shift 2
      ;;
    --label)
      LABEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$ROOT_CERT" ]]; then
  echo "ERROR: --root-cert is required" >&2
  usage
  exit 1
fi

if [[ ! -f "$ROOT_CERT" ]]; then
  echo "ERROR: root cert not found: $ROOT_CERT" >&2
  exit 1
fi

if [[ -n "$SUB_CERT" && ! -f "$SUB_CERT" ]]; then
  echo "ERROR: subordinate cert not found: $SUB_CERT" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
TS="$(date -u '+%Y%m%dT%H%M%SZ')"
SUMMARY="$OUT_DIR/phase2-cert-validation-${LABEL}-${TS}.txt"

{
  echo "Phase 2 Certificate Validation"
  echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Label: $LABEL"
  echo

  echo "== Root Certificate =="
  echo "Input: $ROOT_CERT"
  openssl x509 -in "$ROOT_CERT" -text -noout > "$OUT_DIR/root-${LABEL}-${TS}.txt"
  openssl x509 -in "$ROOT_CERT" -noout -subject -issuer -serial -dates
  openssl x509 -in "$ROOT_CERT" -text -noout | grep -E 'Signature Algorithm|Basic Constraints|Key Usage|Subject Key Identifier|Authority Key Identifier|CA:TRUE|pathlen|pathLen' || true
  echo

  if [[ -n "$SUB_CERT" ]]; then
    echo "== Subordinate Certificate =="
    echo "Input: $SUB_CERT"
    openssl x509 -in "$SUB_CERT" -text -noout > "$OUT_DIR/sub-${LABEL}-${TS}.txt"
    openssl x509 -in "$SUB_CERT" -noout -subject -issuer -serial -dates
    openssl x509 -in "$SUB_CERT" -text -noout | grep -E 'Signature Algorithm|Basic Constraints|Key Usage|Subject Key Identifier|Authority Key Identifier|CRL Distribution Points|Authority Information Access|CA:TRUE|pathlen|pathLen' || true
    echo
  fi

  echo "Artifacts written:"
  echo "- $SUMMARY"
  echo "- $OUT_DIR/root-${LABEL}-${TS}.txt"
  if [[ -n "$SUB_CERT" ]]; then
    echo "- $OUT_DIR/sub-${LABEL}-${TS}.txt"
  fi
} | tee "$SUMMARY"
