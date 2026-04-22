#!/usr/bin/env bash
# phase3-step3-pilot-root.sh
# Guided helper for Phase 3 Step 3 (non-UI):
# - verifies pilot runtime readiness
# - exports pilot root certificate if CA already exists
# - creates pilot root CA via EJBCA CLI if missing
# - validates exported pilot root certificate
#
# Usage:
#   ./phase3/phase3-step3-pilot-root.sh [--root-cert <path>] [--label <name>] [--ca-name <name>]

set -euo pipefail

ROOT="${HOME}/rootCA"
PHASE3_DIR="$ROOT/phase3"
LOG_DIR="$PHASE3_DIR/logs"
EJBCA_HOME="$ROOT/artifacts/ejbca/ejbca-ce-r9.3.7"
VALIDATE_SCRIPT="$PHASE3_DIR/phase3-validate-pilot-certs.sh"
HEALTH_URL="http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth"
CLI_LOG="$LOG_DIR/phase3-step3-cli.log"
TOKEN_PASS_FILE="$PHASE3_DIR/.pilot-ca-token-password"

ROOT_CERT="$PHASE3_DIR/pilot-root.pem"
LABEL="pilot-ecc-root"
PILOT_CA_NAME="${PILOT_CA_NAME:-RootCAPilot-ECC384-SHA384}"
PILOT_CA_DN="${PILOT_CA_DN:-CN=JSIGROUP Pilot Root CA,O=JSIGROUP,C=CA}"
PILOT_CA_KEYSPEC="${PILOT_CA_KEYSPEC:-secp384r1}"
PILOT_CA_KEYTYPE="${PILOT_CA_KEYTYPE:-ECDSA}"
PILOT_CA_SIGALG="${PILOT_CA_SIGALG:-SHA384withECDSA}"
PILOT_CA_VALIDITY_DAYS="${PILOT_CA_VALIDITY_DAYS:-90}"

KNOWN_CA_NAMES=(
  "RootCAPilot-ECC384-SHA384"
  "RootCAPilot"
  "CAPilot"
)

find_candidate_root_cert() {
  local candidates=(
    "$PHASE3_DIR/pilot-root.pem"
    "$PHASE3_DIR/pilot-root.crt"
    "$PHASE3_DIR/pilot-root.cer"
    "$PHASE3_DIR/root-ca.pem"
    "$PHASE3_DIR/root-ca.crt"
    "$PHASE3_DIR/root-ca.cer"
    "$HOME/Downloads/pilot-root.pem"
    "$HOME/Downloads/pilot-root.crt"
    "$HOME/Downloads/pilot-root.cer"
  )

  local f
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
  done

  # Last-resort scan for PEM files that look like CA/root material.
  while IFS= read -r f; do
    if grep -q "BEGIN CERTIFICATE" "$f" 2>/dev/null; then
      echo "$f"
      return 0
    fi
  done < <(find "$PHASE3_DIR" -maxdepth 2 -type f -name '*.pem' 2>/dev/null)

  return 1
}

usage() {
  cat <<'EOF'
Usage:
  ./phase3/phase3-step3-pilot-root.sh [--root-cert <path>] [--label <name>] [--ca-name <name>]

Options:
  --root-cert  Path to exported pilot root certificate PEM
               (default: ~/rootCA/phase3/pilot-root.pem)
  --label      Validation artifact label (default: pilot-ecc-root)
  --ca-name    Pilot CA name to create/export if needed
               (default: RootCAPilot-ECC384-SHA384)
  --ca-dn      Pilot root CA subject DN
               (default: CN=JSIGROUP Pilot Root CA,O=JSIGROUP,C=CA)
  -h, --help   Show this help

Environment overrides:
  PILOT_CA_TOKEN_PASSWORD   Explicit token password (recommended in CI)
  PILOT_CA_KEYSPEC          Default: secp384r1
  PILOT_CA_KEYTYPE          Default: ECDSA
  PILOT_CA_SIGALG           Default: SHA384withECDSA
  PILOT_CA_VALIDITY_DAYS    Default: 90
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-cert) ROOT_CERT="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --ca-name) PILOT_CA_NAME="$2"; shift 2 ;;
    --ca-dn) PILOT_CA_DN="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "$LOG_DIR"

if [[ ! -x "$VALIDATE_SCRIPT" ]]; then
  echo "ERROR: Validation script missing or not executable: $VALIDATE_SCRIPT"
  exit 1
fi
if [[ ! -x "$EJBCA_HOME/bin/ejbca.sh" ]]; then
  echo "ERROR: EJBCA CLI not found: $EJBCA_HOME/bin/ejbca.sh"
  exit 1
