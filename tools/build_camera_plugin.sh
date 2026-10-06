#!/bin/bash
# Build the ARCamera Android plugin AAR.
# Runs in CI (GitHub Actions) BEFORE the Godot export step. Requires:
#   - JDK 17, Android SDK (compileSdk 34) — both present on the CI runner
#   - Gradle 8.x on PATH (CI downloads the distribution; see CAMERA_INTEGRATION.md)
#   - Network access to Maven Central (org.godotengine:godot:4.7.2.stable)
# Output: addons/ar_camera/ar_camera.aar (fat AAR: plugin classes + ZXing),
#         then copied to android/plugins/ alongside ar_camera.gdip.
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_SRC="$PROJ_DIR/addons/ar_camera/android"
TOOLS="$PROJ_DIR/tools"

echo "==> Building ARCamera plugin AAR..."
cd "$PLUGIN_SRC"
gradle bundleRelease --no-daemon -q

THIN_AAR="$PLUGIN_SRC/build/outputs/aar/ar_camera-release.aar"
if [ ! -f "$THIN_AAR" ]; then
    # AGP names the output after the module dir when settings.gradle renames it.
    THIN_AAR="$(ls "$PLUGIN_SRC"/build/outputs/aar/*-release.aar | head -1)"
fi
echo "    thin AAR: $THIN_AAR"

echo "==> Merging ZXing classes (fat AAR)..."
python3 "$TOOLS/merge_zxing_aar.py" \
    "$THIN_AAR" \
    "$PLUGIN_SRC/libs/zxing-core.jar" \
    "$PROJ_DIR/addons/ar_camera/ar_camera.aar"

echo "==> Installing into android/plugins/ for the Godot export..."
mkdir -p "$PROJ_DIR/android/plugins"
cp "$PROJ_DIR/addons/ar_camera/ar_camera.aar" "$PROJ_DIR/android/plugins/"
cp "$PROJ_DIR/addons/ar_camera/ar_camera.gdip" "$PROJ_DIR/android/plugins/"
ls -la "$PROJ_DIR/android/plugins/"
echo "ARCamera plugin ready."
