#!/usr/bin/env bash
# phase3-sign-adcs-subordinate-csr.sh
#
# Sign a Windows AD CS pilot subordinate CA CSR using the EJBCA pilot root CA.
#
# The script handles the full EJBCA CLI workflow without any UI interaction:
#   1. Normalises Windows-format CSR headers to standard PKCS#10 PEM.
#   2. Verifies EJBCA runtime health and required CA/profile presence.
#   3. Registers a one-time end entity in EJBCA (auto-deleted on conflict).
#   4. Issues the subordinate CA certificate via `createcert`.
#   5. Exports PEM and DER formats suitable for Linux storage and Windows import.
#   6. Validates the issued certificate with openssl.
#
# Usage:
#   ./phase3/phase3-sign-adcs-subordinate-csr.sh --csr <CSR_FILE> [options]
#
# Options:
#   --csr PATH          Path to Windows .req or standard PEM CSR file (required)
#   --out PATH          Output PEM path (default: phase3/pilot-sub-from-adcs.pem)
#   --ca-name NAME      Issuing CA name (default: JSIGROUP-Pilot-RootCA)
#   --cert-profile NAME Certificate profile (default: SubordCAPilot-ECC384-SHA384)
#   --ee-profile NAME   End entity profile to use in EJBCA
#                       (default: ADCS2025_SubCA_EE_Profile)
#   --dn DN             Subject DN for issued cert
#                       (default: CN=JSIGROUP Intermediate CA - AD CS - PILOT,
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
OUT_PEM="$SCRIPT_DIR/pilot-sub-from-adcs.pem"
CA_NAME="JSIGROUP-Pilot-RootCA"
CERT_PROFILE="SubordCAPilot-ECC384-SHA384"
EE_PROFILE="ADCS2025_SubCA_EE_Profile"
SUBJECT_DN="CN=JSIGROUP Intermediate CA - AD CS - PILOT"
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

log()  { echo "[sign-csr] $*"; }
die()  { echo "[sign-csr] ERROR: $*" >&2; exit 1; }

# run_ejbca [--timeout SECONDS] <ejbca-command> [args...]
# Timeout defaults to 60s. Wraps timeout inside the subshell so it works
# without needing 'export -f'.
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

[[ -n "$CSR_FILE" ]] || die "--csr is required. Example: --csr ~/JSI-Root.jsigroup.local_jsigroup-JSI-ROOT-CA-1.req"

# Resolve paths
CSR_FILE="$(realpath "$CSR_FILE")"
OUT_PEM="$(realpath "$OUT_PEM")"
OUT_DER="${OUT_PEM%.pem}.cer"

[[ -f "$CSR_FILE" ]] || die "CSR file not found: $CSR_FILE"
[[ -x "$EJBCA_HOME/bin/ejbca.sh" ]] || die "EJBCA CLI not found at: $EJBCA_HOME/bin/ejbca.sh"

mkdir -p "$LOG_DIR"
TS="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_LOG="$LOG_DIR/phase3-sign-csr-$TS.log"

# Auto-generate end entity username if not provided
if [[ -z "$EE_USERNAME" ]]; then
  EE_USERNAME="jsi-pilot-adcs-sub-$TS"
fi

# Temporary PEM-normalised CSR
NORM_CSR="$(mktemp /tmp/phase3-csr-normalised-XXXXXX.pem)"
trap 'rm -f "$NORM_CSR"' EXIT

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
{
  echo "=================================================================="
  echo "  Phase 3 — Sign AD CS Subordinate CSR"
  echo "  Timestamp : $TS"
  echo "  CSR       : $CSR_FILE"
  echo "  Output    : $OUT_PEM"
  echo "  Out (DER) : $OUT_DER"
  echo "  Issuing CA: $CA_NAME"
  echo "  Profile   : $CERT_PROFILE"
  echo "  EE profile: $EE_PROFILE"
  echo "  Subject DN: $SUBJECT_DN"
  echo "  EE User   : $EE_USERNAME"
  echo "=================================================================="
} | tee "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 1 — Normalise CSR to standard PKCS#10 PEM
# ---------------------------------------------------------------------------
log "Step 1: Normalising CSR header..."
# Windows certreq uses 'BEGIN NEW CERTIFICATE REQUEST'; openssl/EJBCA expect
# 'BEGIN CERTIFICATE REQUEST'. Convert if needed, otherwise pass through as-is.
sed 's/BEGIN NEW CERTIFICATE REQUEST/BEGIN CERTIFICATE REQUEST/g;
     s/END NEW CERTIFICATE REQUEST/END CERTIFICATE REQUEST/g' \
  "$CSR_FILE" > "$NORM_CSR"

