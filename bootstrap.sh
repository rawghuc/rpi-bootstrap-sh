#!/usr/bin/env bash
set -euo pipefail

##############################################
# CONFIG (SAFE TO EXPOSE)
##############################################

# Short URL that redirects to installer ZIP
INSTALLER_ZIP_URL="http://parksense.co.in/rawghuc/rpi-scripts-installer"

# Temporary working directory (randomized)
WORKDIR="$(mktemp -d -t rpi-installer-XXXXXXXX)"

##############################################
# CLEANUP LOGIC (CRITICAL)
##############################################

cleanup() {
  echo "[bootstrap] Cleaning up installer files..."
  if [ -d "$WORKDIR" ]; then
    # Overwrite + remove for defense-in-depth
    find "$WORKDIR" -type f -exec shred -u {} \; 2>/dev/null || true
    rm -rf "$WORKDIR"
  fi
}

# Cleanup on:
# - script exit
# - error
# - Ctrl+C
# - kill
trap cleanup EXIT INT TERM

##############################################
# SANITY CHECKS
##############################################

if [ "$(id -u)" -ne 0 ]; then
  echo "[bootstrap] ERROR: must be run as root (use sudo)"
  exit 1
fi

command -v curl >/dev/null || { echo "curl not found"; exit 1; }
command -v unzip >/dev/null || apt update && apt install -y unzip

##############################################
# DOWNLOAD INSTALLER ZIP
##############################################

echo "[bootstrap] Downloading installer package..."
ZIP_PATH="$WORKDIR/installer.zip"

curl -fsSL "$INSTALLER_ZIP_URL" -o "$ZIP_PATH"

##############################################
# EXTRACT ZIP
##############################################

echo "[bootstrap] Extracting installer..."
unzip -q "$ZIP_PATH" -d "$WORKDIR"

# GitHub ZIP extracts into a subfolder — find it
INSTALL_ROOT="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"

echo "[bootstrap] install root: $INSTALL_ROOT"

if [ -z "$INSTALL_ROOT" ]; then
  echo "[bootstrap] ERROR: installer directory not found"
  exit 1
fi

##############################################
# LOCATE INSTALLER SCRIPTS
##############################################

INSTALL_DIR="$INSTALL_ROOT/installer"

if [ ! -f "$INSTALL_DIR/install-master.sh" ]; then
  echo "[bootstrap] ERROR: install-master.sh not found"
  cd $INSTALL_DIR
  ls
  exit 1
fi

##############################################
# LOCK DOWN PERMISSIONS
##############################################

echo "[bootstrap] Securing installer permissions..."
chmod 700 "$INSTALL_DIR"
chmod +x "$INSTALL_DIR"/*.sh

##############################################
# EXECUTE MASTER INSTALLER
##############################################

echo "[bootstrap] Starting master installer..."
cd "$INSTALL_DIR"

# IMPORTANT:
# - No arguments
# - Secrets live ONLY inside install-master.sh
# - bootstrap never sees secrets
./install-master.sh

##############################################
# SUCCESS PATH
##############################################

echo "[bootstrap] Installation finished successfully."

# cleanup() will run automatically via trap

echo "[bootstrap] Rebooting system..."
sleep 2
reboot
