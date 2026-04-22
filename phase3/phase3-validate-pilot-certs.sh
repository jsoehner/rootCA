#!/usr/bin/env bash
# phase3-validate-pilot-certs.sh
# OpenSSL validation of pilot root and subordinate CA certificates.
# Generates structured evidence artifacts for the Phase 3 go/no-go decision.
#
# Usage:
#   ./phase3/phase3-validate-pilot-certs.sh --root-cert <path> [--sub-cert <path>] \
#       [--end-entity <path>] [--label <name>]
#
# Examples:
#   # Validate pilot root only
#   ./phase3/phase3-validate-pilot-certs.sh \
#       --root-cert ./phase3/pilot-root.pem --label pilot-ecc
#
#   # Validate full chain (root + subordinate)
#   ./phase3/phase3-validate-pilot-certs.sh \
#       --root-cert ./phase3/pilot-root.pem \
#       --sub-cert  ./phase3/pilot-sub.pem \
#       --label pilot-ecc
#
#   # Validate full chain including an end-entity certificate
#   ./phase3/phase3-validate-pilot-certs.sh \
#       --root-cert    ./phase3/pilot-root.pem \
#       --sub-cert     ./phase3/pilot-sub.pem \
#       --end-entity   ./phase3/pilot-end-entity.pem \
#       --label pilot-ecc-full

set -euo pipefail

ROOT_DIR="${HOME}/rootCA"
OUT_DIR="$ROOT_DIR/phase3/logs"

usage() {
  cat <<'EOF'
Usage:
  ./phase3/phase3-validate-pilot-certs.sh --root-cert <path> [--sub-cert <path>]
      [--end-entity <path>] [--label <name>]

Options:
  --root-cert   Path to pilot root CA certificate (PEM)           [required]
  --sub-cert    Path to pilot subordinate CA certificate (PEM)    [optional]
  --end-entity  Path to end-entity certificate issued by pilot CA [optional]
  --label       Short label used in output filenames              [default: pilot]
  -h/--help     Show this help

Output files are written to ~/rootCA/phase3/logs/
EOF
}

ROOT_CERT=""
SUB_CERT=""
END_ENTITY=""
LABEL="pilot"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-cert)   ROOT_CERT="$2"; shift 2 ;;
    --sub-cert)    SUB_CERT="$2";  shift 2 ;;
    --end-entity)  END_ENTITY="$2"; shift 2 ;;
    --label)       LABEL="$2";     shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$ROOT_CERT" ]]; then
  echo "ERROR: --root-cert is required" >&2
  usage; exit 1
fi
[[ -f "$ROOT_CERT" ]] || { echo "ERROR: root cert not found: $ROOT_CERT" >&2; exit 1; }
[[ -n "$SUB_CERT"    && ! -f "$SUB_CERT"    ]] && { echo "ERROR: sub cert not found: $SUB_CERT" >&2;             exit 1; }
[[ -n "$END_ENTITY"  && ! -f "$END_ENTITY"  ]] && { echo "ERROR: end-entity cert not found: $END_ENTITY" >&2;   exit 1; }

mkdir -p "$OUT_DIR"
TS="$(date -u '+%Y%m%dT%H%M%SZ')"
SUMMARY="$OUT_DIR/phase3-cert-validation-${LABEL}-${TS}.txt"

PASS_COUNT=0
FAIL_COUNT=0

check() {
  local label="$1"; local result="$2"
  if [[ "$result" == "PASS" ]]; then
    echo "  [PASS] $label"
    (( PASS_COUNT++ )) || true
  else
    echo "  [FAIL] $label"
    (( FAIL_COUNT++ )) || true
  fi
}

