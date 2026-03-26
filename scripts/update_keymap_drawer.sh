#!/bin/bash
# Update keymap-drawer files from config/charybdis.keymap

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
KEYMAP_DRAWER_DIR="${SCRIPT_DIR}/../keymap-drawer"
KEYMAP_FILE="${CONFIG_DIR}/charybdis.keymap"
LAYOUT_FILE="${CONFIG_DIR}/charybdis.json"
CONFIG_FILE="${KEYMAP_DRAWER_DIR}/config.yaml"
BASE_YAML="${KEYMAP_DRAWER_DIR}/charybdis.yaml"
OUTPUT_YAML="${KEYMAP_DRAWER_DIR}/charybdis.yaml"
OUTPUT_SVG="${KEYMAP_DRAWER_DIR}/charybdis.svg"

echo "Updating keymap-drawer files..."
echo "Keymap: ${KEYMAP_FILE}"
echo "Config: ${CONFIG_FILE}"
echo ""

# Check if keymap-drawer is installed
if ! command -v keymap &> /dev/null; then
    echo "Error: keymap-drawer is not installed."
    echo "Install it with: pip install keymap-drawer"
    exit 1
fi

# Parse the keymap and update YAML
echo "Parsing keymap file..."
keymap -c "${CONFIG_FILE}" parse -z "${KEYMAP_FILE}" -b "${BASE_YAML}" > "${OUTPUT_YAML}.tmp"

# Move temp file to final location
mv "${OUTPUT_YAML}.tmp" "${OUTPUT_YAML}"
echo "Updated: ${OUTPUT_YAML}"

# Generate SVG from YAML
echo "Generating SVG..."
keymap -c "${CONFIG_FILE}" draw -j "${LAYOUT_FILE}" "${OUTPUT_YAML}" > "${OUTPUT_SVG}"
echo "Updated: ${OUTPUT_SVG}"

echo ""
echo "Done! Keymap-drawer files have been updated."
