#!/usr/bin/env python3
"""Generates the custom Japanese-style platform model (mesh, materials, textures, .mdl).

Writes jpst_station/content/stations/jpst/perron/. The pedestrian-lane metadata is copied from the vanilla
era-C perron_5.mdl, so the game must be installed. Meshes use the TF3 .msh/.msh.blob format (little-endian
floats; every offset and count is in bytes; one uint32 index list per attribute and submesh).
"""
import math
import re
import struct
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fbx_read

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "jpst_station/content/stations/jpst/perron"
GAME = Path.home() / "Library/Application Support/Steam/steamapps/common/Transport Fever 3/base/content"

LENGTH = 40.0
HALF = 2.5          # half width of the platform (same envelope as the vanilla perron_5)
TOP = 1.1           # platform surface height above the track bed
EDGE = 0.4          # bright concrete strip between the platform edge and the tactile paving
BLOCK = 0.3         # tactile paving width (JIS T 9251 guideline: about 30 cm)
EDGE_FBX = ROOT / "model/platform_edge.fbx"   # hand-made edge piece (20 m, outer lip at y=-0.6, inner side y=0)
BASE_FBX = ROOT / "model/platform_base.fbx"   # hand-made platform body (20 m x 4 m, top at z=1.1)
BASE_W = 4.0
EDGE_PIECE_L = 20.0
EDGE_PIECE_W = 0.6
FLOOR_TILE = 1.2    # floor texture repeat (m)
EDGE_TILE = 1.0     # concrete texture repeat (m)


# ---------------------------------------------------------------- textures

def write_tga(path, w, h, rows):
    """rows[y][x] = (r, g, b); 24 bit uncompressed, top-left origin."""
    path.parent.mkdir(parents=True, exist_ok=True)
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 24, 0x20)
    data = bytearray()
    for row in rows:
        for r, g, b in row:
            data += bytes((b, g, r))
    path.write_bytes(hdr + bytes(data))


def normal_from_height(hmap, strength):
    n = len(hmap)
    rows = []
    for y in range(n):
        row = []
        for x in range(n):
            dx = hmap[y][(x + 1) % n] - hmap[y][(x - 1) % n]
            dy = hmap[(y + 1) % n][x] - hmap[(y - 1) % n][x]
            nx, ny, nz = -dx * strength, -dy * strength, 1.0
            l = math.sqrt(nx * nx + ny * ny + nz * nz)
            row.append(tuple(int(round((c / l * 0.5 + 0.5) * 255)) for c in (nx, ny, nz)))
        rows.append(row)
    return rows


def hash01(a, b):
    v = (a * 73856093) ^ (b * 19349663)
    v = (v * 2654435761) & 0xFFFFFFFF
    return ((v >> 8) & 0xFFFF) / 65535.0


