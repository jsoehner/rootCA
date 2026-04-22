#!/usr/bin/env bash
set -euo pipefail

echo "=== UTC ==="
date -u

echo "=== Binaries ==="
for b in java ant mysql mariadb psql opensc-tool pkcs11-tool pcsc_scan; do
  if command -v "$b" >/dev/null 2>&1; then
    command -v "$b"
  else
    echo "MISSING:$b"
  fi
done

echo "=== Versions ==="
java -version 2>&1 | head -n 2 || true
ant -version 2>&1 | head -n 1 || true

echo "=== Java Alternatives ==="
alternatives --display java 2>/dev/null | head -n 20 || true
if [[ -L /usr/bin/java ]] && [[ ! -x /usr/bin/java ]]; then
  echo "BROKEN_JAVA_ALTERNATIVE:/usr/bin/java points to a non-executable target"
  echo "REMEDIATION: sudo alternatives --set java /usr/lib/jvm/java-21-openjdk/bin/java"
fi

echo "=== PKCS11 Modules ==="
find /usr -name '*opensc-pkcs11*.so' 2>/dev/null | head -n 5 || true

echo "=== Slots ==="
pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --list-slots 2>&1 | head -n 80 || true

echo "=== pcscd ==="
systemctl is-active pcscd || true
systemctl is-enabled pcscd || true

echo "=== Network Links ==="
ip -br link