fi

run_ejbca_cli() {
  (
    cd "$EJBCA_HOME"
    ./bin/ejbca.sh "$@"
  )
}

get_token_password() {
  if [[ -n "${PILOT_CA_TOKEN_PASSWORD:-}" ]]; then
    echo "$PILOT_CA_TOKEN_PASSWORD"
    return 0
  fi
  if [[ -f "$TOKEN_PASS_FILE" ]]; then
    cat "$TOKEN_PASS_FILE"
    return 0
  fi

  local generated
  generated="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"
  printf '%s\n' "$generated" > "$TOKEN_PASS_FILE"
  chmod 600 "$TOKEN_PASS_FILE"
  echo "$generated"
}

try_export_ca_cert() {
  local ca_name="$1"
  if run_ejbca_cli ca getcacert --caname "$ca_name" -f "$ROOT_CERT" >> "$CLI_LOG" 2>&1; then
    echo "[step3] Exported root cert from CA '$ca_name' to $ROOT_CERT"
    return 0
  fi
  return 1
}

echo "[step3] Checking pilot runtime readiness"
health_code="$(curl --max-time 5 -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || true)"
if [[ "$health_code" != "200" ]]; then
  echo "ERROR: Pilot EJBCA health endpoint is not ready (HTTP $health_code)"
  echo "       Start pilot runtime first: ./phase3/phase3-run-wildfly30-pilot.sh"
  exit 1
fi

echo "[step3] Pilot runtime is healthy (HTTP 200)"
echo "[step3] Running non-UI CA workflow (CLI only). Log: $CLI_LOG"
: > "$CLI_LOG"

if [[ ! -f "$ROOT_CERT" ]]; then
  if detected="$(find_candidate_root_cert)"; then
    echo "[step3] Auto-detected root certificate: $detected"
    cp -f "$detected" "$ROOT_CERT"
    echo "[step3] Copied detected certificate to: $ROOT_CERT"
  fi
fi

if [[ ! -f "$ROOT_CERT" ]]; then
  echo "[step3] No local root certificate file found. Trying CA export from known names."

  if ! try_export_ca_cert "$PILOT_CA_NAME"; then
    for name in "${KNOWN_CA_NAMES[@]}"; do
      if [[ "$name" == "$PILOT_CA_NAME" ]]; then
        continue
      fi
      if try_export_ca_cert "$name"; then
        PILOT_CA_NAME="$name"
        break
      fi
    done
  fi
fi

if [[ ! -f "$ROOT_CERT" ]]; then
  echo "[step3] Pilot CA not found by export. Attempting CA creation with CLI."
  TOKEN_PASS="$(get_token_password)"

  if run_ejbca_cli ca init \
      --caname "$PILOT_CA_NAME" \
      --dn "$PILOT_CA_DN" \
      --tokenType soft \
      --tokenPass "$TOKEN_PASS" \
      --keyspec "$PILOT_CA_KEYSPEC" \
      --keytype "$PILOT_CA_KEYTYPE" \
      -v "$PILOT_CA_VALIDITY_DAYS" \
      --policy null \
      -s "$PILOT_CA_SIGALG" >> "$CLI_LOG" 2>&1; then
    echo "[step3] Created pilot CA: $PILOT_CA_NAME"
  else
    echo "[step3] CA creation command returned non-zero; retrying export in case CA already exists."
  fi

  if ! try_export_ca_cert "$PILOT_CA_NAME"; then
    echo "ERROR: Could not export pilot root certificate to: $ROOT_CERT"
    echo "       Checked/used CA name: $PILOT_CA_NAME"
    echo "       Inspect CLI log: $CLI_LOG"
    echo "       You can list known CAs with:"
    echo "         (cd $EJBCA_HOME && ./bin/ejbca.sh ca listcas)"
    exit 1
  fi
fi

echo "[step3] Validating pilot root certificate"
"$VALIDATE_SCRIPT" --root-cert "$ROOT_CERT" --label "$LABEL"

echo ""
echo "[step3] Completed. Root certificate validation passed."
echo "[step3] Root cert file: $ROOT_CERT"
echo "[step3] CA name used   : $PILOT_CA_NAME"
echo "[step3] Next: issue and export pilot subordinate cert, then run:"
echo "  ./phase3/phase3-validate-pilot-certs.sh --root-cert ./phase3/pilot-root.pem --sub-cert ./phase3/pilot-sub.pem --label pilot-ecc-chain"