def tex_floor(n=128):
    """2x2 concrete pavers, a few percent of shade variation, dark joints."""
    alb, hm, mga = [], [], []
    half = n // 2
    for y in range(n):
        ra, rh, rm = [], [], []
        for x in range(n):
            tx, ty = x % half, y % half
            joint = tx < 2 or ty < 2
            shade = 0.9 + 0.1 * hash01(x // half, y // half)
            c = int((150 if not joint else 95) * shade)
            ra.append((c, c, c - 2))
            rh.append(0.0 if joint else 1.0)
            rm.append((0, 70, 255))
        alb.append(ra)
        hm.append(rh)
        mga.append(rm)
    return alb, normal_from_height(hm, 1.5), mga


def tex_edge(n=64):
    alb, hm, mga = [], [], []
    for y in range(n):
        ra, rh, rm = [], [], []
        for x in range(n):
            c = 205 + int(12 * hash01(x, y))
            ra.append((c, c, c - 4))
            rh.append(0.0)
            rm.append((0, 60, 255))
        alb.append(ra)
        hm.append(rh)
        mga.append(rm)
    return alb, normal_from_height(hm, 1.0), mga


def tex_yellow(n=64):
    """One 30 cm x 30 cm block: u across (outer -> inner), v along the platform.
    Dotted paving over the outer 0.75 of the width plus a continuous bar on the inner side (内方線付き点状ブロック)."""
    alb, hm, mga = [], [], []
    pitch = n // 4
    for y in range(n):
        ra, rh, rm = [], [], []
        for x in range(n):
            height = 0.0
            if x < 48:
                cx, cy = (x // 16) * 16 + 8, (y // pitch) * pitch + pitch // 2
                d = math.hypot(x - cx, y - cy)
                if d < 5.5:
                    height = math.cos(d / 5.5 * math.pi / 2) ** 0.5
            elif 52 <= x <= 59:
                height = 0.8
            base = (236, 190, 20)
            c = tuple(min(255, int(v * (0.86 + 0.14 * height))) for v in base)
            ra.append(c)
            rh.append(height)
            rm.append((0, 90, 255))
        alb.append(ra)
        hm.append(rh)
        mga.append(rm)
    return alb, normal_from_height(hm, 4.0), mga


def _png_set(paths):
    from PIL import Image

    def rows(img):
        w, h = img.size
        px = img.load()
        return [[px[x, y] for x in range(w)] for y in range(h)]
    alb = Image.open(paths[0]).convert("RGB")
    nrm = Image.open(paths[1]).convert("RGB")
    rgh = Image.open(paths[2]).convert("L").resize(alb.size)
    rp = rgh.load()
    w, h = alb.size
    mga = [[(0, 255 - rp[x, y], 255) for x in range(w)] for y in range(h)]
    return rows(alb), rows(nrm), mga


def tex_edge_piece():
    """Textures from model/platform_edge_{albedo,normal,roughness}.png; plain concrete until the files exist."""
    paths = [ROOT / f"model/platform_edge_{k}.png" for k in ("albedo", "normal", "roughness")]
    return _png_set(paths) if all(q.exists() for q in paths) else tex_edge()


def tex_base_piece():
    """Same as tex_edge_piece for model/platform_base_*.png; falls back to the generic platform floor."""
    paths = [ROOT / f"model/platform_base_{k}.png" for k in ("albedo", "normal", "roughness")]
    if not all(q.exists() for q in paths):
        return tex_floor()
    return _png_set(paths)


def write_texture_set(name, tex):
    alb, nrm, mga = tex
    d = OUT / "mat/tex"
    write_tga(d / f"{name}_albedo.tga", len(alb[0]), len(alb), alb)
    write_tga(d / f"{name}_normal.tga", len(nrm[0]), len(nrm), nrm)
    write_tga(d / f"{name}_mga.tga", len(mga[0]), len(mga), mga)


MTL = """function data()
return {
	__version = "",
	order = 0,
	params = {
		light_receiver = {
			fragmentProperties = {
				{
					isLegacyMaterial = false,
					lightMask = 2,
				},
			},
		},
		map_albedo = {
			fragmentSamplers = {
				albedoTex = {
					fileName = "tex/%(n)s_albedo.tga",
					type = "TWOD",
					wrapS = "REPEAT",
					wrapT = "REPEAT",
				},
			},
		},
		map_metal_gloss_ao = {
			fragmentSamplers = {
				metalGlossAoTex = {
					fileName = "tex/%(n)s_mga.tga",
					type = "TWOD",
					wrapS = "REPEAT",
					wrapT = "REPEAT",
				},
			},
		},
		map_normal = {
			fragmentSamplers = {
				normalTex = {
					fileName = "tex/%(n)s_normal.tga",
					redGreen = true,
					type = "TWOD",
					wrapS = "REPEAT",
					wrapT = "REPEAT",
				},
			},
		},
		texcoord_scale = {
			fragmentProperties = {
				{
					texCoordScale = 1,
				},
			},
		},
	},
	type = "PHYSICAL_NRML_MAP",
}
end
"""


# ---------------------------------------------------------------- mesh

class Mesh:
    def __init__(self):
        self.pos, self.uv, self.nrm, self.tan = [], [], [], []
        self.subs = []  # list of index lists (one per submesh)

    def submesh(self):
        self.subs.append([])

    def quad(self, p, uv, normal, tangent):
        """p: 4 corners counter-clockwise seen from the normal side; uv: 4 pairs."""
        base = len(self.pos)
        for i in range(4):
            self.pos.append(p[i])
            self.uv.append(uv[i])
            self.nrm.append(normal)
            self.tan.append(tangent + (1.0,))
        self.subs[-1] += [base, base + 1, base + 2, base, base + 2, base + 3]

    def write(self, mshpath):
        blob = bytearray()
        attrs = {}
        for name, data, comp in (("position", self.pos, 3), ("uv0", self.uv, 2),
                                 ("normal", self.nrm, 3), ("tangent", self.tan, 4)):
            off = len(blob)
            for item in data:
                blob += struct.pack("<%df" % comp, *item)
            attrs[name] = (off, len(blob) - off, comp)
        sub_text = []
        for idx in self.subs:
            lists = {}
            for name in ("position", "uv0", "normal", "tangent"):
                off = len(blob)
                blob += struct.pack("<%dI" % len(idx), *idx)
                lists[name] = (off, len(idx) * 4)
            sub_text.append(lists)
        out = ["function data()", "return {", "\tsubMeshes = {"]
        for lists in sub_text:
            out.append("\t\t{\n\t\t\tindices = {")
            for name, (off, size) in sorted(lists.items()):
                out.append(f"\t\t\t\t{name} = {{ count = {size}, offset = {off}, }},")
            out.append("\t\t\t},\n\t\t},")
        out.append("\t},\n\tvertexAttr = {")
        for name, (off, size, comp) in sorted(attrs.items()):
            out.append(f"\t\t{name} = {{ count = {size}, numComp = {comp}, offset = {off}, }},")
        out.append("\t},\n}\nend\n")
        mshpath.parent.mkdir(parents=True, exist_ok=True)
        mshpath.write_text("\n".join(out))
        Path(str(mshpath) + ".blob").write_bytes(bytes(blob))


HOLE_W = 1.1        # half width of a stairwell opening
HOLE_L = 4.5        # length of a stairwell opening
HOLE_X = (10.5, 25.0)  # start of the two openings (each descends toward the cell centre, x = LENGTH / 2)
STEPS = 8
STEP_DROP = 0.13


def stair_well(m, x0, d, yc=0.0):
    """Stairwell below the floor opening starting at x0; d = +1 descends toward +x, -1 toward -x."""
    H, T = HOLE_W, TOP
    ya, yb2 = yc - H, yc + H
    sl = HOLE_L / STEPS

    def q(pts, nrm, tan):
        # mirror for d = -1: x -> 2*x0 + HOLE_L - x, reverse the winding
        if d < 0:
            pts = [(2 * x0 + HOLE_L - x, y, z) for x, y, z in pts][::-1]
            nrm = (-nrm[0], nrm[1], nrm[2])
            tan = (-tan[0], tan[1], tan[2])
        uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
        m.quad(pts, uv, nrm, tan)

    bottom = T - STEPS * STEP_DROP
    for s_, ny in ((1, -1), (-1, 1)):
        y = yc + s_ * H
        pts = [(x0, y, bottom), (x0 + HOLE_L, y, bottom), (x0 + HOLE_L, y, T), (x0, y, T)]
        if ny == 1:
            pts = [pts[1], pts[0], pts[3], pts[2]]
            q(pts, (0, 1, 0), (-1, 0, 0))
        else:
            q(pts, (0, -1, 0), (1, 0, 0))
    q([(x0 + HOLE_L, ya, bottom), (x0 + HOLE_L, ya, T), (x0 + HOLE_L, yb2, T), (x0 + HOLE_L, yb2, bottom)],
      (-1, 0, 0), (0, 1, 0))
    for i in range(STEPS):
        xa, xb = x0 + i * sl, x0 + (i + 1) * sl
        z = T - (i + 1) * STEP_DROP
        q([(xa, ya, z), (xb, ya, z), (xb, yb2, z), (xa, yb2, z)], (0, 0, 1), (1, 0, 0))
        q([(xa, ya, z), (xa, ya, z + STEP_DROP), (xa, yb2, z + STEP_DROP), (xa, yb2, z)], (-1, 0, 0), (0, 1, 0))


# Which platform edges face a track: (mesh +y, mesh -y). The edge without a track gets no concrete strip
# and no tactile paving. Models for the other combinations carry a suffix.
SIDE_SUFFIX = {(True, True): "", (True, False): "_p", (False, True): "_m", (False, False): "_n"}



# ---------------------------------------------------------------- imported edge piece

def load_edge_piece(path=EDGE_FBX):
    """Triangles ((pos, uv) x3) of an FBX piece, or None when the file is missing."""
    if not path.exists():
        return None
    g = fbx_read.geometries(str(path))[0]
    uvs, uvidx = g["uvl"]
    tris, k = [], 0
    for poly in g["polys"]:
        corners = []
        for vi in poly:
            u = uvidx[k] if uvidx else k
            corners.append((g["pos"][vi], (uvs[2 * u], uvs[2 * u + 1])))
            k += 1
        for i in range(1, len(corners) - 1):
            tris.append((corners[0], corners[i], corners[i + 1]))
    return tris


def add_edge_piece(m, tris, cx, side, H):
    """Adds one copy of the edge piece centred at x=cx on the +y (side=1) or -y (side=-1) platform edge."""
    add_piece(m, tris, cx, lambda y: (H - EDGE_PIECE_W - y) if side == 1 else (-H + EDGE_PIECE_W + y), side == 1)


def _clip(poly, axis, val, keep_low):
    """Sutherland-Hodgman clip of a polygon [(pos, uv)] to pos[axis] <= val (keep_low) or >= val."""
    def inside(v):
        return v[0][axis] <= val if keep_low else v[0][axis] >= val
    out = []
    for i, cur in enumerate(poly):
        prv = poly[i - 1]
        if inside(cur) != inside(prv):
            t = (val - prv[0][axis]) / (cur[0][axis] - prv[0][axis])
            out.append((tuple(prv[0][k] + t * (cur[0][k] - prv[0][k]) for k in range(3)),
                        tuple(prv[1][k] + t * (cur[1][k] - prv[1][k]) for k in range(2))))
        if inside(cur):
            out.append(cur)
    return out


def _minus_rect(poly, rect):
    """Pieces of a convex polygon outside rect = (xa, xb, ya, yb)."""
    xa, xb, ya, yb = rect
    pieces = []
    rest = poly
    for axis, val, low in ((0, xa, True), (0, xb, False), (1, ya, True), (1, yb, False)):
        if len(rest) < 3:
            break
        out = _clip(rest, axis, val, low)
        if len(out) >= 3:
            pieces.append(out)
        rest = _clip(rest, axis, val, not low)
    return pieces


def add_piece(m, tris, cx, ymap, flip, holes=()):
    """Adds a piece shifted to x=cx with its y coordinates remapped by ymap (flip when ymap mirrors).
    holes: rectangles (xa, xb, ya, yb) in final coordinates that are cut out of the piece."""
    polys = []
    for tri in tris:
        pts = []
        for (x, y, z), uv in tri:
            pts.append(((x + cx, ymap(y), z), uv))
        if flip:
            pts = [pts[0], pts[2], pts[1]]  # mirroring flips the winding
        cur = [pts]
        for r in holes:
            cur = [q for poly in cur for q in _minus_rect(poly, r)]
        polys += cur
    for poly in polys:
      for i in range(1, len(poly) - 1):
        pts = [poly[0], poly[i], poly[i + 1]]
        (a, ua), (b, ub), (c, uc) = pts
        e1 = [b[i] - a[i] for i in range(3)]
        e2 = [c[i] - a[i] for i in range(3)]
        n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        nl = math.sqrt(sum(v * v for v in n))
        if nl < 1e-12:
            continue
        n = tuple(v / nl for v in n)
        du1, dv1 = ub[0] - ua[0], ub[1] - ua[1]
        du2, dv2 = uc[0] - ua[0], uc[1] - ua[1]
        det = du1 * dv2 - du2 * dv1
        if abs(det) < 1e-12:
            t = (1.0, 0.0, 0.0)
        else:
            t = tuple((e1[i] * dv2 - e2[i] * dv1) / det for i in range(3))
            tl = math.sqrt(sum(v * v for v in t)) or 1.0
            t = tuple(v / tl for v in t)
        base = len(m.pos)
        for (pos, uv) in pts:
            m.pos.append(pos)
            m.uv.append(uv)
            m.nrm.append(n)
            m.tan.append(t + (1.0,))
        m.subs[-1] += [base, base + 1, base + 2]


def build_platform_mesh(stairs=False, half=HALF, yc=0.0, sides=(True, True)):
    m = Mesh()
    L, H, T = LENGTH, half, TOP
    ye = H - EDGE            # inner limit of the bright concrete strip
    yb = ye - BLOCK          # inner limit of the tactile paving
    edge_tris = load_edge_piece()
    if edge_tris:
        top = H - EDGE_PIECE_W if sides[0] else H
        bot = -(H - EDGE_PIECE_W) if sides[1] else -H
    else:
        top = yb if sides[0] else H
        bot = -yb if sides[1] else -H

    base_tris = load_edge_piece(BASE_FBX) if edge_tris else None
    # 0: floor
    m.submesh()

    def floor(xa, xb, ya, yb_):
        m.quad([(xa, ya, T), (xb, ya, T), (xb, yb_, T), (xa, yb_, T)],
               [(xa / FLOOR_TILE, ya / FLOOR_TILE), (xb / FLOOR_TILE, ya / FLOOR_TILE),
                (xb / FLOOR_TILE, yb_ / FLOOR_TILE), (xa / FLOOR_TILE, yb_ / FLOOR_TILE)], (0, 0, 1), (1, 0, 0))
    if base_tris:
        m.quad([(0, 0, 0), (0.1, 0, 0), (0.1, 0.1, 0), (0, 0.1, 0)], [(0, 0)] * 4, (0, 0, 1), (1, 0, 0))
    elif stairs:
        cur = 0.0
        for hx in HOLE_X:
            floor(cur, hx, bot, top)
            floor(hx, hx + HOLE_L, yc + HOLE_W, top)
            floor(hx, hx + HOLE_L, bot, yc - HOLE_W)
            cur = hx + HOLE_L
        floor(cur, L, bot, top)
    else:
        floor(0, L, bot, top)
    # 1: bright concrete strips on both edges + both side walls
    m.submesh()
    for s in (1, -1):
        if not sides[0 if s == 1 else 1] or edge_tris:
            continue
        y0, y1 = (ye, H) if s == 1 else (-H, -ye)
        m.quad([(0, y0, T), (L, y0, T), (L, y1, T), (0, y1, T)],
               [(0, y0 / EDGE_TILE), (L / EDGE_TILE, y0 / EDGE_TILE),
                (L / EDGE_TILE, y1 / EDGE_TILE), (0, y1 / EDGE_TILE)], (0, 0, 1), (1, 0, 0))
    if not (edge_tris and sides[0]):
        m.quad([(L, H, 0), (0, H, 0), (0, H, T), (L, H, T)],
               [(0, 0), (L / EDGE_TILE, 0), (L / EDGE_TILE, T / EDGE_TILE), (0, T / EDGE_TILE)], (0, 1, 0), (-1, 0, 0))
    if not (edge_tris and sides[1]):
        m.quad([(0, -H, 0), (L, -H, 0), (L, -H, T), (0, -H, T)],
               [(0, 0), (L / EDGE_TILE, 0), (L / EDGE_TILE, T / EDGE_TILE), (0, T / EDGE_TILE)], (0, -1, 0), (1, 0, 0))
    if edge_tris and all(sides):
        m.quad([(0, 0, 0), (0.1, 0, 0), (0.1, 0.1, 0), (0, 0.1, 0)], [(0, 0)] * 4, (0, 0, 1), (1, 0, 0))
    # 2: tactile paving; u runs from the outer edge to the platform inside, v along x
    m.submesh()
    n = L / BLOCK
    if edge_tris:
        sides_t = (False, False)
    else:
        sides_t = sides
    if sides_t[0]:
        m.quad([(0, yb, T), (L, yb, T), (L, ye, T), (0, ye, T)],
               [(1, 0), (1, n), (0, n), (0, 0)], (0, 0, 1), (0, -1, 0))
    if sides_t[1]:
        m.quad([(0, -ye, T), (L, -ye, T), (L, -yb, T), (0, -yb, T)],
               [(0, 0), (0, n), (1, n), (1, 0)], (0, 0, 1), (0, 1, 0))
    if not any(sides_t):
        # keep the submesh non-empty; the quad is buried inside the platform
        m.quad([(0, 0, 0), (0.1, 0, 0), (0.1, 0.1, 0), (0, 0.1, 0)], [(0, 0)] * 4, (0, 0, 1), (1, 0, 0))
    if edge_tris:
        # 3: the hand-made edge piece (outer lip, bright strip and tactile paving), two 20 m copies per side
        m.submesh()
        for side in (1, -1):
            if sides[0 if side == 1 else 1]:
                for cx in (EDGE_PIECE_L / 2, L - EDGE_PIECE_L / 2):
                    add_edge_piece(m, edge_tris, cx, side, H)
        if not m.subs[-1]:
            m.quad([(0, 0, 0), (0.1, 0, 0), (0.1, 0.1, 0), (0, 0.1, 0)], [(0, 0)] * 4, (0, 0, 1), (1, 0, 0))
    if edge_tris and BASE_FBX.exists():
        # 4: the hand-made body, squeezed in y to fill the space between the edge pieces (stairwell openings are cut out)
        m.submesh()
        k, mid = (top - bot) / BASE_W, (top + bot) / 2
        holes = [(hx, hx + HOLE_L, yc - HOLE_W, yc + HOLE_W) for hx in HOLE_X] if stairs else []
        for cx in (EDGE_PIECE_L / 2, L - EDGE_PIECE_L / 2):
            if base_tris:
                add_piece(m, base_tris, cx, lambda y: mid + y * k, False, holes)
        if not base_tris:
            m.quad([(0, 0, 0), (0.1, 0, 0), (0.1, 0.1, 0), (0, 0.1, 0)], [(0, 0)] * 4, (0, 0, 1), (1, 0, 0))
    return m


RAIL_H = 0.95       # handrail height above the floor
WALL_H = 0.4        # solid kerb under the handrail (also makes the module easy to pick)
WALL_T = 0.12


def box(m, x0, x1, y0, y1, z0, z1):
    for pts, nrm, tan in (
            ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1), (1, 0, 0)),
            ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0), (1, 0, 0)),
            ([(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)], (0, 1, 0), (-1, 0, 0)),
            ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0), (0, 1, 0)),
            ([(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)], (-1, 0, 0), (0, -1, 0))):
        m.quad(pts, [(0, 0), (1, 0), (1, 1), (0, 1)], nrm, tan)


