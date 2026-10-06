#!/usr/bin/env python3
"""Merge ZXing classes into the ARCamera AAR (fat AAR).

Godot's Android export consumes plugin AARs as flat files with NO transitive
dependencies, so a normal Gradle `implementation` dep on ZXing would be lost.
Instead we build a thin AAR and merge the ZXing .class files into its
classes.jar here. Deterministic, testable without the Android SDK.

Usage: merge_zxing_aar.py <input.aar> <zxing-core.jar> <output.aar>
"""
import sys
import zipfile
import shutil
import os


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: merge_zxing_aar.py <input.aar> <zxing-core.jar> <output.aar>",
              file=sys.stderr)
        return 2
    in_aar, zxing_jar, out_aar = sys.argv[1], sys.argv[2], sys.argv[3]

    # Read the thin AAR's entries.
    with zipfile.ZipFile(in_aar, "r") as z:
        entries = {name: z.read(name) for name in z.namelist()}

    if "classes.jar" not in entries:
        print("ERROR: input AAR has no classes.jar", file=sys.stderr)
        return 1

    # Merge ZXing classes into classes.jar (skip signatures/metadata).
    classes = {}
    with zipfile.ZipFile(in_aar, "r") as z:
        with z.open("classes.jar") as cf:
            with zipfile.ZipFile(cf, "r") as cj:
                for name in cj.namelist():
                    classes[name] = cj.read(name)
    added = 0
    with zipfile.ZipFile(zxing_jar, "r") as zj:
        for name in zj.namelist():
            if not name.endswith(".class"):
                continue
            if name.startswith("META-INF/"):
                continue
            if name not in classes:
                classes[name] = zj.read(name)
                added += 1

    # Rebuild classes.jar in-memory, then the AAR.
    import io
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as cj:
        for name in sorted(classes):
            cj.writestr(name, classes[name])
    entries["classes.jar"] = buf.getvalue()

    tmp = out_aar + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(entries):
            z.writestr(name, entries[name])
    shutil.move(tmp, out_aar)
    print(f"merged {added} zxing classes -> {out_aar}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
