#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "🔨 Building GanttLab (Release mode)..."
SDK_PATH=""
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
elif [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi

mkdir -p "$DIR/.build/release"
if swift build -c release 2>/dev/null; then
    echo "✅ Built with swift build"
else
    echo "⚠️ swift build failed, compiling directly via swiftc..."
    SWIFT_FILES=()
    while IFS= read -r file; do
        SWIFT_FILES+=("$file")
    done < <(find Sources -name "*.swift")
    if [ -n "$SDK_PATH" ]; then
        swiftc -O -sdk "$SDK_PATH" -parse-as-library "${SWIFT_FILES[@]}" -o "$DIR/.build/release/GanttLab"
    else
        swiftc -O -parse-as-library "${SWIFT_FILES[@]}" -o "$DIR/.build/release/GanttLab"
    fi
    echo "✅ Built with swiftc successfully"
fi

APP_NAME="Gantt Lab"
BUNDLE_DIR="$DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating macOS App Bundle at $BUNDLE_DIR..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$DIR/.build/release/GanttLab" "$MACOS_DIR/$APP_NAME"

# Copy App Icon
if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

BUILD_DATE=$(date "+%Y.%m.%d")

# Manage auto-incrementing build number starting from 1
BUILD_NUM_FILE="$DIR/build_number.txt"
if [ ! -f "$BUILD_NUM_FILE" ]; then
    BUILD_NUMBER=1
else
    PREV_NUM=$(cat "$BUILD_NUM_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$PREV_NUM" ] || ! [[ "$PREV_NUM" =~ ^[0-9]+$ ]]; then
        BUILD_NUMBER=1
    else
        BUILD_NUMBER=$((PREV_NUM + 1))
    fi
fi
echo "$BUILD_NUMBER" > "$BUILD_NUM_FILE"

FULL_VERSION="$BUILD_DATE ($BUILD_NUMBER)"
echo "🏷 Build Version: $FULL_VERSION"

# Create Info.plist
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.ganttlab.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$FULL_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>GanttLab Project</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.ganttlab.project</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.ganttlab.project</string>
            <key>UTTypeDescription</key>
            <string>GanttLab Project File</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>ganttlab</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "✅ '$APP_NAME.app' bundle created successfully!"
echo "👉 You can now double-click '$APP_NAME.app' in Finder or run: open '$BUNDLE_DIR'"