def railing(m, x0, d):
    """Kerb, posts and handrails around the two long sides and the far end of a stairwell."""
    T = TOP
    xa, xb = x0, x0 + HOLE_L
    far = xb if d > 0 else xa
    ex = (far, far + WALL_T) if d > 0 else (far - WALL_T, far)
    for s_ in (1, -1):
        ya, yb = (HOLE_W, HOLE_W + WALL_T) if s_ > 0 else (-HOLE_W - WALL_T, -HOLE_W)
        box(m, xa, xb + (WALL_T if d > 0 else 0), ya, yb, T, T + WALL_H)
        box(m, xa - (0 if d > 0 else WALL_T), xb, ya, yb, T, T + WALL_H)
        box(m, xa, xb, ya + 0.03, yb - 0.03, T + RAIL_H - 0.05, T + RAIL_H)
        for i in range(4):
            px = xa + 0.06 + i * (HOLE_L - 0.12) / 3
            box(m, px - 0.03, px + 0.03, ya + 0.03, yb - 0.03, T + WALL_H, T + RAIL_H)
    box(m, ex[0], ex[1], -HOLE_W, HOLE_W, T, T + WALL_H)
    box(m, far - 0.03 if d > 0 else far - 0.03, far + 0.03, -HOLE_W, HOLE_W, T + RAIL_H - 0.05, T + RAIL_H)


