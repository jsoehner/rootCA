#!/usr/bin/env bash
# phase5-sign-adcs-subordinate-csr.sh
#
# Sign a Windows AD CS PRODUCTION subordinate CA CSR using the EJBCA production root CA.
#
# Usage:
#   ./phase5/phase5-sign-adcs-subordinate-csr.sh --csr <CSR_FILE> [options]
#
# Options:
#   --csr PATH          Path to Windows .req or standard PEM CSR file (required)
#   --out PATH          Output PEM path (default: phase5/subordinate-ca.pem)
#   --ca-name NAME      Issuing CA name (default: JSIGROUP-ProductionRootCA)
#   --cert-profile NAME Certificate profile (default: SubordCAProd-ECC384-SHA384)
#   --ee-profile NAME   End entity profile to use in EJBCA
#                       (default: ADCS2025_SubCA_EE_Profile)
#   --dn DN             Subject DN for issued cert
#                       (default: CN=JSIGROUP Intermediate CA - AD CS,
#                                 OU=Certificate Authority,O=JSIGROUP,C=CA)
#   --username NAME     EJBCA end entity username (default: auto-generated)
#   -h, --help          Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EJBCA_HOME="$ROOT_DIR/artifacts/ejbca/ejbca-ce-r9.3.7"
LOG_DIR="$SCRIPT_DIR/logs"
HEALTH_URL="http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth"

CSR_FILE=""
OUT_PEM="$SCRIPT_DIR/prod-sub-from-adcs.pem"
CA_NAME="JSIGROUP-ProductionRootCA"
CERT_PROFILE="SubordCAProd-ECC384-SHA384"
EE_PROFILE="ADCS2025_Prod_SubCA_EE_Profile"
SUBJECT_DN="CN=JSIGROUP Intermediate CA - AD CS,OU=Certificate Authority,O=JSIGROUP,C=CA"
EE_USERNAME=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  sed -n '/^# Usage:/,/^[^#]/{ s/^# //; /^[^#]/d; p }' "${BASH_SOURCE[0]}"
  echo ""
  echo "Options:"
  sed -n '/^# Options:/,/^[^#]/{ s/^# //; /^[^#]/d; p }' "${BASH_SOURCE[0]}"
}

log()  { echo "[sign-csr-prod] $*"; }
die()  { echo "[sign-csr-prod] ERROR: $*" >&2; exit 1; }

run_ejbca() {
  local t=60
  if [[ "${1:-}" == "--timeout" ]]; then t="$2"; shift 2; fi
  (
    cd "$EJBCA_HOME"
    timeout "$t" ./bin/ejbca.sh "$@"
  )
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --csr)          CSR_FILE="$2";        shift 2 ;;
    --out)          OUT_PEM="$2";         shift 2 ;;
    --ca-name)      CA_NAME="$2";         shift 2 ;;
    --cert-profile) CERT_PROFILE="$2";    shift 2 ;;
    --ee-profile)   EE_PROFILE="$2";      shift 2 ;;
    --dn)           SUBJECT_DN="$2";      shift 2 ;;
    --username)     EE_USERNAME="$2";     shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$CSR_FILE" ]] || die "--csr is required."

# Resolve paths
CSR_FILE="$(realpath "$CSR_FILE")"
OUT_PEM="$(realpath "$OUT_PEM")"
OUT_DER="${OUT_PEM%.pem}.cer"

[[ -f "$CSR_FILE" ]] || die "CSR file not found: $CSR_FILE"
[[ -x "$EJBCA_HOME/bin/ejbca.sh" ]] || die "EJBCA CLI not found at: $EJBCA_HOME/bin/ejbca.sh"

mkdir -p "$LOG_DIR"
TS="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_LOG="$LOG_DIR/phase5-sign-csr-$TS.log"

if [[ -z "$EE_USERNAME" ]]; then
  EE_USERNAME="jsi-prod-adcs-sub-$TS"
fi

NORM_CSR="$(mktemp /tmp/phase5-csr-normalised-XXXXXX.pem)"
trap 'rm -f "$NORM_CSR"' EXIT

# ---------------------------------------------------------------------------
# Step 1 — Normalise CSR
# ---------------------------------------------------------------------------
log "Step 1: Normalising CSR header..."
sed 's/BEGIN NEW CERTIFICATE REQUEST/BEGIN CERTIFICATE REQUEST/g;
     s/END NEW CERTIFICATE REQUEST/END CERTIFICATE REQUEST/g' \
  "$CSR_FILE" > "$NORM_CSR"

