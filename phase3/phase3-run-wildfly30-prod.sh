#!/usr/bin/env bash
# phase3-run-wildfly30-prod.sh
# Restore EJBCA to the production database after Phase 3 pilot testing.
# Stops any running pilot instance and starts on the production ejbca database.
#
# Usage:
#   ./phase3/phase3-run-wildfly30-prod.sh [--fail-fast]

set -euo pipefail

ROOT="${HOME}/rootCA"
PHASE1_DIR="$ROOT/phase1"
PHASE3_DIR="$ROOT/phase3"
LOG_DIR="$PHASE1_DIR/logs"
WILDFLY_HOME="$ROOT/artifacts/appserver/wildfly-30.0.1.Final"
EJBCA_EAR="$ROOT/artifacts/ejbca/ejbca-ce-r9.3.7/dist/ejbca.ear"
DEPLOY_NAME="ejbca.ear"
LOG_FILE="$LOG_DIR/phase1-wildfly30-ejbca9.log"
PID_FILE="$PHASE1_DIR/phase1-wildfly30-ejbca9.pid"
JAVA21_HOME="/usr/lib/jvm/java-21-openjdk"
HEALTH_URL="http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth"
OCSP_URL="http://127.0.0.1:8080/ejbca/publicweb/status/ocsp"
FAIL_FAST="${PHASE3_FAIL_FAST:-0}"

if [[ "${1:-}" == "--fail-fast" ]]; then
  FAIL_FAST="1"
fi

# --- Load production credentials --------------------------------------------
PROD_CREDS_FILE="$PHASE1_DIR/.db-credentials"
if [[ ! -f "$PROD_CREDS_FILE" ]]; then
  echo "ERROR: Production credentials file not found: $PROD_CREDS_FILE"
  echo "       Run ./phase1/phase1-setup-mariadb.sh first"
  exit 1
fi
# shellcheck source=/dev/null
source "$PROD_CREDS_FILE"

# --- Pre-flight checks ------------------------------------------------------
MARIADB_MODULE_DIR="$WILDFLY_HOME/modules/org/mariadb/jdbc/main"
if [[ ! -f "$MARIADB_MODULE_DIR/mariadb-java-client.jar" ]]; then
  echo "ERROR: MariaDB WildFly module not installed: $MARIADB_MODULE_DIR"
  exit 1
fi

if ! mysql -u"${EJBCA_DB_USER}" -p"${EJBCA_DB_PASSWORD}" "${EJBCA_DB_NAME}" -e "SELECT 1" >/dev/null 2>&1; then
  echo "ERROR: Cannot reach production database '${EJBCA_DB_NAME}' as '${EJBCA_DB_USER}'"
  echo "       Ensure MariaDB is running:  sudo systemctl start mariadb"
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

echo "[prod-restore] Stopping any running pilot/test instance"
pkill -f 'wildfly-30.0.1.Final|jboss-modules.jar' 2>/dev/null || true
sleep 3
rm -f "$WILDFLY_HOME/standalone/deployments/ejbca.ear"*
rm -f "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME"*
rm -f "$WILDFLY_HOME/standalone/deployments/ejbca9.ear"*

echo "[prod-restore] Starting EJBCA on PRODUCTION database: ${EJBCA_DB_NAME}"

# --- Start WildFly ----------------------------------------------------------
mkdir -p "$LOG_DIR"
cd "$WILDFLY_HOME"
JAVA_HOME="$JAVA21_HOME" PATH="$JAVA21_HOME/bin:$PATH" nohup ./bin/standalone.sh -b 127.0.0.1 > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 12

echo "[prod-restore] PID: $(cat "$PID_FILE")"
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
    echo "[prod-restore] Removing stale managed deployment: ${stale}"
    "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="/deployment=${stale}:undeploy" >/dev/null 2>&1 || true
    "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="/deployment=${stale}:remove" >/dev/null 2>&1 || true
  fi
done

# --- Configure datasource pointing at production DB -------------------------
if "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/data-source=EjbcaDS:read-resource' >/dev/null 2>&1; then
  echo "[prod-restore] Removing existing EjbcaDS"
  "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/data-source=EjbcaDS:remove'
fi

if ! "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/jdbc-driver=mariadb:read-resource' >/dev/null 2>&1; then
  echo "[prod-restore] Registering MariaDB JDBC driver"
  "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/jdbc-driver=mariadb:add(driver-name=mariadb,driver-module-name=org.mariadb.jdbc,driver-class-name=org.mariadb.jdbc.Driver)'
fi

echo "[prod-restore] Configuring datasource java:/EjbcaDS → production database: ${EJBCA_DB_NAME}"
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
echo "[prod-restore] Probing endpoints:"
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

echo "[prod-restore] healthcheck_http=$health_code"
echo "[prod-restore] status_ocsp_http=$ocsp_code"

if [[ "$FAIL_FAST" == "1" && ( "$health_code" != "200" || "$ocsp_code" != "200" ) ]]; then
  echo "ERROR: Production readiness probes failed"
  exit 1
fi

echo ""
echo "[prod-restore] EJBCA is running on PRODUCTION database: ${EJBCA_DB_NAME}"
echo "  Admin web : http://127.0.0.1:8080/ejbca/adminweb/"
echo "  Log file  : $LOG_FILE"

echo ""
echo "[prod-restore] Recent log markers:"
grep -E 'WFLYSRV0010|WFLYSRV0026|WFLYCTL0013|EjbcaDS|ejbca\.ear|ejbca9\.ear|ERROR|Exception' \
  "$LOG_FILE" | tail -30 || true
