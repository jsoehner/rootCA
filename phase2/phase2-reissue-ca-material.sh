#!/usr/bin/env bash
# phase2-reissue-ca-material.sh
# Regenerate root and subordinate CA material with corrected organization/country values.
# Designed for CLI-only operation on the active EJBCA runtime.

set -euo pipefail

ROOT_DIR="${HOME}/rootCA"
PHASE2_DIR="$ROOT_DIR/phase2"
LOG_DIR="$PHASE2_DIR/logs"
EJBCA_HOME="$ROOT_DIR/artifacts/ejbca/ejbca-ce-r9.3.7"
VALIDATE_SCRIPT="$PHASE2_DIR/phase2-validate-certs.sh"
PROFILES_DIR="$PHASE2_DIR/profiles"
HEALTH_URL="http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth"

ROOT_CA_NAME="${ROOT_CA_NAME:-JSIGROUP-RootCA}"
SUB_CA_NAME="${SUB_CA_NAME:-JSIGROUP-SubCA}"
ROOT_DN="${ROOT_DN:-CN=JSIGROUP Root CA,O=JSIGROUP,C=CA}"
SUB_DN="${SUB_DN:-CN=JSIGROUP Intermediate CA - AD CS,OU=Certificate Authority,O=JSIGROUP,C=CA}"
ROOT_PROFILE="${ROOT_PROFILE:-RootCAProd-ECC384-SHA384}"
SUB_PROFILE="${SUB_PROFILE:-SubordCAProd-ECC384-SHA384}"
ROOT_VALIDITY_DAYS="${ROOT_VALIDITY_DAYS:-3650}"
SUB_VALIDITY_DAYS="${SUB_VALIDITY_DAYS:-1825}"
ROOT_CERT_OUT="${ROOT_CERT_OUT:-$PHASE2_DIR/root-ca.pem}"
SUB_CERT_OUT="${SUB_CERT_OUT:-$PHASE2_DIR/sub-ca.pem}"
LABEL="${LABEL:-reissue-jsigroup-ca}"
FORCE="0"

usage() {
  cat <<'EOF'
Usage:
  ./phase2/phase2-reissue-ca-material.sh [options]

Options:
  --root-ca-name NAME     Root CA name in EJBCA (default: JSIGROUP-RootCA)
  --sub-ca-name NAME      Subordinate CA name in EJBCA (default: JSIGROUP-SubCA)
  --root-dn DN            Root subject DN (default: CN=JSIGROUP Root CA,O=JSIGROUP,C=CA)
  --sub-dn DN             Subordinate subject DN (default: CN=JSIGROUP Intermediate CA - AD CS,OU=Certificate Authority,O=JSIGROUP,C=CA)
  --root-profile NAME     Root certificate profile (default: RootCAProd-ECC384-SHA384)
  --sub-profile NAME      Subordinate certificate profile (default: SubordCAProd-ECC384-SHA384)
  --root-validity DAYS    Root validity in days (default: 3650)
  --sub-validity DAYS     Subordinate validity in days (default: 1825)
  --root-cert-out PATH    Output PEM path for root cert (default: ./phase2/root-ca.pem)
  --sub-cert-out PATH     Output PEM path for subordinate cert (default: ./phase2/sub-ca.pem)
  --label NAME            Label for validation report (default: reissue-jsigroup-ca)
  --force                 Allow using CA names that already exist (exports existing material)
  -h, --help              Show help

Notes:
  - This script imports certificate profiles from ./phase2/profiles before CA creation.
  - This script creates new software-token CAs unless a CA with the same name already exists.
  - If a CA name exists and --force is not set, the script exits to prevent accidental reuse.
  - Run production context first if needed: ./phase3/phase3-run-wildfly30-prod.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-ca-name) ROOT_CA_NAME="$2"; shift 2 ;;
    --sub-ca-name) SUB_CA_NAME="$2"; shift 2 ;;
    --root-dn) ROOT_DN="$2"; shift 2 ;;
    --sub-dn) SUB_DN="$2"; shift 2 ;;
    --root-profile) ROOT_PROFILE="$2"; shift 2 ;;
    --sub-profile) SUB_PROFILE="$2"; shift 2 ;;
    --root-validity) ROOT_VALIDITY_DAYS="$2"; shift 2 ;;
    --sub-validity) SUB_VALIDITY_DAYS="$2"; shift 2 ;;
    --root-cert-out) ROOT_CERT_OUT="$2"; shift 2 ;;
    --sub-cert-out) SUB_CERT_OUT="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --force) FORCE="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "$LOG_DIR"
TS="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_LOG="$LOG_DIR/phase2-reissue-$TS.log"

run_ejbca_cli() {
  (
    cd "$EJBCA_HOME"
    ./bin/ejbca.sh "$@"
  )
}

require_health() {
  local code
  code="$(curl --max-time 5 -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || true)"
  if [[ "$code" != "200" ]]; then
    echo "ERROR: EJBCA health endpoint is not ready (HTTP $code)" | tee -a "$RUN_LOG"
    echo "       Start runtime first (typically production context): ./phase3/phase3-run-wildfly30-prod.sh" | tee -a "$RUN_LOG"
    exit 1
  fi
}

ca_id_by_name() {
  local target="$1"
  # Force non-interactive execution and cap runtime to avoid hangs.
  timeout 30 "$EJBCA_HOME/bin/ejbca.sh" ca listcas </dev/null | awk -v target="$target" '
    /^CA Name: / {name = substr($0, 10)}
    /^ Id: / {if (name == target) {print $2; exit 0}}
  '
}