# Verify the result is valid PKCS#10 before proceeding
if ! openssl req -in "$NORM_CSR" -noout 2>/dev/null; then
  die "CSR failed openssl validation after header normalisation. Check that '$CSR_FILE' is a valid PKCS#10 request."
fi

# EJBCA createcert enforces proof-of-possession (PoPO). If the CSR self-signature
# does not verify, issuance will fail later with a generic PoPO error.
if ! openssl req -in "$NORM_CSR" -verify -noout >/dev/null 2>&1; then
  die "CSR self-signature verification failed (PoPO invalid). Regenerate the CSR on AD CS and rerun."
fi

CSR_SUBJECT="$(openssl req -in "$NORM_CSR" -noout -subject 2>/dev/null | sed 's/subject=//')"
log "  CSR subject  : $CSR_SUBJECT"
log "  Issuing DN   : $SUBJECT_DN"
log "  CSR validated OK." | tee -a "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 2 — Verify EJBCA runtime health
# ---------------------------------------------------------------------------
log "Step 2: Checking EJBCA runtime health..."
HTTP_CODE="$(curl --max-time 10 -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || true)"
if [[ "$HTTP_CODE" != "200" ]]; then
  die "EJBCA health endpoint returned HTTP $HTTP_CODE (expected 200). Start the runtime first."
fi
log "  Health endpoint: HTTP $HTTP_CODE — OK" | tee -a "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 3 — Verify issuing CA is present
# ---------------------------------------------------------------------------
log "Step 3: Verifying issuing CA '$CA_NAME' is present..."
CA_LIST="$(run_ejbca --timeout 25 ca listcas 2>&1)"
if ! echo "$CA_LIST" | grep -q "CA Name: $CA_NAME"; then
  echo "$CA_LIST" | grep "CA Name:" | tee -a "$RUN_LOG"
  die "CA '$CA_NAME' is not present in this EJBCA instance."
fi
log "  CA '$CA_NAME' confirmed present." | tee -a "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 4 — Verify certificate profile is present
# ---------------------------------------------------------------------------
log "Step 4: Verifying certificate profile '$CERT_PROFILE' is present..."
PROFILE_TMPDIR="$(mktemp -d /tmp/phase3-profiles-XXXXXX)"
trap 'rm -rf "$PROFILE_TMPDIR"; rm -f "$NORM_CSR"' EXIT
run_ejbca --timeout 30 ca exportprofiles -d "$PROFILE_TMPDIR" >/dev/null 2>&1 || true
if ! ls "$PROFILE_TMPDIR/" | grep -q "$CERT_PROFILE"; then
  ls "$PROFILE_TMPDIR/" | tee -a "$RUN_LOG"
  die "Certificate profile '$CERT_PROFILE' is not present. Import it from phase2/profiles/ first."
fi
log "  Profile '$CERT_PROFILE' confirmed present." | tee -a "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 5 — Generate end entity password
# ---------------------------------------------------------------------------
# Disable pipefail locally: head closing the pipe causes tr to receive SIGPIPE (141)
# which propagates as a pipeline failure under set -o pipefail.
EE_PASSWORD="$(set +o pipefail; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
log "Step 5: Registering end entity '$EE_USERNAME'..."

# Remove conflicting end entity from a prior run, if any
if run_ejbca --timeout 20 ra findendentity --username "$EE_USERNAME" >/dev/null 2>&1; then
  log "  Found existing end entity with same username — removing before re-registering."
  run_ejbca --timeout 20 ra delendentity --username "$EE_USERNAME" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Step 6 — Register end entity in EJBCA
# ---------------------------------------------------------------------------
ADDENTITY_OUTPUT="$LOG_DIR/phase3-sign-csr-addendentity-$TS.log"
if ! run_ejbca --timeout 30 ra addendentity \
  --username     "$EE_USERNAME" \
  --password     "$EE_PASSWORD" \
  --dn           "$SUBJECT_DN" \
  --caname       "$CA_NAME" \
  --type         1 \
  --token        USERGENERATED \
  --eeprofile    "$EE_PROFILE" \
  --certprofile  "$CERT_PROFILE" \
  >"$ADDENTITY_OUTPUT" 2>&1; then
  cat "$ADDENTITY_OUTPUT" | tee -a "$RUN_LOG"
  if grep -q "Couldn't find certificate profile" "$ADDENTITY_OUTPUT"; then
    die "End entity profile '$EE_PROFILE' does not allow certificate profile '$CERT_PROFILE'. Create/import an EE profile that explicitly allows '$CERT_PROFILE', then rerun with --ee-profile <name>."
  fi
  die "Failed to create end entity. See: $ADDENTITY_OUTPUT"
