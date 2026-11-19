"""Minimal binary FBX reader (geometry only): returns dict name -> list of meshes."""
import struct, zlib


def _read(d, o):
    end, np_, _pl, nl = struct.unpack_from("<IIIB", d, o)
    if end == 0:
        return None, o + 13
    name = d[o + 13:o + 13 + nl].decode()
    p = o + 13 + nl
    props = []
    for _ in range(np_):
        t = chr(d[p]); p += 1
        if t in "YCIFDL":
            f = {"Y": "<h", "C": "<?", "I": "<i", "F": "<f", "D": "<d", "L": "<q"}[t]
            props.append(struct.unpack_from(f, d, p)[0]); p += struct.calcsize(f)
        elif t in "fdilb":
            al, enc, cl = struct.unpack_from("<III", d, p); p += 12
            raw = d[p:p + cl]; p += cl
            if enc:
                raw = zlib.decompress(raw)
            f = {"f": "f", "d": "d", "i": "i", "l": "q", "b": "?"}[t]
            props.append(list(struct.unpack("<%d%s" % (al, f), raw)))
        else:
            ln = struct.unpack_from("<I", d, p)[0]; p += 4
            props.append(d[p:p + ln].decode("latin1")); p += ln
    ch = []
    while p < end:
        c, p = _read(d, p)
        if c is None:
            break
        ch.append(c)
    return (name, props, ch), end


def load(path):
    d = open(path, "rb").read()
    o, top = 27, []
    while o < len(d) - 100:
        n, o = _read(d, o)
        if n is None:
            break
        top.append(n)
    return top


def find(node, name):
    return [c for c in node[2] if c[0] == name]


def geometries(path):
    """Yield dicts: pos (list of xyz), polys (list of vertex-index lists, ids into pos),
    uv (per polygon-vertex), normal (per polygon-vertex), mat (per polygon)."""
    out = []
    objs = [c for t in load(path) if t[0] == "Objects" for c in t[2]]
    for g in objs:
        if g[0] != "Geometry":
            continue
        v = find(g, "Vertices")[0][1][0]
        pos = [tuple(v[i:i + 3]) for i in range(0, len(v), 3)]
        pvi = find(g, "PolygonVertexIndex")[0][1][0]
        polys, cur = [], []
        for i in pvi:
            if i < 0:
                cur.append(~i); polys.append(cur); cur = []
            else:
                cur.append(i)

        def layer(name, dataname, idxname):
            ls = find(g, name)
            if not ls:
                return None
            vals = find(ls[0], dataname)[0][1][0]
            ix = find(ls[0], idxname)
            return vals, (ix[0][1][0] if ix else None)
        uvl = layer("LayerElementUV", "UV", "UVIndex")
        nl = layer("LayerElementNormal", "Normals", "NormalsIndex")
        ml = find(g, "LayerElementMaterial")
        mats = find(ml[0], "Materials")[0][1][0] if ml else [0] * len(polys)
        out.append(dict(pos=pos, polys=polys, uvl=uvl, nl=nl, mats=mats, name=g[1][1]))
    return out
