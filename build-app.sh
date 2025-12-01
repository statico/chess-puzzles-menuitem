#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}[DEBUG] Building Chess Puzzles app bundle...${NC}"

# Get version from Package.swift
echo -e "${GREEN}[DEBUG] Extracting version from Package.swift...${NC}"
VERSION=$(grep -E '^let version = ' Package.swift | sed -E "s/let version = \"(.*)\"/\1/")
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not find version in Package.swift${NC}"
    exit 1
fi

echo -e "${YELLOW}[DEBUG] Version: ${VERSION}${NC}"

# Build configuration
BUILD_CONFIG="${1:-release}"
APP_NAME="Chess Puzzles"
APP_BUNDLE="${APP_NAME}.app"
EXECUTABLE_NAME="chess-puzzles-menuitem"
BUNDLE_ID="com.chesspuzzles.menuitem"

# Clean previous build
if [ -d "${APP_BUNDLE}" ]; then
    echo -e "${YELLOW}Removing existing app bundle...${NC}"
    rm -rf "${APP_BUNDLE}"
fi

# Build Swift package
echo -e "${GREEN}Building Swift package (${BUILD_CONFIG})...${NC}"
swift build -c "${BUILD_CONFIG}"

# Find the executable
EXECUTABLE_PATH=".build/${BUILD_CONFIG}/${EXECUTABLE_NAME}"
if [ ! -f "${EXECUTABLE_PATH}" ]; then
    echo -e "${RED}Error: Executable not found at ${EXECUTABLE_PATH}${NC}"
    exit 1
fi

# Find the resource bundle
RESOURCE_BUNDLE=".build/${BUILD_CONFIG}/${EXECUTABLE_NAME}_ChessPuzzlesUI.bundle"
if [ ! -d "${RESOURCE_BUNDLE}" ]; then
    echo -e "${YELLOW}Warning: Resource bundle not found at ${RESOURCE_BUNDLE}, continuing without it...${NC}"
fi

# Create app bundle structure
echo -e "${GREEN}Creating app bundle structure...${NC}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
echo -e "${GREEN}Copying executable...${NC}"
cp "${EXECUTABLE_PATH}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"

# Make executable
chmod +x "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"

# Copy resource bundle if it exists
if [ -d "${RESOURCE_BUNDLE}" ]; then
    echo -e "${GREEN}Copying resource bundle...${NC}"
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
fi

# Create icon from Assets.xcassets
echo -e "${GREEN}Creating app icon...${NC}"
ICONSET_DIR=".iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

# Generate iconset from source image with all required sizes
# iconutil requires specific filenames and exact sizes
SOURCE_ICON="App.icon/Assets/b_knight_png_1024px.png"
ICON_FILE="AppIcon.icns"

# Generate all required icon sizes with exact dimensions
sips -z 16 16 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null 2>&1 || true
sips -z 32 32 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null 2>&1 || true
sips -z 32 32 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null 2>&1 || true
sips -z 64 64 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null 2>&1 || true
sips -z 128 128 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null 2>&1 || true
sips -z 256 256 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1 || true
sips -z 256 256 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null 2>&1 || true
sips -z 512 512 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1 || true
sips -z 512 512 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null 2>&1 || true
sips -z 1024 1024 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1 || true

# Create .icns file using absolute path
ICONSET_ABS=$(cd "${ICONSET_DIR}" && pwd)
ICNS_OUTPUT=$(cd "$(dirname "${APP_BUNDLE}")" && pwd)/AppIcon.icns
if iconutil --convert icns --output "${ICNS_OUTPUT}" "${ICONSET_ABS}" 2>/dev/null; then
    mv "${ICNS_OUTPUT}" "${APP_BUNDLE}/Contents/Resources/${ICON_FILE}"
    echo -e "${GREEN}Icon created successfully${NC}"
else
    # Fallback: use the 512x512 icon directly
    echo -e "${YELLOW}Warning: iconutil failed, using 512x512 icon as fallback...${NC}"
    if [ -f "${ICONSET_DIR}/icon_512x512.png" ]; then
        cp "${ICONSET_DIR}/icon_512x512.png" "${APP_BUNDLE}/Contents/Resources/AppIcon.png"
        ICON_FILE="AppIcon.png"
    else
        ICON_FILE=""
    fi
fi
rm -rf "${ICONSET_DIR}"

# Create Info.plist
echo -e "${GREEN}Creating Info.plist...${NC}"
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>${ICON_FILE:-AppIcon}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Sign with ad hoc signing
echo -e "${GREEN}Signing app bundle with ad hoc signing...${NC}"
codesign --sign - --force --deep "${APP_BUNDLE}"

# Verify signature
echo -e "${GREEN}Verifying signature...${NC}"
codesign --verify --verbose "${APP_BUNDLE}"

echo -e "${GREEN}✓ App bundle created successfully: ${APP_BUNDLE}${NC}"
echo -e "${GREEN}✓ Version: ${VERSION}${NC}"

