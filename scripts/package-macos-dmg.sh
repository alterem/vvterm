#!/bin/bash

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    cat <<'EOF'
Usage:
  scripts/package-macos-dmg.sh <app-path> <output-dmg> [volume-name] [staging-dir]

Example:
  scripts/package-macos-dmg.sh \
    build/Release/VVTerm.app \
    dist/VVTerm-macos-arm64.dmg \
    "VVTerm"
EOF
    exit 1
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
VOLUME_NAME="${3:-VVTerm}"
STAGING_DIR="${4:-}"
SAFE_VOLUME_NAME="$(echo "$VOLUME_NAME" | tr -cd '[:alnum:]. _-')"
if [ -z "$SAFE_VOLUME_NAME" ]; then
    SAFE_VOLUME_NAME="VVTerm"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
fi

if [ -z "$STAGING_DIR" ]; then
    STAGING_DIR="$(mktemp -d)"
fi

cleanup() {
    hdiutil detach "/Volumes/$SAFE_VOLUME_NAME" -force >/dev/null 2>&1 || true
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR"
mkdir -p "$(dirname "$OUTPUT_DMG")"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil detach "/Volumes/$SAFE_VOLUME_NAME" -force >/dev/null 2>&1 || true
rm -f "$OUTPUT_DMG"

attempt=1
max_attempts=3

while [ "$attempt" -le "$max_attempts" ]; do
    if hdiutil create \
        -volname "$VOLUME_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov \
        -format UDZO \
        "$OUTPUT_DMG"; then
        exit 0
    fi

    if [ "$attempt" -eq "$max_attempts" ]; then
        echo "Failed to create DMG after $max_attempts attempts." >&2
        exit 1
    fi

    echo "hdiutil create failed on attempt $attempt/$max_attempts; cleaning up and retrying..." >&2
    hdiutil detach "/Volumes/$SAFE_VOLUME_NAME" -force >/dev/null 2>&1 || true
    rm -f "$OUTPUT_DMG"
    sleep $((attempt * 3))
    attempt=$((attempt + 1))
done
