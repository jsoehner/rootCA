#!/usr/bin/env bash
# phase3-run-wildfly30-pilot.sh
# Start EJBCA on the isolated ejbca_pilot database for Phase 3 pilot testing.
# Stops any running EJBCA/WildFly instance first.
#
# Usage:
#   ./phase3/phase3-run-wildfly30-pilot.sh [--fail-fast]
#
# When finished with pilot testing, restore the production context:
#   ./phase3/phase3-run-wildfly30-prod.sh

set -euo pipefail

ROOT="${HOME}/rootCA"
PHASE3_DIR="$ROOT/phase3"
LOG_DIR="$PHASE3_DIR/logs"
WILDFLY_HOME="$ROOT/artifacts/appserver/wildfly-30.0.1.Final"
EJBCA_EAR="$ROOT/artifacts/ejbca/ejbca-ce-r9.3.7/dist/ejbca.ear"
DEPLOY_NAME="ejbca.ear"
LOG_FILE="$LOG_DIR/phase3-wildfly30-pilot.log"
PID_FILE="$PHASE3_DIR/phase3-wildfly30-pilot.pid"
JAVA21_HOME="/usr/lib/jvm/java-21-openjdk"
HEALTH_URL="http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth"
OCSP_URL="http://127.0.0.1:8080/ejbca/publicweb/status/ocsp"
FAIL_FAST="${PHASE3_FAIL_FAST:-0}"

if [[ "${1:-}" == "--fail-fast" ]]; then
  FAIL_FAST="1"
fi

# --- Load pilot credentials -------------------------------------------------
PILOT_CREDS_FILE="$PHASE3_DIR/.pilot-db-credentials"
if [[ ! -f "$PILOT_CREDS_FILE" ]]; then
  echo "ERROR: Pilot credentials file not found: $PILOT_CREDS_FILE"
  echo "       Run ./phase3/phase3-setup-pilot.sh first"
  exit 1
fi
# shellcheck source=/dev/null
source "$PILOT_CREDS_FILE"

# --- Pre-flight checks ------------------------------------------------------
MARIADB_MODULE_DIR="$WILDFLY_HOME/modules/org/mariadb/jdbc/main"
if [[ ! -f "$MARIADB_MODULE_DIR/mariadb-java-client.jar" ]]; then
  echo "ERROR: MariaDB WildFly module not installed: $MARIADB_MODULE_DIR"
  echo "       Run ./phase1/phase1-setup-mariadb.sh first"
  exit 1
fi

if ! mysql -u"${EJBCA_DB_USER}" -p"${EJBCA_DB_PASSWORD}" "${EJBCA_DB_NAME}" -e "SELECT 1" >/dev/null 2>&1; then
  echo "ERROR: Cannot reach pilot database '${EJBCA_DB_NAME}' as '${EJBCA_DB_USER}'"
  echo "       Ensure MariaDB is running and pilot DB exists:"
  echo "         sudo systemctl start mariadb"
  echo "         ./phase3/phase3-setup-pilot.sh"
  exit 1
fi

if [[ ! -d "$WILDFLY_HOME" ]]; then
  echo "ERROR: WildFly 30 home not found: $WILDFLY_HOME"
  exit 1
fi
if [[ ! -f "$EJBCA_EAR" ]]; then
  echo "ERROR: EJBCA 9 EAR not found: $EJBCA_EAR"
  echo "       Run ./phase1/phase1-build-ejbca9.sh first"
  exit 1
fi
if [[ ! -x "$JAVA21_HOME/bin/java" ]]; then
  echo "ERROR: Java 21 not found at $JAVA21_HOME"
  exit 1
fi

echo "[pilot] Starting EJBCA on PILOT database: ${EJBCA_DB_NAME}"

# --- Stop any running instance ----------------------------------------------
pkill -f 'wildfly-30.0.1.Final|jboss-modules.jar' 2>/dev/null || true
sleep 3
rm -f "$WILDFLY_HOME/standalone/deployments/ejbca.ear"*
rm -f "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME"*
rm -f "$WILDFLY_HOME/standalone/deployments/ejbca9.ear"*

# --- Start WildFly ----------------------------------------------------------
mkdir -p "$PHASE3_DIR" "$LOG_DIR"
cd "$WILDFLY_HOME"
JAVA_HOME="$JAVA21_HOME" PATH="$JAVA21_HOME/bin:$PATH" nohup ./bin/standalone.sh -b 127.0.0.1 > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 12

echo "[pilot] PID: $(cat "$PID_FILE")"
ps -fp "$(cat "$PID_FILE")" || true

