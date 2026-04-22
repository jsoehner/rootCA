#!/usr/bin/env bash
set -euo pipefail

# Fedora host hardening helper for Phase 1.
# Requires sudo. Designed to be idempotent.

echo "[hardening] Updating packages"
sudo dnf -y upgrade

echo "[hardening] Installing audit tooling"
sudo dnf -y install audit audit-libs

echo "[hardening] Enabling auditd and pcscd"
sudo systemctl enable --now auditd pcscd

echo "[hardening] Disabling unneeded desktop services if present"
for svc in cups avahi-daemon bluetooth; do
  if systemctl list-unit-files | grep -q "^${svc}\.service"; then
    sudo systemctl disable --now "${svc}.service" || true
    sudo systemctl mask "${svc}.service" || true
  fi
done

echo "[hardening] Writing minimal audit rules for EJBCA paths"
sudo mkdir -p /etc/audit/rules.d
cat << 'EOF' | sudo tee /etc/audit/rules.d/ejbca-phase1.rules >/dev/null
-w ~/rootCA -p wa -k rootca_workspace
-w ~/rootCA/artifacts -p wa -k rootca_artifacts
EOF
sudo augenrules --load || true

echo "[hardening] Status checks"
systemctl is-active auditd || true
systemctl is-active pcscd || true
for svc in cups avahi-daemon bluetooth; do
  systemctl is-enabled "${svc}.service" 2>/dev/null || true
done

echo "[hardening] Completed"
