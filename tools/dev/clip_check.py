# Pairwise clipping check of every cosmetic piece (tools/dev/clip_dump.gd makes the input):
# segment-vs-triangle hits between pieces of different kinds and against the bare arms, eyes
# and mouth, outside the body only. Prints the worst pairs (hits, a, b, centroid).
import json, sys, itertools, numpy as np
from collections import defaultdict
d = json.load(open(sys.argv[1]))
CELL = 0.03
def T(v): return np.asarray(v, dtype=np.float64).reshape(-1, 3, 3)
parts = {k: T(v) for k, v in d['parts'].items()}
body = parts['Rig/Body']
bare = {'arm': np.concatenate([parts[k] for k in parts if '/Arm' in k]),
        'eyes_face': np.concatenate([parts[k] for k in ['Rig/Body/EyeL', 'Rig/Body/EyeR']]),
        'mouth_face': parts['Rig/Body/Mouth']}
pieces = {k: (v['kind'], T(v['tris'])) for k, v in d['pieces'].items()}
pieces = {k: v for k, v in pieces.items() if len(v[1])}

def inside_body(p):
    # ray parity along +x against the body mesh
    o = p[:, None, :]; v0, v1, v2 = body[:, 0], body[:, 1], body[:, 2]
    e1 = v1 - v0; e2 = v2 - v0; dirn = np.array([1.0, 0.0, 0.0])
    h = np.cross(dirn, e2); a = np.einsum('ij,ij->i', e1, h)
    ok = np.abs(a) > 1e-12; f = np.where(ok, 1.0 / np.where(ok, a, 1), 0)
    s = o - v0[None]; u = f * np.einsum('nij,ij->ni', s, h)
    q = np.cross(s, e1[None]); vv = f * (q @ dirn)
    t = f * np.einsum('nij,ij->ni', q, e2)
    hit = ok & (u >= 0) & (vv >= 0) & (u + vv <= 1) & (t > 1e-9)
    return hit.sum(1) % 2 == 1

def cells(tris):
    lo = np.floor(tris.min(1) / CELL).astype(int); hi = np.floor(tris.max(1) / CELL).astype(int)
    return lo, hi

def tri_tri(A, B):
    """Vectorised segment-vs-triangle test both ways; returns mask and hit points."""
    pts = []; mask = np.zeros(len(A), bool)
    for X, Y, flip in ((A, B, False), (B, A, True)):
        v0, v1, v2 = Y[:, 0], Y[:, 1], Y[:, 2]
        e1 = v1 - v0; e2 = v2 - v0
        for a, b in ((0, 1), (1, 2), (2, 0)):
            p0 = X[:, a]; dvec = X[:, b] - p0
            h = np.cross(dvec, e2); det = np.einsum('ij,ij->i', e1, h)
            ok = np.abs(det) > 1e-14; f = np.where(ok, 1 / np.where(ok, det, 1), 0)
            s = p0 - v0; u = f * np.einsum('ij,ij->i', s, h)
            q = np.cross(s, e1); w = f * np.einsum('ij,ij->i', dvec, q)
            t = f * np.einsum('ij,ij->i', e2, q)
            hit = ok & (u >= 0) & (w >= 0) & (u + w <= 1) & (t >= 0) & (t <= 1)
            mask |= hit
            if hit.any():
                pts.append(p0[hit] + dvec[hit] * t[hit, None])
    return mask, (np.concatenate(pts) if pts else np.zeros((0, 3)))

def index(tris):
    lo, hi = cells(tris); idx = defaultdict(list)
    for i in range(len(tris)):
        for x in range(lo[i, 0], hi[i, 0] + 1):
            for y in range(lo[i, 1], hi[i, 1] + 1):
                for z in range(lo[i, 2], hi[i, 2] + 1):
                    idx[(x, y, z)].append(i)
    return idx

def bbox(t): return t.reshape(-1, 3).min(0), t.reshape(-1, 3).max(0)
IDX = {}
def check(na, A, nb, B):
    (la, ha), (lb, hb) = bbox(A), bbox(B)
    lo = np.maximum(la, lb); hi = np.minimum(ha, hb)
    if np.any(lo > hi): return 0, None
    if na not in IDX: IDX[na] = index(A)
    if nb not in IDX: IDX[nb] = index(B)
    ia, ib = IDX[na], IDX[nb]
    pairs = set()
    small, big, sw = (ia, ib, False) if len(ia) < len(ib) else (ib, ia, True)
    for c, lst in small.items():
        other = big.get(c)
        if other:
            for i in lst:
                for j in other:
                    pairs.add((j, i) if sw else (i, j))
    if not pairs: return 0, None
    P = np.array(list(pairs))
    m, pts = tri_tri(A[P[:, 0]], B[P[:, 1]])
    if len(pts) == 0: return 0, None
    vis = pts[~inside_body(pts)] if len(pts) < 20000 else pts
    return len(vis), (vis.mean(0) if len(vis) else None)

SPREADS = d.get('spreads', {})
def spread(cape, other, T):
    s = SPREADS.get(cape + '|' + other)
    if not s: return T, cape
    T = T.copy(); T[..., 0] *= s; T[..., 2] *= s
    return T, cape + '@' + other

res = []
names = sorted(pieces)
for x, y in itertools.combinations(names, 2):
    kx, A = pieces[x]; ky, B = pieces[y]
    if kx == ky: continue
    xa, ya = x, y
    if kx == 'cape': A, xa = spread(x, y, A)
    if ky == 'cape': B, ya = spread(y, x, B)
    n, c = check(xa, A, ya, B)
    if n: res.append((n, x, y, None if c is None else c.round(2).tolist()))
for x in names:
    kx, A = pieces[x]
    for bn, B in bare.items():
        if bn == 'eyes_face' and kx == 'eyes': continue
        n, c = check(x, A, bn, B)
        if n: res.append((n, x, bn, None if c is None else c.round(2).tolist()))
res.sort(reverse=True)
json.dump(res, open(sys.argv[2], 'w'))
print(len(res), 'clipping pairs')
for r in res[:60]: print(r)