# --- Wait for management endpoint -------------------------------------------
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command=':read-attribute(name=server-state)' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Remove stale managed deployments that can conflict with scanner-based deploys.
for stale in ejbca9.ear ejbca.ear; do
  if "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="/deployment=${stale}:read-resource" >/dev/null 2>&1; then
    echo "[pilot] Removing stale managed deployment: ${stale}"
    "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="/deployment=${stale}:undeploy" >/dev/null 2>&1 || true
    "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="/deployment=${stale}:remove" >/dev/null 2>&1 || true
  fi
done

# --- Configure datasource pointing at pilot DB ------------------------------
# Always remove stale datasource (may point at prod DB from a previous run)
if "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/data-source=EjbcaDS:read-resource' >/dev/null 2>&1; then
  echo "[pilot] Removing existing EjbcaDS"
  "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/data-source=EjbcaDS:remove'
fi

# Register MariaDB driver if not already present
if ! "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/jdbc-driver=mariadb:read-resource' >/dev/null 2>&1; then
  echo "[pilot] Registering MariaDB JDBC driver"
  "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/jdbc-driver=mariadb:add(driver-name=mariadb,driver-module-name=org.mariadb.jdbc,driver-class-name=org.mariadb.jdbc.Driver)'
fi

echo "[pilot] Configuring datasource java:/EjbcaDS → pilot database: ${EJBCA_DB_NAME}"
DS_CMD="data-source add --name=EjbcaDS --jndi-name=java:/EjbcaDS --driver-name=mariadb \
  --connection-url=jdbc:mariadb://localhost:3306/${EJBCA_DB_NAME} \
  --user-name=${EJBCA_DB_USER} --password=${EJBCA_DB_PASSWORD} \
  --use-ccm=true --enabled=true --min-pool-size=5 --max-pool-size=20 \
  --pool-prefill=true --validate-on-match=true --background-validation=false \
  --prepared-statements-cache-size=50 --share-prepared-statements=true \
  --transaction-isolation=TRANSACTION_READ_COMMITTED"
"$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="$DS_CMD"
"$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command=':reload'
sleep 10

# --- Deploy EAR -------------------------------------------------------------
cp "$EJBCA_EAR" "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME"
rm -f "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME.failed"
touch "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME.dodeploy"
sleep 8

# --- Health probes ----------------------------------------------------------
echo "[pilot] Probing endpoints:"
health_code="000"
ocsp_code="000"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  health_code=$(curl --max-time 5 -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || true)
  ocsp_code=$(curl --max-time 5 -s -o /dev/null -w '%{http_code}' "$OCSP_URL" || true)
  if [[ "$health_code" == "200" && "$ocsp_code" == "200" ]]; then
    break
  fi
  sleep 3
done

echo "[pilot] healthcheck_http=$health_code"
echo "[pilot] status_ocsp_http=$ocsp_code"

if [[ "$FAIL_FAST" == "1" && ( "$health_code" != "200" || "$ocsp_code" != "200" ) ]]; then
  echo "ERROR: Pilot readiness probes failed"
  exit 1
fi

echo ""
echo "[pilot] EJBCA is running on PILOT database: ${EJBCA_DB_NAME}"
echo "  Admin web : http://127.0.0.1:8080/ejbca/adminweb/"
echo "  Log file  : $LOG_FILE"
echo ""
echo "Next steps for Phase 3 pilot execution (CLI-based, no UI access required):"
echo "  1. Create and export pilot root CA (or reuse existing):"
echo "       ./phase3/phase3-step3-pilot-root.sh"
echo "  2. Create and export pilot subordinate CA:"
echo "       (subordinate CA creation script - TBD)"
echo "  3. Validate full chain (root + sub + end-entity):"
echo "       ./phase3/phase3-validate-pilot-certs.sh --root-cert ./phase3/pilot-root.pem \\"
echo "         --sub-cert ./phase3/pilot-sub.pem --label pilot-ecc-chain"
echo ""
echo "  To restore production context when done:"
echo "    ./phase3/phase3-run-wildfly30-prod.sh"

echo ""
echo "[pilot] Recent log markers:"
grep -E 'WFLYSRV0010|WFLYSRV0026|WFLYCTL0013|EjbcaDS|ejbca\.ear|ejbca9\.ear|ERROR|Exception' \
  "$LOG_FILE" | grep -v 'BouncyCastle is not loaded by an EJBCA classloader' | tail -30 || true

if grep -q 'BouncyCastle is not loaded by an EJBCA classloader' "$LOG_FILE"; then
  echo ""
  echo "[pilot] NOTE: Known non-fatal EJBCA warning detected:"
  echo "        'BouncyCastle is not loaded by an EJBCA classloader'"
  echo "        This warning is expected on this stack and is non-blocking when"
  echo "        deployment succeeded and health probes are 200."
fi