def build_stairwell_mesh():
    m = Mesh()
    m.submesh()
    stair_well(m, HOLE_X[0], 1)
    stair_well(m, HOLE_X[1], -1)
    m.submesh()
    railing(m, HOLE_X[0], 1)
    railing(m, HOLE_X[1], -1)
    return m


def build_stairwell_mdl(mat):
    """Walls and steps of both stairwells; a collider slightly above the floor lets the player pick the module."""
    x0, x1 = HOLE_X[0], HOLE_X[1] + HOLE_L
    hx, hy, hz = (x1 - x0) / 2, HOLE_W, RAIL_H / 2
    cz = TOP + hz
    return f"""-- Generated by tools/gen_models.py; do not edit by hand.
function data()
return {{
\t\tboundingInfo = {{
\t\t\tbbMax = {{ {x1}, {HOLE_W}, {TOP + RAIL_H}, }},
\t\t\tbbMin = {{ {x0}, {-HOLE_W}, {TOP - STEPS * STEP_DROP}, }},
\t\t}},
\t\tcollider = {{
\t\t\tparams = {{
\t\t\t\thalfExtents = {{ {hx}, {hy}, {hz}, }},
\t\t\t}},
\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, {(x0 + x1) / 2}, 0, {cz}, 1, }},
\t\t\ttype = "BOX",
\t\t}},
\t\tlods = {{
\t\t\t{{
\t\t\t\tnode = {{
\t\t\t\t\tchildren = {{
\t\t\t\t\t\t{{
\t\t\t\t\t\t\tmaterials = {{ "mat/{mat}.mtl", "mat/{mat}.mtl", }},
\t\t\t\t\t\t\tmesh = "msh/jpst_stairwell_lod0.msh",
\t\t\t\t\t\t\tname = "stairwell",
\t\t\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t\t\t}},
\t\t\t\t\t}},
\t\t\t\t\tname = "RootNode",
\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t}},
\t\t\t\tvisibleFrom = 0,
\t\t\t\tvisibleTo = 3000,
\t\t\t}},
\t\t}},
\t\tmetadata = {{ }},
\t\tversion = 2,
\t}}
end
"""


