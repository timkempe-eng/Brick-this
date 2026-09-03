#!/usr/bin/env python3
"""Checks a rendered STL is something a printer can actually slice.

OpenSCAD will happily emit a mesh with holes in it if the model has
coincident faces or a zero-thickness wall, and a slicer's response to that is
not an error — it is a part with a missing side, discovered after four hours
on the bed. The two things worth asserting are cheap:

  * every edge is shared by exactly two triangles (the surface is closed);
  * the signed volume is positive (the normals point outward).

    python3 scripts/check_stl.py build/*.stl
"""
import struct
import sys
from collections import Counter
from pathlib import Path


def triangles(path: Path):
    """Yields (v0, v1, v2) from a binary or ASCII STL."""
    data = path.read_bytes()
    # A binary STL's header is 80 bytes, then a uint32 count. ASCII files start
    # with "solid", but so do some binary ones from bad exporters — so decide
    # on the length, which only fits for a genuine binary file.
    if len(data) >= 84:
        count = struct.unpack_from("<I", data, 80)[0]
        if len(data) == 84 + count * 50:
            for i in range(count):
                base = 84 + i * 50 + 12
                yield tuple(struct.unpack_from("<3f", data, base + j * 12) for j in range(3))
            return

    vertices = []
    for line in data.decode("utf-8", "replace").splitlines():
        parts = line.split()
        if parts[:1] == ["vertex"]:
            vertices.append(tuple(float(x) for x in parts[1:4]))
    for i in range(0, len(vertices) - 2, 3):
        yield tuple(vertices[i:i + 3])


def check(path: Path) -> bool:
    edges: Counter = Counter()
    volume = 0.0
    faces = 0

    for a, b, c in triangles(path):
        faces += 1
        # Rounded, because two triangles that meet along an edge must agree
        # about where it is, and float text round-trips through STL.
        key = [tuple(round(v, 5) for v in p) for p in (a, b, c)]
        for i in range(3):
            p, q = key[i], key[(i + 1) % 3]
            edges[(p, q) if p <= q else (q, p)] += 1
        volume += (
            a[0] * (b[1] * c[2] - b[2] * c[1])
            - a[1] * (b[0] * c[2] - b[2] * c[0])
            + a[2] * (b[0] * c[1] - b[1] * c[0])
        ) / 6.0

    problems = []
    if faces == 0:
        problems.append("no triangles at all")
    open_edges = [e for e, n in edges.items() if n != 2]
    if open_edges:
        problems.append(f"{len(open_edges)} edge(s) not shared by exactly two faces")
    if volume <= 0:
        problems.append(f"volume is {volume:.1f} mm³ — normals point inward")

    ml = volume / 1000
    print(f"{path.name}: {faces} triangles, {ml:.2f} ml"
          f" ({ml * 1.24:.0f} g in solid PLA)"
          + (" — FAILED: " + "; ".join(problems) if problems else " — closed"))
    return not problems


if __name__ == "__main__":
    paths = [Path(p) for p in sys.argv[1:]]
    if not paths:
        print(__doc__)
        sys.exit(2)
    sys.exit(0 if all([check(p) for p in paths]) else 1)
