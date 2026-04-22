#!/usr/bin/env bash
set -euo pipefail

# Remediation helper for Fedora Phase 1 prerequisites.
# Requires sudo privileges.

echo "[phase1-remediate] Fixing Java alternatives"
sudo alternatives --set java /usr/lib/jvm/java-21-openjdk/bin/java

echo "[phase1-remediate] Installing prerequisites"
sudo dnf -y install ant mariadb postgresql

echo "[phase1-remediate] Running verifier"
"$(dirname "$0")/phase1-verify-fedora.sh"