def vanilla_mdl(name="perron_5"):
    with zipfile.ZipFile(GAME / "stations/rail.zip") as z:
        return z.read(f"rail/era_c/{name}.mdl").decode()


def build_mdl(vanilla, mtls, mesh="jpst_perron_5_lod0", name="perron_5"):
    head = vanilla[:vanilla.index("\t\tlods = {")]
    tail = vanilla[vanilla.index("\t\tmetadata = {"):]
    mats = ", ".join(f'"mat/{m}.mtl"' for m in mtls)
    lod = f"""\t\tlods = {{
\t\t\t{{
\t\t\t\tnode = {{
\t\t\t\t\tchildren = {{
\t\t\t\t\t\t{{
\t\t\t\t\t\t\tmaterials = {{ {mats}, }},
\t\t\t\t\t\t\tmesh = "msh/{mesh}.msh",
\t\t\t\t\t\t\tname = "{name}",
\t\t\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t\t\t}},
\t\t\t\t\t}},
\t\t\t\t\tname = "RootNode",
\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t}},
\t\t\t\tvisibleFrom = 0,
\t\t\t\tvisibleTo = 3000,
\t\t\t}},
\t\t}},
"""
    return "-- Generated by tools/gen_models.py; do not edit by hand.\n" + head + lod + tail


