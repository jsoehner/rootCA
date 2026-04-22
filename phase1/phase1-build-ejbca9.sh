#!/usr/bin/env bash
set -euo pipefail

# Local EJBCA 9 build helper.

ROOT="${HOME}/rootCA"
PHASE1_DIR="$ROOT/phase1"
LOG_DIR="$PHASE1_DIR/logs"
EJBCA_DIR="$ROOT/artifacts/ejbca/ejbca-ce-r9.3.7"
APPSRV_HOME_DIR="$ROOT/artifacts/appserver/wildfly-30.0.1.Final"
LOG_FILE="$LOG_DIR/phase1-ant-build-ejbca9.log"

mkdir -p "$LOG_DIR"

if [[ ! -d "$EJBCA_DIR" ]]; then
  echo "ERROR: EJBCA 9 source directory not found: $EJBCA_DIR"
  exit 1
fi

DB_PROPS="$EJBCA_DIR/conf/database.properties"
if [[ ! -f "$DB_PROPS" ]]; then
  echo "WARNING: $DB_PROPS not found — build will default to H2 dialect"
  echo "         Run ./phase1/phase1-setup-mariadb.sh first to configure MariaDB"
else
  echo "[phase1-build-ejbca9] Using database config: $(grep 'database.name' "$DB_PROPS" | head -n 1)"
fi

if [[ ! -d "$APPSRV_HOME_DIR" ]]; then
  echo "ERROR: WildFly 30 directory not found: $APPSRV_HOME_DIR"
  exit 1
fi

JAVA21_HOME="/usr/lib/jvm/java-21-openjdk"
if [[ ! -x "$JAVA21_HOME/bin/java" ]]; then
  echo "ERROR: Java 21 not found at $JAVA21_HOME"
  exit 1
fi

echo "[phase1-build-ejbca9] Starting clean build"
cd "$EJBCA_DIR"
JAVA_HOME="$JAVA21_HOME" PATH="$JAVA21_HOME/bin:$PATH" APPSRV_HOME="$APPSRV_HOME_DIR" ant clean build > "$LOG_FILE" 2>&1

echo "[phase1-build-ejbca9] Build completed"
echo "[phase1-build-ejbca9] Log: $LOG_FILE"
grep -E 'java.version\(ant.java\)|BUILD SUCCESSFUL|BUILD FAILED' "$LOG_FILE" | tail -n 30 || true
