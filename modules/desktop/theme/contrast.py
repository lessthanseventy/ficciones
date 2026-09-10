#!/usr/bin/env python3
"""Check one palette against the pair table in contrast.nix.

Usage: contrast.py <name> <pairs.json>   — exits 1 on any pair below its floor.
The JSON is `builtins.toJSON (import ./contrast.nix palette)`: groups of
{label, fg, bg, min, why?} plus the `hue` map the names resolve through.
"""
import json
import sys


def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hexcolor):
    r, g, b = (int(hexcolor[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def ratio(fg, bg):
    a, b = luminance(fg), luminance(bg)
    if a < b:
        a, b = b, a
    return (a + 0.05) / (b + 0.05)


def main():
    name, path = sys.argv[1], sys.argv[2]
    spec = json.load(open(path))
    hue = spec.pop("hue")
    failures = []
    print(f"── {name} " + "─" * (56 - len(name)))
    for group, pairs in spec.items():
        print(f"  {group}:")
        for p in pairs:
            fg, bg = hue[p["fg"]], hue[p["bg"]]
            r = ratio(fg, bg)
            ok = r >= p["min"] - 5e-3  # a pair sitting exactly on its floor passes
            print(f"    {'ok ' if ok else 'FAIL'}  {r:6.2f} (min {p['min']:.1f})  {p['label']}"
                  f"  #{fg} on #{bg}")
            if not ok:
                failures.append((p["label"], r, p["min"]))
    if failures:
        print(f"\n{name}: {len(failures)} pair(s) below the floor:", file=sys.stderr)
        for label, r, floor in failures:
            print(f"  {label}: {r:.2f} < {floor:.1f}", file=sys.stderr)
        return 1
    print(f"{name}: all pairs clear their floor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
