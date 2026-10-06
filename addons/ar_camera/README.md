# ARCamera — Passthrough Camera Android plugin for NEXUS ARCADE

Quest 3 front RGB camera access for Godot, built on Android Camera2
(the same foundation as Meta's Passthrough Camera API).

## Layout

- `android/` — Gradle library module (Java sources, `libs/zxing-core.jar`)
- `ar_camera.gdip` — Godot plugin config (copied to `android/plugins/` by the build)
- `ar_camera.aar` — built by CI (fat AAR: plugin + ZXing classes)

## GDScript API (via `scripts/shared/ar_camera.gd`)

- `ARCamera.is_available()` → bool
- `ARCamera.request_permission()` → void
- `ARCamera.capture()` → Image (JPEG still) or null
- `ARCamera.frame_size()` → Vector2i
- `ARCamera.scan_qr()` → String ("" when none)

On-device CV helpers: `scripts/shared/camera_vision.gd`
(color analysis, Sobel edges, brightness, roundness — no ML API, no key).

## Building

No local JDK in this sandbox, so the AAR is built in CI:

```yaml
- name: Build ARCamera plugin
  run: |
    wget -q https://services.gradle.org/distributions/gradle-8.7-bin.zip
    unzip -q gradle-8.7-bin.zip -d /tmp
    export PATH=/tmp/gradle-8.7/bin:$PATH
    export ANDROID_HOME=/usr/local/lib/android/sdk
    export ANDROID_SDK_ROOT=/usr/local/lib/android/sdk
    bash tools/build_camera_plugin.sh
```

This compiles the library, merges ZXing into the AAR
(`tools/merge_zxing_aar.py` — tested), and installs
`ar_camera.aar` + `ar_camera.gdip` into `android/plugins/`
before the Godot export step.

## App manifest

The merge step adds to `export_presets.cfg` permissions:
`android.permission.CAMERA` and `horizonos.permission.HEADSET_CAMERA`.
The godotopenxrvendors plugin already injects the HorizonOS camera
permissions when CAMERA is enabled (verify on first device test).

## Privacy

Frames are captured on demand, processed on-device, never uploaded.
The games show a "camera unavailable" fallback + manual mode when the
permission/hardware is missing.