DECK_THICK = 0.8    # concourse / deck slab thickness


def tex_concourse(n=64):
    """Plain light-grey floor with soft speckle (the slab is stretched, so no joints)."""
    alb, hm, mga = [], [], []
    for y in range(n):
        ra, rh, rm = [], [], []
        for x in range(n):
            c = 178 + int(14 * hash01(x, y)) + int(6 * hash01(x // 4, y // 4))
            ra.append((c, c, c - 3))
            rh.append(0.0)
            rm.append((0, 55, 255))
        alb.append(ra)
        hm.append(rh)
        mga.append(rm)
    return alb, normal_from_height(hm, 1.0), mga


def build_deck_mesh():
    """6 x 4 m slab (X 0..6, Y 0..4, top at z=0); stretched by the scripts like the vanilla deck piece."""
    m = Mesh()
    m.submesh()
    m.quad([(0, 0, 0), (6, 0, 0), (6, 4, 0), (0, 4, 0)], [(0, 0), (2, 0), (2, 1.5), (0, 1.5)], (0, 0, 1), (1, 0, 0))
    m.submesh()
    z0 = -DECK_THICK
    for pts, nrm, tan in (
            ([(0, 0, z0), (0, 4, z0), (6, 4, z0), (6, 0, z0)], (0, 0, -1), (0, 1, 0)),
            ([(0, 0, z0), (6, 0, z0), (6, 0, 0), (0, 0, 0)], (0, -1, 0), (1, 0, 0)),
            ([(6, 4, z0), (0, 4, z0), (0, 4, 0), (6, 4, 0)], (0, 1, 0), (-1, 0, 0)),
            ([(6, 0, z0), (6, 4, z0), (6, 4, 0), (6, 0, 0)], (1, 0, 0), (0, 1, 0)),
            ([(0, 4, z0), (0, 0, z0), (0, 0, 0), (0, 4, 0)], (-1, 0, 0), (0, -1, 0))):
        m.quad(pts, [(0, 0), (1, 0), (1, 0.3), (0, 0.3)], nrm, tan)
    return m


def build_deck_mdl():
    t = DECK_THICK
    return f"""-- Generated by tools/gen_models.py; do not edit by hand.
function data()
return {{
\t\tboundingInfo = {{
\t\t\tbbMax = {{ 6, 4, 0, }},
\t\t\tbbMin = {{ 0, 0, {-t}, }},
\t\t}},
\t\tcollider = {{
\t\t\tparams = {{
\t\t\t\thalfExtents = {{ 3, 2, {t / 2}, }},
\t\t\t}},
\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 3, 2, {-t / 2}, 1, }},
\t\t\ttype = "BOX",
\t\t}},
\t\tlods = {{
\t\t\t{{
\t\t\t\tnode = {{
\t\t\t\t\tchildren = {{
\t\t\t\t\t\t{{
\t\t\t\t\t\t\tmaterials = {{ "mat/jpst_concourse_floor.mtl", "mat/jpst_platform_edge.mtl", }},
\t\t\t\t\t\t\tmesh = "msh/jpst_deck_lod0.msh",
\t\t\t\t\t\t\tname = "deck",
\t\t\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t\t\t}},
\t\t\t\t\t}},
\t\t\t\t\tname = "RootNode",
\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t}},
\t\t\t\tvisibleFrom = 0,
\t\t\t\tvisibleTo = 3000,
\t\t\t}},
\t\t}},
\t\tmetadata = {{ }},
\t\tversion = 2,
\t}}
end
"""


def build_gate_mesh():
    """Ticket gate line across a 3 m walkway (X -1.5..1.5, passes along Y): two machines, a 1.1 m
    wide passage between them and a fence on each outer side."""
    m = Mesh()
    m.submesh()
    for cx in (-0.75, 0.75):
        box(m, cx - 0.2, cx + 0.2, -0.6, 0.6, 0.0, 0.95)
    for x0, x1 in ((-1.5, -0.95), (0.95, 1.5)):
        box(m, x0, x1, -0.03, 0.03, 0.0, 1.0)
    m.submesh()
    for cx in (-0.75, 0.75):
        box(m, cx - 0.2, cx + 0.2, -0.6, 0.6, 0.95, 1.0)
    return m


def build_gate_mdl():
    return f"""-- Generated by tools/gen_models.py; do not edit by hand.
function data()
return {{
\t\tboundingInfo = {{
\t\t\tbbMax = {{ 1.5, 0.6, 1.0, }},
\t\t\tbbMin = {{ -1.5, -0.6, 0, }},
\t\t}},
\t\tcollider = {{
\t\t\tparams = {{
\t\t\t\thalfExtents = {{ 1.5, 0.6, 0.5, }},
\t\t\t}},
\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0.5, 1, }},
\t\t\ttype = "BOX",
\t\t}},
\t\tlods = {{
\t\t\t{{
\t\t\t\tnode = {{
\t\t\t\t\tchildren = {{
\t\t\t\t\t\t{{
\t\t\t\t\t\t\tmaterials = {{ "mat/jpst_platform_edge.mtl", "mat/jpst_platform_tactile.mtl", }},
\t\t\t\t\t\t\tmesh = "msh/jpst_gate_lod0.msh",
\t\t\t\t\t\t\tname = "gate",
\t\t\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t\t\t}},
\t\t\t\t\t}},
\t\t\t\t\tname = "RootNode",
\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t}},
\t\t\t\tvisibleFrom = 0,
\t\t\t\tvisibleTo = 3000,
\t\t\t}},
\t\t}},
\t\tmetadata = {{ }},
\t\tversion = 2,
\t}}
end
"""


DOOR_Y = 0.1        # inset of the door line from the platform edge
DOOR_H = 1.5        # door height above the platform surface
DOOR_PERIOD = 4.0   # one panel (2.8 m) plus one opening (1.2 m)


def tex_pdoor(n=32):
    alb, hm, mga = [], [], []
    for y in range(n):
        ra, rh, rm = [], [], []
        for x in range(n):
            c = 52 + int(8 * hash01(x, y))
            ra.append((c, c + 6, c + 14))
            rh.append(0.0)
            rm.append((140, 200, 255))
        alb.append(ra)
        hm.append(rh)
        mga.append(rm)
    return alb, normal_from_height(hm, 0.5), mga


def build_pdoor_mesh(half, sides=(True, True)):
    """Platform screen doors along both edges: glass panels with a 1.2 m opening every 4 m, white posts and top rail."""
    m = Mesh()
    m.submesh()  # panels
    z0, z1 = TOP + 0.15, TOP + DOOR_H - 0.12
    for sgn in [x for x, on in zip((1, -1), sides) if on]:
        ya, yb = sorted((sgn * (half - DOOR_Y), sgn * (half - DOOR_Y - 0.06)))
        for i in range(int(LENGTH / DOOR_PERIOD)):
            x0 = i * DOOR_PERIOD + 0.7
            box(m, x0 + 0.1, x0 + 2.7, ya, yb, z0, z1)
    m.submesh()  # frame
    for sgn in [x for x, on in zip((1, -1), sides) if on]:
        ya, yb = sorted((sgn * (half - DOOR_Y + 0.02), sgn * (half - DOOR_Y - 0.1)))
        for i in range(int(LENGTH / DOOR_PERIOD)):
            x0 = i * DOOR_PERIOD + 0.7
            box(m, x0, x0 + 0.1, ya, yb, TOP, TOP + DOOR_H)
            box(m, x0 + 2.7, x0 + 2.8, ya, yb, TOP, TOP + DOOR_H)
            box(m, x0 + 0.1, x0 + 2.7, ya, yb, TOP + DOOR_H - 0.12, TOP + DOOR_H)
            box(m, x0 + 0.1, x0 + 2.7, ya, yb, TOP, TOP + 0.15)
    return m


def build_pdoor_mdl(name, half, sides=(True, True)):
    cy = (half - DOOR_Y - 0.05) * (1 if sides[0] or not sides[1] else -1)
    return f"""-- Generated by tools/gen_models.py; do not edit by hand.
function data()
return {{
\t\tboundingInfo = {{
\t\t\tbbMax = {{ {LENGTH}, {half}, {TOP + DOOR_H}, }},
\t\t\tbbMin = {{ 0, {-half}, {TOP}, }},
\t\t}},
\t\tcollider = {{
\t\t\tparams = {{
\t\t\t\thalfExtents = {{ {LENGTH / 2}, 0.25, {DOOR_H / 2}, }},
\t\t\t}},
\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, {LENGTH / 2}, {cy}, {TOP + DOOR_H / 2}, 1, }},
\t\t\ttype = "BOX",
\t\t}},
\t\tlods = {{
\t\t\t{{
\t\t\t\tnode = {{
\t\t\t\t\tchildren = {{
\t\t\t\t\t\t{{
\t\t\t\t\t\t\tmaterials = {{ "mat/jpst_pdoor.mtl", "mat/jpst_platform_edge.mtl", }},
\t\t\t\t\t\t\tmesh = "msh/{name}_lod0.msh",
\t\t\t\t\t\t\tname = "pdoor",
\t\t\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t\t\t}},
\t\t\t\t\t}},
\t\t\t\t\tname = "RootNode",
\t\t\t\t\ttransf = {{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, }},
\t\t\t\t}},
\t\t\t\tvisibleFrom = 0,
\t\t\t\tvisibleTo = 3000,
\t\t\t}},
\t\t}},
\t\tmetadata = {{ }},
\t\tversion = 2,
\t}}
end
"""


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    textures = {"jpst_platform_floor": tex_floor(), "jpst_platform_edge": tex_edge(),
                "jpst_platform_tactile": tex_yellow(),
                "jpst_platform_edge_jp": tex_edge_piece(),
                "jpst_platform_base_jp": tex_base_piece(),
                "jpst_concourse_floor": tex_concourse(),
                "jpst_pdoor": tex_pdoor()}
    for name, tex in textures.items():
        write_texture_set(name, tex)
        (OUT / f"mat/{name}.mtl").write_text(MTL % {"n": name})
    mt = ["jpst_platform_floor", "jpst_platform_edge", "jpst_platform_tactile"]
    if EDGE_FBX.exists():
        mt.append("jpst_platform_edge_jp")
        if BASE_FBX.exists():
            mt.append("jpst_platform_base_jp")
    for sides, suf in SIDE_SUFFIX.items():
        build_platform_mesh(sides=sides).write(OUT / f"msh/jpst_perron_5{suf}_lod0.msh")
        (OUT / f"jpst_perron_5{suf}.mdl").write_text(
            build_mdl(vanilla_mdl(), mt, f"jpst_perron_5{suf}_lod0") if suf else build_mdl(vanilla_mdl(), mt))
    # script x = -mesh y, so the stairs half of a 10 m platform (script x = -2.5) is at mesh y = +2.5
    for name, vname, stairs, half, yc in (
            ("jpst_perron_5_underpass", "perron_5", True, HALF, 0.0),
            ("jpst_perron_10", "perron_10", False, 5.0, 0.0),
            ("jpst_perron_10_underpass", "perron_10", True, 5.0, 2.5)):
        for sides, suf in SIDE_SUFFIX.items():
            build_platform_mesh(stairs, half, yc, sides).write(OUT / f"msh/{name}{suf}_lod0.msh")
            (OUT / f"{name}{suf}.mdl").write_text(build_mdl(
                vanilla_mdl(vname), mt, f"{name}{suf}_lod0", vname))
    build_stairwell_mesh().write(OUT / "msh/jpst_stairwell_lod0.msh")
    (OUT / "jpst_stairwell.mdl").write_text(build_stairwell_mdl("jpst_platform_edge"))
    build_deck_mesh().write(OUT / "msh/jpst_deck_lod0.msh")
    (OUT / "jpst_deck.mdl").write_text(build_deck_mdl())
    build_gate_mesh().write(OUT / "msh/jpst_gate_lod0.msh")
    (OUT / "jpst_gate.mdl").write_text(build_gate_mdl())
    for name, half in (("jpst_pdoor_5", HALF), ("jpst_pdoor_10", 5.0)):
        for sides, suf in SIDE_SUFFIX.items():
            if not any(sides):
                continue
            build_pdoor_mesh(half, sides).write(OUT / f"msh/{name}{suf}_lod0.msh")
            (OUT / f"{name}{suf}.mdl").write_text(build_pdoor_mdl(name + suf, half, sides))
    print("written", OUT)


if __name__ == "__main__":
    main()
