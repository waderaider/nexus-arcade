#!/usr/bin/env python3
## QA gate: contrast audit for NEXUS game UI text.
## Scans Label3D/UI text colors and computes WCAG contrast ratios vs a dark
## background (the common case). Flags anything below 4.5:1 (AA) or alpha<0.85.
## Usage: python3 tools/qa/contrast_audit.py
import re, glob, sys

def luminance(r, g, b):
    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)

def contrast(l1, l2):
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)

issues = []
files = glob.glob("scripts/games/*/*.gd") + glob.glob("scripts/shared/*.gd")
for f in files:
    s = open(f).read()
    for m in re.finditer(
        r'(modulate|font_color)\s*=\s*Color\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)', s):
        r, g, b = float(m.group(2)), float(m.group(3)), float(m.group(4))
        a = float(m.group(5)) if m.group(5) else 1.0
        cr = contrast(luminance(r, g, b), 0.02)
        # Skip pure-black (usually outlines/panels, not text).
        if r == 0 and g == 0 and b == 0:
            continue
        if cr < 4.5 or a < 0.85:
            issues.append((f, m.group(0)[:70], cr, a))

print("Contrast issues (vs dark bg, WCAG AA = 4.5:1):")
for f, txt, cr, a in issues:
    print("  %.1f:1 alpha=%.2f %-28s %s" % (cr, a, f.split("/")[-1], txt))
print("total: %d" % len(issues))
sys.exit(1 if issues else 0)
