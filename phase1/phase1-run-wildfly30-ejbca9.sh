#!/usr/bin/env bash
set -euo pipefail

ROOT="${HOME}/rootCA"
PHASE1_DIR="$ROOT/phase1"
LOG_DIR="$PHASE1_DIR/logs"
WILDFLY_HOME="$ROOT/artifacts/appserver/wildfly-30.0.1.Final"
EJBCA_EAR="$ROOT/artifacts/ejbca/ejbca-ce-r9.3.7/dist/ejbca.ear"
DEPLOY_NAME="ejbca.ear"
LOG_FILE="$LOG_DIR/phase1-wildfly30-ejbca9.log"
PID_FILE="$PHASE1_DIR/phase1-wildfly30-ejbca9.pid"
JAVA21_HOME="/usr/lib/jvm/java-21-openjdk"
HEALTH_URL="http://127.0.0.1:8080/ejbca/publicweb/healthcheck/ejbcahealth"
OCSP_URL="http://127.0.0.1:8080/ejbca/publicweb/status/ocsp"
FAIL_FAST="${PHASE1_FAIL_FAST:-0}"

if [[ "${1:-}" == "--fail-fast" ]]; then
  FAIL_FAST="1"
fi

# --- Load MariaDB credentials -----------------------------------------------
DB_CREDS_FILE="$PHASE1_DIR/.db-credentials"
if [[ ! -f "$DB_CREDS_FILE" ]]; then
  echo "ERROR: MariaDB credentials file not found: $DB_CREDS_FILE"
  echo "       Run ./phase1/phase1-setup-mariadb.sh first"
  exit 1
fi
# shellcheck source=/dev/null
source "$DB_CREDS_FILE"

# --- Pre-flight checks ------------------------------------------------------
MARIADB_MODULE_DIR="$WILDFLY_HOME/modules/org/mariadb/jdbc/main"
if [[ ! -f "$MARIADB_MODULE_DIR/mariadb-java-client.jar" ]]; then
  echo "ERROR: MariaDB WildFly module not installed: $MARIADB_MODULE_DIR"
  echo "       Run ./phase1/phase1-setup-mariadb.sh first"
  exit 1
fi

if ! mysql -u"${EJBCA_DB_USER}" -p"${EJBCA_DB_PASSWORD}" "${EJBCA_DB_NAME}" -e "SELECT 1" >/dev/null 2>&1; then
  echo "ERROR: Cannot reach MariaDB database '${EJBCA_DB_NAME}' as user '${EJBCA_DB_USER}'"
  echo "       Start MariaDB:  sudo systemctl start mariadb"
  exit 1
fi

if [[ ! -d "$WILDFLY_HOME" ]]; then
  echo "ERROR: WildFly 30 home not found: $WILDFLY_HOME"
  exit 1
fi
if [[ ! -f "$EJBCA_EAR" ]]; then
  echo "ERROR: EJBCA 9 EAR not found: $EJBCA_EAR"
  echo "Hint: run ./phase1/phase1-build-ejbca9.sh first"
  exit 1
fi
if [[ ! -x "$JAVA21_HOME/bin/java" ]]; then
  echo "ERROR: Java 21 runtime not found at $JAVA21_HOME"
  exit 1
fi

mkdir -p "$LOG_DIR"

pkill -f 'wildfly-30.0.1.Final|jboss-modules.jar' 2>/dev/null || true
rm -f "$WILDFLY_HOME/standalone/deployments/ejbca.ear"*
rm -f "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME"*
rm -f "$WILDFLY_HOME/standalone/deployments/ejbca9.ear"*

cd "$WILDFLY_HOME"
JAVA_HOME="$JAVA21_HOME" PATH="$JAVA21_HOME/bin:$PATH" nohup ./bin/standalone.sh -b 127.0.0.1 > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 12

echo "PID: $(cat "$PID_FILE")"
ps -fp "$(cat "$PID_FILE")" || true

# Wait for management endpoint before configuration.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command=':read-attribute(name=server-state)' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Remove stale managed deployments that can conflict with scanner-based deploys.
for stale in ejbca9.ear ejbca.ear; do
  if "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="/deployment=${stale}:read-resource" >/dev/null 2>&1; then
    echo "Removing stale managed deployment: ${stale}"
    "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="/deployment=${stale}:undeploy" >/dev/null 2>&1 || true
    "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="/deployment=${stale}:remove" >/dev/null 2>&1 || true
  fi
done

# Remove any stale EjbcaDS (may be leftover H2 config from a previous run)
if "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command='/subsystem=datasources/data-source=EjbcaDS:read-resource' >/dev/null 2>&1; then
  echo "Removing existing EjbcaDS for fresh configuration"
  "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command='/subsystem=datasources/data-source=EjbcaDS:remove'
fi

# Register MariaDB JDBC driver if not already present
if ! "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command='/subsystem=datasources/jdbc-driver=mariadb:read-resource' >/dev/null 2>&1; then
  echo "Registering MariaDB JDBC driver"
  "$WILDFLY_HOME/bin/jboss-cli.sh" --connect \
    --command='/subsystem=datasources/jdbc-driver=mariadb:add(driver-name=mariadb,driver-module-name=org.mariadb.jdbc,driver-class-name=org.mariadb.jdbc.Driver)'
fi

echo "Configuring datasource java:/EjbcaDS (MariaDB — ${EJBCA_DB_NAME})"
DS_CMD="data-source add --name=EjbcaDS --jndi-name=java:/EjbcaDS --driver-name=mariadb --connection-url=jdbc:mariadb://localhost:3306/${EJBCA_DB_NAME} --user-name=${EJBCA_DB_USER} --password=${EJBCA_DB_PASSWORD} --use-ccm=true --enabled=true --min-pool-size=5 --max-pool-size=20 --pool-prefill=true --validate-on-match=true --background-validation=false --prepared-statements-cache-size=50 --share-prepared-statements=true --transaction-isolation=TRANSACTION_READ_COMMITTED"
"$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="$DS_CMD"
"$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command=':reload'
sleep 10

cp "$EJBCA_EAR" "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME"
rm -f "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME.failed"
touch "$WILDFLY_HOME/standalone/deployments/$DEPLOY_NAME.dodeploy"
sleep 8

echo "Probes:"
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

echo "healthcheck_http=$health_code"
echo "status_ocsp_http=$ocsp_code"

if [[ "$FAIL_FAST" == "1" && ( "$health_code" != "200" || "$ocsp_code" != "200" ) ]]; then
  echo "ERROR: Readiness probes failed in fail-fast mode"
  echo "       healthcheck_http=$health_code"
  echo "       status_ocsp_http=$ocsp_code"
  exit 1
fi

echo "Recent log markers:"
strings "$LOG_FILE" | grep -E 'WFLYSRV0010|WFLYSRV0026|WFLYCTL0013|WFLYUT0021|ERROR|EjbcaDS|ejbca\.ear|ejbca9\.ear|UnsupportedOrmXsdVersionException|NoClassDefFoundError' | tail -n 120 || true
