#!/usr/bin/env python3
"""NEXUS ARCADE v0.9.0 gray-primitive CI audit.

Fails (in --strict mode) when shipped game scenes/scripts create untextured
default-gray meshes. Heuristics, per file:

  GDScript (scripts/games/, scripts/halloween/, scripts/*.gd):
    G1. Primitive mesh (BoxMesh/SphereMesh/CylinderMesh/CapsuleMesh/PlaneMesh/
        PrismMesh/TorusMesh/QuadMesh) instantiated with no material_override
        or surface material assigned nearby -> "untextured primitive"
    G2. StandardMaterial3D with albedo_color in the default-gray band
        (all channels 0.60-0.85, saturation < 0.12) -> "default-gray material"
    G3. GraphicsPolish.pbr() called with a gray color -> "gray pbr()"

  TSCN (scenes/**/*.tscn):
    T1. StandardMaterial3D sub_resource with albedo_color in the gray band
        (or albedo_color absent entirely) -> "default-gray material"
    T2. Primitive MeshInstance3D with no material override at all ->
        "untextured primitive"

Counts are reported per file; --mode warn (default) always exits 0 and is
wired as a non-blocking CI step. Flip the workflow to --mode strict (exit 1
on any finding) after the art pass lands.

Run:  python3 tools/ci_gray_audit.py [--mode warn|strict]
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME_DIRS = [ROOT / "scripts" / "games", ROOT / "scripts" / "halloween", ROOT / "scripts"]
SCENE_DIR = ROOT / "scenes"

PRIM_MESHES = (
    "BoxMesh", "SphereMesh", "CylinderMesh", "CapsuleMesh", "PlaneMesh",
    "PrismMesh", "TorusMesh", "QuadMesh", "TextMesh",
)

GRAY_LO, GRAY_HI = 0.60, 0.85


def is_gray(r, g, b):
    if not (GRAY_LO <= r <= GRAY_HI and GRAY_LO <= g <= GRAY_HI and GRAY_LO <= b <= GRAY_HI):
        return False
    return max(r, g, b) - min(r, g, b) < 0.12


def audit_gd(path: Path):
    findings = []
    src = path.read_text(errors="replace")
    lines = src.splitlines()
    # G2/G3: gray albedo assignments / gray pbr() calls.
    for i, ln in enumerate(lines, 1):
        m = re.search(r"albedo_color\s*=\s*Color\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)", ln)
        if m and is_gray(float(m.group(1)), float(m.group(2)), float(m.group(3))):
            findings.append((i, "default-gray material", ln.strip()[:90]))
        m2 = re.search(r"pbr\(\s*Color\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)", ln)
        if m2 and is_gray(float(m2.group(1)), float(m2.group(2)), float(m2.group(3))):
            findings.append((i, "gray pbr()", ln.strip()[:90]))
    # G1: primitive mesh created; check the next 25 lines for any material.
    for i, ln in enumerate(lines):
        m = re.search(r"\b(%s)\.new\(\)" % "|".join(PRIM_MESHES), ln)
        if not m:
            continue
        window = "\n".join(lines[i : i + 25])
        if not re.search(r"material_override|surface_material_override|material\s*=|quad\.material", window):
            findings.append((i + 1, "untextured primitive", ln.strip()[:90]))
    return findings


def audit_tscn(path: Path):
    findings = []
    src = path.read_text(errors="replace")
    # T1: StandardMaterial3D sub-resources.
    for m in re.finditer(
        r'\[sub_resource type="StandardMaterial3D" id="([^"]+)"\](.*?)(?=\n\[|\Z)',
        src, re.S,
    ):
        block = m.group(2)
        cm = re.search(r"albedo_color\s*=\s*Color\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)", block)
        if cm is None:
            # No albedo at all on a flat material read -> default look.
            if "emission_enabled" not in block:
                findings.append((0, "default-gray material", "sub_resource %s (no albedo)" % m.group(1)))
        elif is_gray(float(cm.group(1)), float(cm.group(2)), float(cm.group(3))):
            if "emission_enabled" not in block:  # emissive grays are intentional glow
                findings.append((0, "default-gray material", "sub_resource %s" % m.group(1)))
    # T2: MeshInstance3D nodes with a primitive mesh and no material anywhere.
    for m in re.finditer(
        r'\[node name="([^"]+)"[^\]]*type="MeshInstance3D"[^\]]*\](.*?)(?=\n\[node |\Z)',
        src, re.S,
    ):
        block = m.group(2)
        if re.search(r"surface_material_override|material_override", block):
            continue
        mesh = re.search(r"mesh\s*=\s*SubResource\(\"([^\"]+)\"\)", block)
        if mesh and any(p in src for p in []):
            pass
        # Only flag when the mesh sub-resource is a primitive type.
        if mesh:
            mid = mesh.group(1)
            mm = re.search(r'\[sub_resource type="(%s)" id="%s"\]' % ("|".join(PRIM_MESHES), re.escape(mid)), src)
            if mm:
                findings.append((0, "untextured primitive", "node %s" % m.group(1)))
    return findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["warn", "strict"], default="warn")
    args = ap.parse_args()

    all_findings = {}
    # .gd files from the game dirs (scripts/games, scripts/halloween)
    # plus top-level scripts/*.gd (hub, mano_magica).
    gd_files = []
    for d in GAME_DIRS:
        if d.is_dir():
            if d.name == "scripts":
                gd_files.extend(sorted(d.glob("*.gd")))
            else:
                gd_files.extend(sorted(d.rglob("*.gd")))
    for p in gd_files:
        f = audit_gd(p)
        if f:
            all_findings[str(p.relative_to(ROOT))] = f
    for p in sorted(SCENE_DIR.rglob("*.tscn")):
        f = audit_tscn(p)
        if f:
            all_findings[str(p.relative_to(ROOT))] = f

    total = sum(len(v) for v in all_findings.values())
    print("gray-primitive audit: %d files with findings, %d total" % (len(all_findings), total))
    for path in sorted(all_findings):
        print("  %s:" % path)
        for line_no, kind, snippet in all_findings[path][:8]:
            print("    L%-5s %-22s %s" % (line_no or "-", kind, snippet))
        if len(all_findings[path]) > 8:
            print("    ... and %d more" % (len(all_findings[path]) - 8))

    if args.mode == "strict" and total > 0:
        print("STRICT: failing the build (%d gray-primitive findings)" % total)
        return 1
    if total > 0:
        print("WARN: findings reported, not failing (flip to --strict after the art pass)")
    else:
        print("CLEAN: no gray-primitive findings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
