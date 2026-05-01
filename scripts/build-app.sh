#!/bin/bash
# Build a distributable Cue Mini.app from the Swift Package.
#
# Usage:
#   scripts/build-app.sh                # debug build, ad-hoc signed
#   scripts/build-app.sh --release      # release build, ad-hoc signed
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#     scripts/build-app.sh --release    # release build, properly signed
#
# After building you'll have ./build/Cue Mini.app

set -euo pipefail

CONFIG="debug"
ARCHS=("arm64")
if [[ "${1:-}" == "--release" ]]; then
    CONFIG="release"
    ARCHS=("arm64" "x86_64")
fi

APP_NAME="Cue Mini"
EXEC_NAME="CueMini"
BUNDLE_ID="com.josephrussell.cuemini"
BUILD_DIR="$(pwd)/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

echo "==> Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

if [[ "$CONFIG" == "release" ]]; then
    echo "==> Building universal release binary"
    BIN_PATHS=()
    for ARCH in "${ARCHS[@]}"; do
        echo "    -> $ARCH"
        swift build -c release --arch "$ARCH"
        BIN_PATHS+=("$(swift build -c release --arch "$ARCH" --show-bin-path)/$EXEC_NAME")
    done
    lipo -create -output "$APP_PATH/Contents/MacOS/$EXEC_NAME" "${BIN_PATHS[@]}"
else
    echo "==> Building debug binary"
    swift build
    cp "$(swift build --show-bin-path)/$EXEC_NAME" "$APP_PATH/Contents/MacOS/$EXEC_NAME"
fi
chmod +x "$APP_PATH/Contents/MacOS/$EXEC_NAME"

echo "==> Copying Info.plist + Resources"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"

# SwiftPM emits a per-target resource bundle alongside the binary.
# It must travel into the .app or the runtime aborts loading resources (fonts, etc).
if [[ "$CONFIG" == "release" ]]; then
    BUNDLE_SRC="$(swift build -c release --arch arm64 --show-bin-path)/CueMini_CueMini.bundle"
else
    BUNDLE_SRC="$(swift build --show-bin-path)/CueMini_CueMini.bundle"
fi
if [[ -d "$BUNDLE_SRC" ]]; then
    # Place the SwiftPM resource bundle inside Contents/Resources so codesign's
    # bundle layout rules are happy. Fonts.swift looks for it in both locations.
    cp -R "$BUNDLE_SRC" "$APP_PATH/Contents/Resources/CueMini_CueMini.bundle"
fi

# PkgInfo is the classic Mac type/creator file; some tools sniff it
printf "APPL????" > "$APP_PATH/Contents/PkgInfo"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    if [[ -f "Resources/embedded.provisionprofile" ]]; then
        echo "==> Embedding provisioning profile"
        cp "Resources/embedded.provisionprofile" "$APP_PATH/Contents/embedded.provisionprofile"
    else
        echo "WARN: Resources/embedded.provisionprofile not found."
        echo "      ShazamKit-restricted entitlements will fail at launch."
    fi
    echo "==> Signing with Developer ID: $DEVELOPER_ID (distribution entitlements)"
    codesign --force --options runtime --timestamp \
        --entitlements Resources/CueMini.entitlements \
        --sign "$DEVELOPER_ID" \
        "$APP_PATH"
else
    echo "==> Ad-hoc signing (no DEVELOPER_ID set) — using DEV entitlements"
    echo "    Note: ShazamKit will not work in this build. Set DEVELOPER_ID for distribution."
    codesign --force \
        --entitlements Resources/CueMini-Dev.entitlements \
        --sign - \
        "$APP_PATH"
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true

echo ""
echo "Done: $APP_PATH"
echo "Run with: open \"$APP_PATH\""