fi
cat "$ADDENTITY_OUTPUT" | tee -a "$RUN_LOG"

log "  End entity registered." | tee -a "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 7 — Issue certificate from CSR
# ---------------------------------------------------------------------------
log "Step 7: Issuing certificate from CSR..."
run_ejbca --timeout 90 createcert \
  --username "$EE_USERNAME" \
  --password "$EE_PASSWORD" \
  -c         "$NORM_CSR" \
  -f         "$OUT_PEM" \
  2>&1 | tee -a "$RUN_LOG"

[[ -s "$OUT_PEM" ]] || die "createcert did not produce output file: $OUT_PEM"
log "  Certificate written to: $OUT_PEM" | tee -a "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 8 — Export DER (Windows import format)
# ---------------------------------------------------------------------------
log "Step 8: Exporting DER copy for Windows import..."
openssl x509 -in "$OUT_PEM" -outform der -out "$OUT_DER"
log "  DER certificate written to: $OUT_DER" | tee -a "$RUN_LOG"

# ---------------------------------------------------------------------------
# Step 9 — Validate issued certificate
# ---------------------------------------------------------------------------
log "Step 9: Validating issued certificate..." | tee -a "$RUN_LOG"

PILOT_ROOT_PEM="$SCRIPT_DIR/pilot-root.pem"
PASS=0
FAIL=0

check() {
  local desc="$1" result="$2" expected="$3"
  if echo "$result" | grep -qi "$expected"; then
    log "  [PASS] $desc"
    (( PASS++ ))
  else
    log "  [FAIL] $desc  — expected: $expected  got: $result"
    (( FAIL++ ))
  fi
}

CERT_SUBJECT="$(openssl x509 -in "$OUT_PEM" -noout -subject 2>/dev/null)"
CERT_ISSUER="$(openssl x509 -in "$OUT_PEM" -noout -issuer  2>/dev/null)"
CERT_DATES="$(openssl x509 -in "$OUT_PEM" -noout -dates   2>/dev/null)"
CERT_TEXT="$(openssl x509 -in "$OUT_PEM" -noout -text     2>/dev/null)"
CERT_FP="$(openssl x509 -in "$OUT_PEM" -noout -fingerprint -sha256 2>/dev/null)"

check "Subject contains JSIGROUP Intermediate CA"        "$CERT_SUBJECT" "JSIGROUP Intermediate CA"
# Only enforce O/C checks if they were requested in --dn for this run.
if [[ "$SUBJECT_DN" == *"O=JSIGROUP"* ]]; then
  check "Subject contains O=JSIGROUP"                    "$CERT_SUBJECT" "O=JSIGROUP"
fi
if [[ "$SUBJECT_DN" == *"C=CA"* ]]; then
  check "Subject contains C=CA"                          "$CERT_SUBJECT" "C=CA"
fi
check "Issuer contains JSIGROUP Pilot Root CA"           "$CERT_ISSUER"  "JSIGROUP Pilot Root CA"
check "Key usage contains Certificate Sign"              "$CERT_TEXT"    "Certificate Sign"
check "Key usage contains CRL Sign"                      "$CERT_TEXT"    "CRL Sign"
check "Basic Constraints: CA:TRUE"                       "$CERT_TEXT"    "CA:TRUE"

if [[ -f "$PILOT_ROOT_PEM" ]]; then
  CHAIN_VERIFY="$(openssl verify -CAfile "$PILOT_ROOT_PEM" "$OUT_PEM" 2>&1)"
  check "Chain verification (pilot root → sub)"  "$CHAIN_VERIFY" "OK"
else
  log "  [SKIP] Chain verification — pilot-root.pem not found at $PILOT_ROOT_PEM"
fi

{
  echo ""
  echo "=================================================================="
  echo "  Validation Summary"
  echo "  PASS: $PASS   FAIL: $FAIL"
  echo ""
  echo "  Subject   : $CERT_SUBJECT"
  echo "  Issuer    : $CERT_ISSUER"
  echo "  $CERT_DATES"
  echo "  $CERT_FP"
  echo "=================================================================="
  echo ""
  echo "  Output files:"
  echo "    PEM (Linux/EJBCA): $OUT_PEM"
  echo "    DER (Windows):     $OUT_DER"
  echo ""
  echo "  Next step (Test 2 in Phase-3-Test-Execution-Worksheet.md):"
  echo "    Copy $OUT_DER to the Windows AD CS host and complete the CA setup."
  echo "=================================================================="
} | tee -a "$RUN_LOG"

if (( FAIL > 0 )); then
  die "$FAIL validation check(s) failed. Review log: $RUN_LOG"
fi

log "All validation checks passed. Log: $RUN_LOG"
