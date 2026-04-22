#!/usr/bin/env bash
set -euo pipefail

# Phase 1 bootstrap for Fedora-based offline EJBCA root host.
# Installs required packages and ensures pcscd is enabled.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[phase1] Starting Fedora bootstrap"
echo "[phase1] Installing packages"
sudo dnf -y install \
  java-21-openjdk-headless \
  ant \
  mariadb \
  postgresql \
  opensc \
  pcsc-tools \
  pcsc-lite

echo "[phase1] Enabling pcscd"
sudo systemctl enable --now pcscd

echo "[phase1] Writing verification helper"
cat > "$SCRIPT_DIR/phase1-verify-fedora.sh" << 'EOF'
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

echo "=== PKCS11 Modules ==="
find /usr -name '*opensc-pkcs11*.so' 2>/dev/null | head -n 5 || true

echo "=== Slots ==="
pkcs11-tool --module /usr/lib64/opensc-pkcs11.so --list-slots 2>&1 | head -n 80 || true

echo "=== pcscd ==="
systemctl is-active pcscd || true
systemctl is-enabled pcscd || true

echo "=== Network Links ==="
ip -br link
EOF
chmod +x "$SCRIPT_DIR/phase1-verify-fedora.sh"

echo "[phase1] Bootstrap complete"
echo "[phase1] Run ./phase1/phase1-verify-fedora.sh to verify readiness"