{
  echo "Phase 3 Pilot Certificate Validation"
  echo "Timestamp  : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Label      : $LABEL"
  echo "Root cert  : $ROOT_CERT"
  [[ -n "$SUB_CERT"   ]] && echo "Sub cert   : $SUB_CERT"
  [[ -n "$END_ENTITY" ]] && echo "End-entity : $END_ENTITY"
  echo ""

  # -------------------------------------------------------------------------
  echo "== Root CA Certificate =="
  openssl x509 -in "$ROOT_CERT" -noout -subject -issuer -serial -dates
  echo ""

  echo "-- Signature Algorithm --"
  openssl x509 -in "$ROOT_CERT" -noout -text | grep -E 'Signature Algorithm' | head -2 || true
  echo ""

  echo "-- Key Extensions --"
  openssl x509 -in "$ROOT_CERT" -noout -text | \
    grep -E 'Basic Constraints|Key Usage|Subject Key Identifier|Authority Key Identifier|CA:TRUE|pathlen|pathLen|CRL Distribution|Authority Information' || true
  echo ""

  echo "-- Self-signed check --"
  ROOT_SUBJECT="$(openssl x509 -in "$ROOT_CERT" -noout -subject | sed 's/^subject=//')"
  ROOT_ISSUER="$(openssl x509 -in "$ROOT_CERT"  -noout -issuer | sed 's/^issuer=//')"
  if [[ "$ROOT_SUBJECT" == "$ROOT_ISSUER" ]]; then
    check "Root is self-signed (subject == issuer)" "PASS"
  else
    check "Root is self-signed (subject == issuer)" "FAIL"
    echo "    Subject: subject=$ROOT_SUBJECT"
    echo "    Issuer : issuer=$ROOT_ISSUER"
  fi

  echo ""
  echo "-- Basic Constraints: CA:TRUE --"
  if openssl x509 -in "$ROOT_CERT" -noout -text | grep -q 'CA:TRUE'; then
    check "Root has CA:TRUE" "PASS"
  else
    check "Root has CA:TRUE" "FAIL"
  fi

  echo ""
  echo "-- Key Usage: keyCertSign + cRLSign --"
  KU_LINE="$(openssl x509 -in "$ROOT_CERT" -noout -text | grep -A1 'Key Usage' | tr '\n' ' ')"
  if echo "$KU_LINE" | grep -q 'Certificate Sign' && echo "$KU_LINE" | grep -q 'CRL Sign'; then
    check "Root Key Usage includes keyCertSign and cRLSign" "PASS"
  else
    check "Root Key Usage includes keyCertSign and cRLSign" "FAIL"
    echo "    KeyUsage line: $KU_LINE"
  fi

  echo ""
  echo "-- Self-signature verification --"
  if openssl verify -CAfile "$ROOT_CERT" "$ROOT_CERT" >/dev/null 2>&1; then
    check "Root self-signature verifies" "PASS"
  else
    check "Root self-signature verifies" "FAIL"
  fi

  # -------------------------------------------------------------------------
  if [[ -n "$SUB_CERT" ]]; then
    echo ""
    echo "== Subordinate CA Certificate =="
    openssl x509 -in "$SUB_CERT" -noout -subject -issuer -serial -dates
    echo ""

    echo "-- Signature Algorithm --"
    openssl x509 -in "$SUB_CERT" -noout -text | grep -E 'Signature Algorithm' | head -2 || true
    echo ""

    echo "-- Key Extensions --"
    openssl x509 -in "$SUB_CERT" -noout -text | \
      grep -E 'Basic Constraints|Key Usage|Subject Key Identifier|Authority Key Identifier|CA:TRUE|pathlen|pathLen|CRL Distribution|Authority Information' || true
    echo ""

    echo "-- CA:TRUE with pathLen=0 --"
    SUB_TEXT="$(openssl x509 -in "$SUB_CERT" -noout -text)"
    if echo "$SUB_TEXT" | grep -q 'CA:TRUE'; then
      check "Subordinate has CA:TRUE" "PASS"
    else
      check "Subordinate has CA:TRUE" "FAIL"
    fi
    if echo "$SUB_TEXT" | grep -qE 'pathlen:0|pathLen:0|Path Length Constraint: 0'; then
      check "Subordinate has pathLen=0" "PASS"
    else
      check "Subordinate has pathLen=0" "FAIL"
    fi

    echo ""
    echo "-- Chain verification (root → sub) --"
    if openssl verify -CAfile "$ROOT_CERT" "$SUB_CERT" >/dev/null 2>&1; then
      check "Subordinate chain verifies against root" "PASS"
    else
      check "Subordinate chain verifies against root" "FAIL"
      openssl verify -CAfile "$ROOT_CERT" "$SUB_CERT" 2>&1 | sed 's/^/    /' || true
    fi
  fi

  # -------------------------------------------------------------------------
  if [[ -n "$END_ENTITY" ]]; then
    echo ""
    echo "== End-Entity Certificate =="
    openssl x509 -in "$END_ENTITY" -noout -subject -issuer -serial -dates
    echo ""

    echo "-- Signature Algorithm --"
    openssl x509 -in "$END_ENTITY" -noout -text | grep -E 'Signature Algorithm' | head -2 || true
    echo ""

    if [[ -n "$SUB_CERT" ]]; then
      echo "-- Full chain verification (root → sub → end-entity) --"
      CHAIN_FILE="$(mktemp /tmp/phase3-chain-XXXXXX.pem)"
      cat "$SUB_CERT" "$ROOT_CERT" > "$CHAIN_FILE"
      if openssl verify -CAfile "$ROOT_CERT" -untrusted "$CHAIN_FILE" "$END_ENTITY" >/dev/null 2>&1; then
        check "End-entity full chain verifies" "PASS"
      else
        check "End-entity full chain verifies" "FAIL"
        openssl verify -CAfile "$ROOT_CERT" -untrusted "$CHAIN_FILE" "$END_ENTITY" 2>&1 | sed 's/^/    /' || true
      fi
      rm -f "$CHAIN_FILE"
    else
      echo "-- Chain verification (root → end-entity, no intermediate) --"
      if openssl verify -CAfile "$ROOT_CERT" "$END_ENTITY" >/dev/null 2>&1; then
        check "End-entity chain verifies against root" "PASS"
      else
        check "End-entity chain verifies against root" "FAIL"
      fi
    fi
  fi

  # -------------------------------------------------------------------------
  echo ""
  echo "== Validation Summary =="
  echo "  PASS : $PASS_COUNT"
  echo "  FAIL : $FAIL_COUNT"
  if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo "  RESULT: ALL CHECKS PASSED — evidence suitable for Phase 3 go/no-go record"
  else
    echo "  RESULT: $FAIL_COUNT CHECK(S) FAILED — review failures above before proceeding"
  fi
  echo ""
  echo "Evidence artifacts:"
  echo "  $SUMMARY"

} | tee "$SUMMARY"

echo ""
echo "Validation report written: $SUMMARY"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
