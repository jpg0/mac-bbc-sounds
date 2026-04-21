#!/bin/bash

# Configuration
APP_NAME="BBCSoundsMenuBar"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Building ${APP_NAME}..."

# 1. Build the executable using Swift Package Manager
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

# 2. Extract the binary path
BINARY_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}

# 3. Create the .app bundle structure
echo "📦 Packaging into ${BUNDLE_NAME}..."
rm -rf "${BUNDLE_NAME}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 4. Copy the binary
cp "${BINARY_PATH}" "${MACOS_DIR}/"

# 5. Copy Info.plist and Icon
cp "Info.plist" "${CONTENTS_DIR}/"
cp "AppIcon.icns" "${RESOURCES_DIR}/"

# 6. Ad-hoc Codesign (required for some macOS features)
echo "🔐 Codesigning..."
codesign --force --deep --options runtime --entitlements "BBCSoundsMenuBar.entitlements" --sign - "${BUNDLE_NAME}"

echo "✅ Success! You can now run the app with:"
echo "   open ${BUNDLE_NAME}"
