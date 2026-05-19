#!/bin/bash

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 5 ]; then
    cat <<'EOF'
Usage:
  scripts/package-ios-ipa.sh <archive-path> <output-dir> [export-options-plist] [project] [scheme]

Example:
  scripts/package-ios-ipa.sh \
    .build/archives/VVTerm.xcarchive \
    .build/output \
    /tmp/ExportOptions.plist \
    VVTerm.xcodeproj \
    VVTerm
EOF
    exit 1
fi

ARCHIVE_PATH="$1"
OUTPUT_DIR="$2"
EXPORT_OPTIONS_PLIST="${3:-}"
PROJECT="${4:-VVTerm.xcodeproj}"
SCHEME="${5:-VVTerm}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/DerivedData}"
TEAM_ID="${TEAM_ID:-K68RDJ84GS}"
APP_NAME="${APP_NAME:-VVTerm}"
UNSIGNED_IPA="${UNSIGNED_IPA:-0}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-0}"
ALLOW_PROVISIONING_DEVICE_REGISTRATION="${ALLOW_PROVISIONING_DEVICE_REGISTRATION:-0}"
APP_STORE_CONNECT_API_KEY_PATH="${APP_STORE_CONNECT_API_KEY_PATH:-}"
APP_STORE_CONNECT_API_KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-}"
APP_STORE_CONNECT_API_ISSUER_ID="${APP_STORE_CONNECT_API_ISSUER_ID:-}"

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$OUTPUT_DIR" "$DERIVED_DATA_PATH"

if [ "$UNSIGNED_IPA" = "1" ] || [ "$UNSIGNED_IPA" = "true" ]; then
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -sdk iphoneos \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        EXPANDED_CODE_SIGN_IDENTITY="" \
        COMPILER_INDEX_STORE_ENABLE=NO \
        build

    APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/$APP_NAME.app"
    if [ ! -d "$APP_PATH" ]; then
        echo "Unsigned app bundle not found: $APP_PATH" >&2
        exit 1
    fi

    STAGING_DIR="$(mktemp -d)"
    cleanup() {
        rm -rf "$STAGING_DIR"
    }
    trap cleanup EXIT

    mkdir -p "$STAGING_DIR/Payload"
    cp -R "$APP_PATH" "$STAGING_DIR/Payload/"

    IPA_PATH="$OUTPUT_DIR/$APP_NAME-unsigned.ipa"
    rm -f "$IPA_PATH"
    (cd "$STAGING_DIR" && /usr/bin/zip -qry "$IPA_PATH" Payload)
    echo "Created unsigned IPA: $IPA_PATH"
    exit 0
fi

XCODEBUILD_SIGNING_ARGS=()
if [ "$ALLOW_PROVISIONING_UPDATES" = "1" ] || [ "$ALLOW_PROVISIONING_UPDATES" = "true" ]; then
    XCODEBUILD_SIGNING_ARGS+=("-allowProvisioningUpdates")
fi

if [ "$ALLOW_PROVISIONING_DEVICE_REGISTRATION" = "1" ] || [ "$ALLOW_PROVISIONING_DEVICE_REGISTRATION" = "true" ]; then
    XCODEBUILD_SIGNING_ARGS+=("-allowProvisioningDeviceRegistration")
fi

if [ -n "$APP_STORE_CONNECT_API_KEY_PATH" ] || [ -n "$APP_STORE_CONNECT_API_KEY_ID" ] || [ -n "$APP_STORE_CONNECT_API_ISSUER_ID" ]; then
    if [ -z "$APP_STORE_CONNECT_API_KEY_PATH" ] || [ -z "$APP_STORE_CONNECT_API_KEY_ID" ] || [ -z "$APP_STORE_CONNECT_API_ISSUER_ID" ]; then
        echo "APP_STORE_CONNECT_API_KEY_PATH, APP_STORE_CONNECT_API_KEY_ID, and APP_STORE_CONNECT_API_ISSUER_ID must be set together." >&2
        exit 1
    fi

    XCODEBUILD_SIGNING_ARGS+=(
        "-allowProvisioningUpdates"
        "-authenticationKeyPath" "$APP_STORE_CONNECT_API_KEY_PATH"
        "-authenticationKeyID" "$APP_STORE_CONNECT_API_KEY_ID"
        "-authenticationKeyIssuerID" "$APP_STORE_CONNECT_API_ISSUER_ID"
    )
fi

xcodebuild \
    "${XCODEBUILD_SIGNING_ARGS[@]}" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    archive

if [ -n "$EXPORT_OPTIONS_PLIST" ]; then
    if [ ! -f "$EXPORT_OPTIONS_PLIST" ]; then
        echo "Export options plist not found: $EXPORT_OPTIONS_PLIST" >&2
        exit 1
    fi

    xcodebuild \
        "${XCODEBUILD_SIGNING_ARGS[@]}" \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$OUTPUT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
fi