echo "[reissue] Starting reissue workflow" | tee "$RUN_LOG"
echo "[reissue] Root CA name : $ROOT_CA_NAME" | tee -a "$RUN_LOG"
echo "[reissue] Root DN      : $ROOT_DN" | tee -a "$RUN_LOG"
echo "[reissue] Sub CA name  : $SUB_CA_NAME" | tee -a "$RUN_LOG"
echo "[reissue] Sub DN       : $SUB_DN" | tee -a "$RUN_LOG"

if [[ ! -x "$EJBCA_HOME/bin/ejbca.sh" ]]; then
  echo "ERROR: EJBCA CLI not found at $EJBCA_HOME/bin/ejbca.sh" | tee -a "$RUN_LOG"
  exit 1
fi
if [[ ! -x "$VALIDATE_SCRIPT" ]]; then
  echo "ERROR: Validation script missing: $VALIDATE_SCRIPT" | tee -a "$RUN_LOG"
  exit 1
fi
if [[ ! -d "$PROFILES_DIR" ]]; then
  echo "ERROR: Profiles directory missing: $PROFILES_DIR" | tee -a "$RUN_LOG"
  exit 1
fi

require_health

echo "[reissue] Importing certificate profiles from $PROFILES_DIR" | tee -a "$RUN_LOG"
if ! run_ejbca_cli ca importprofiles -d "$PROFILES_DIR" >> "$RUN_LOG" 2>&1; then
  if grep -q "already exist in database" "$RUN_LOG"; then
    echo "[reissue] Profile import reported existing profiles; continuing" | tee -a "$RUN_LOG"
  else
    echo "ERROR: Failed to import certificate profiles" | tee -a "$RUN_LOG"
    exit 1
  fi
fi

ROOT_ID_EXISTING="$(ca_id_by_name "$ROOT_CA_NAME" || true)"
SUB_ID_EXISTING="$(ca_id_by_name "$SUB_CA_NAME" || true)"

if [[ "$FORCE" != "1" ]]; then
  if [[ -n "$ROOT_ID_EXISTING" ]]; then
    echo "ERROR: Root CA '$ROOT_CA_NAME' already exists (ID $ROOT_ID_EXISTING)." | tee -a "$RUN_LOG"
    echo "       Use a new --root-ca-name or pass --force to reuse/export existing material." | tee -a "$RUN_LOG"
    exit 1
  fi
  if [[ -n "$SUB_ID_EXISTING" ]]; then
    echo "ERROR: Subordinate CA '$SUB_CA_NAME' already exists (ID $SUB_ID_EXISTING)." | tee -a "$RUN_LOG"
    echo "       Use a new --sub-ca-name or pass --force to reuse/export existing material." | tee -a "$RUN_LOG"
    exit 1
  fi
fi

# Use hex output to avoid pipefail issues from head/tr pipelines.
TOKEN_PASS_ROOT="$(openssl rand -hex 12)"
TOKEN_PASS_SUB="$(openssl rand -hex 12)"

if [[ -z "$ROOT_ID_EXISTING" ]]; then
  echo "[reissue] Creating root CA '$ROOT_CA_NAME'" | tee -a "$RUN_LOG"
  run_ejbca_cli ca init \
    --caname "$ROOT_CA_NAME" \
    --dn "$ROOT_DN" \
    --tokenType soft \
    --tokenPass "$TOKEN_PASS_ROOT" \
    --keyspec secp384r1 \
    --keytype ECDSA \
    -v "$ROOT_VALIDITY_DAYS" \
    --policy null \
    -s SHA384withECDSA \
    -certprofile "$ROOT_PROFILE" >> "$RUN_LOG" 2>&1
fi

ROOT_ID="$(ca_id_by_name "$ROOT_CA_NAME" || true)"
if [[ -z "$ROOT_ID" ]]; then
  echo "ERROR: Could not resolve root CA ID for '$ROOT_CA_NAME'" | tee -a "$RUN_LOG"
  exit 1
fi

echo "[reissue] Root CA ID: $ROOT_ID" | tee -a "$RUN_LOG"

if [[ -z "$SUB_ID_EXISTING" ]]; then
  echo "[reissue] Creating subordinate CA '$SUB_CA_NAME' signed by root ID $ROOT_ID" | tee -a "$RUN_LOG"
  run_ejbca_cli ca init \
    --caname "$SUB_CA_NAME" \
    --dn "$SUB_DN" \
    --signedby "$ROOT_ID" \
    --tokenType soft \
    --tokenPass "$TOKEN_PASS_SUB" \
    --keyspec secp384r1 \
    --keytype ECDSA \
    -v "$SUB_VALIDITY_DAYS" \
    --policy null \
    -s SHA384withECDSA \
    -certprofile "$SUB_PROFILE" >> "$RUN_LOG" 2>&1
fi

echo "[reissue] Exporting CA certificates" | tee -a "$RUN_LOG"
run_ejbca_cli ca getcacert --caname "$ROOT_CA_NAME" -f "$ROOT_CERT_OUT" >> "$RUN_LOG" 2>&1
run_ejbca_cli ca getcacert --caname "$SUB_CA_NAME" -f "$SUB_CERT_OUT" >> "$RUN_LOG" 2>&1

echo "[reissue] Running certificate validation" | tee -a "$RUN_LOG"
"$VALIDATE_SCRIPT" --root-cert "$ROOT_CERT_OUT" --sub-cert "$SUB_CERT_OUT" --label "$LABEL" | tee -a "$RUN_LOG"

echo "[reissue] Completed successfully" | tee -a "$RUN_LOG"
echo "[reissue] Root cert : $ROOT_CERT_OUT" | tee -a "$RUN_LOG"
echo "[reissue] Sub cert  : $SUB_CERT_OUT" | tee -a "$RUN_LOG"
echo "[reissue] Run log   : $RUN_LOG" | tee -a "$RUN_LOG"
