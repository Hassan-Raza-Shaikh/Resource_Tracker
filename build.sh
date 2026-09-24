#!/bin/bash
set -e

echo "=== Building Resource Tracker App ==="

# 1. Setup build directories
echo "Creating build directory structure..."
mkdir -p build/"Resource Tracker.app"/Contents/MacOS
mkdir -p build/"Resource Tracker.app"/Contents/Resources

# 2. Check and copy icon source
# Prefer the committed, repo-local icon so the build is reproducible on any machine.
ICON_SOURCE="assets/app_icon.jpg"
if [ -f "$ICON_SOURCE" ]; then
    echo "Copying app icon base image..."
    cp "$ICON_SOURCE" build/app_icon_base.jpg
else
    echo "Warning: Base app icon image not found at $ICON_SOURCE. Skipping icon build."
fi

# 3. Generate transparent app icon and build .icns
if [ -f "build/app_icon_base.jpg" ]; then
    echo "Masking and cropping app icon background..."
    python3 src/mask_icon.py
fi

if [ -f "build/app_icon_base_transparent.png" ]; then
    echo "Generating multi-resolution macOS iconset..."
    mkdir -p build/AppIcon.iconset
    
    # Scale base transparent image into standard icon sizes
    sips -s format png -z 16 16     build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_16x16.png > /dev/null
    sips -s format png -z 32 32     build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_16x16@2x.png > /dev/null
    sips -s format png -z 32 32     build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_32x32.png > /dev/null
    sips -s format png -z 64 64     build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_32x32@2x.png > /dev/null
    sips -s format png -z 128 128   build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_128x128.png > /dev/null
    sips -s format png -z 256 256   build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_128x128@2x.png > /dev/null
    sips -s format png -z 256 256   build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_256x256.png > /dev/null
    sips -s format png -z 512 512   build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_256x256@2x.png > /dev/null
    sips -s format png -z 512 512   build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_512x512.png > /dev/null
    sips -s format png -z 1024 1024 build/app_icon_base_transparent.png --out build/AppIcon.iconset/icon_512x512@2x.png > /dev/null
    
    echo "Compiling .icns file..."
    iconutil -c icns build/AppIcon.iconset -o build/"Resource Tracker.app"/Contents/Resources/AppIcon.icns
    
    # Cleanup temp iconset files
    rm -rf build/AppIcon.iconset
fi

# 4. Copy Info.plist config
echo "Copying Info.plist..."
cp Info.plist build/"Resource Tracker.app"/Contents/Info.plist

# 5. Compile Swift application
echo "Compiling Swift source files..."
SDK_PATH=$(xcrun --show-sdk-path)
swiftc -sdk "$SDK_PATH" -target arm64-apple-macos27.0 -O \
    -o build/"Resource Tracker.app"/Contents/MacOS/"Resource Tracker" \
    src/*.swift

echo "=== Build Completed Successfully ==="
echo "You can run the application using: open build/\"Resource Tracker.app\""