if ! openssl req -in "$NORM_CSR" -noout 2>/dev/null; then
  die "CSR failed openssl validation. Check that '$CSR_FILE' is a valid PKCS#10 request."
fi

# ---------------------------------------------------------------------------
# Step 2 — Verify Health
# ---------------------------------------------------------------------------
log "Step 2: Checking EJBCA runtime health..."
HTTP_CODE="$(curl --max-time 10 -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || true)"
if [[ "$HTTP_CODE" != "200" ]]; then
  die "EJBCA health endpoint returned HTTP $HTTP_CODE. Start the runtime first."
fi

# ---------------------------------------------------------------------------
# Step 3 — Verify CA
# ---------------------------------------------------------------------------
log "Step 3: Verifying issuing CA '$CA_NAME'..."
CA_LIST="$(run_ejbca --timeout 25 ca listcas 2>&1)"
if ! echo "$CA_LIST" | grep -q "CA Name: $CA_NAME"; then
  die "CA '$CA_NAME' is not present."
fi

# ---------------------------------------------------------------------------
# Step 4 — Verify Profile (Skipped export, assume present if Phase 4 succeeded)
# ---------------------------------------------------------------------------
log "Step 4: Using certificate profile '$CERT_PROFILE'..."

# ---------------------------------------------------------------------------
# Step 5 — Register End Entity
# ---------------------------------------------------------------------------
EE_PASSWORD="$(set +o pipefail; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
log "Step 5: Registering end entity '$EE_USERNAME'..."

if run_ejbca --timeout 20 ra findendentity --username "$EE_USERNAME" >/dev/null 2>&1; then
  run_ejbca --timeout 20 ra delendentity --username "$EE_USERNAME" >/dev/null 2>&1 || true
fi

if ! run_ejbca --timeout 30 ra addendentity \
  --username     "$EE_USERNAME" \
  --password     "$EE_PASSWORD" \
  --dn           "$SUBJECT_DN" \
  --caname       "$CA_NAME" \
  --type         1 \
  --token        USERGENERATED \
  --eeprofile    "$EE_PROFILE" \
  --certprofile  "$CERT_PROFILE" \
  >/dev/null 2>&1; then
  die "Failed to create end entity. Check profile mappings."
fi

# ---------------------------------------------------------------------------
# Step 6 — Issue Certificate
# ---------------------------------------------------------------------------
log "Step 6: Issuing certificate from CSR..."
run_ejbca --timeout 90 createcert \
  --username "$EE_USERNAME" \
  --password "$EE_PASSWORD" \
  -c         "$NORM_CSR" \
  -f         "$OUT_PEM" \
  2>&1 | tee -a "$RUN_LOG"

[[ -s "$OUT_PEM" ]] || die "createcert did not produce output file."

# ---------------------------------------------------------------------------
# Step 7 — Export DER
# ---------------------------------------------------------------------------
log "Step 7: Exporting DER copy..."
openssl x509 -in "$OUT_PEM" -outform der -out "$OUT_DER"

# ---------------------------------------------------------------------------
# Step 8 — Final Validation
# ---------------------------------------------------------------------------
log "Step 8: Validating issued certificate..."
openssl x509 -in "$OUT_PEM" -text -noout | grep -E "Subject:|Issuer:|CA:TRUE|Certificate Sign" | tee -a "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 9 — Update and Export CRL
# ---------------------------------------------------------------------------
log "Step 9: Generating and exporting fresh CRL for '$CA_NAME'..."
run_ejbca --timeout 60 ca createcrl "$CA_NAME" >/dev/null 2>&1 || log "WARNING: CRL generation reported an issue."

CRL_OUT="$ROOT_DIR/artifacts/root.crl"
run_ejbca --timeout 60 ca getcrl --caname "$CA_NAME" -f "$CRL_OUT" >/dev/null 2>&1 || die "Failed to export CRL to $CRL_OUT"

log "SUCCESS: Production Subordinate CA issued at: $OUT_DER"
log "SUCCESS: CRL updated and exported to: $CRL_OUT"
log "NOTE: Please copy '$OUT_DER', '$ROOT_DIR/phase4/root-ca-production.cer', and '$CRL_OUT' to the Windows host."
log "      Rename 'root-ca-production.cer' to 'root-ca-prod-ecc384.cer' if required by the installation script."
