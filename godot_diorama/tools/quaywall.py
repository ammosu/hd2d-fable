#!/usr/bin/env python3
"""堤岸石牆專用貼圖 tex/quaywall.png（768×40 = 24 m × 1.25 m，不重複）：
壓頂石、三排大小不一的砌石、青苔團、三個排水口（下方有水漬）、四個繫船鐵環、幾塊破損缺角的石頭、底部深綠的水線污痕。 python3 tools/quaywall.py"""
import json, os
import numpy as np
from PIL import Image
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
W, H = 768, 40
r = np.random.default_rng(21)
BASE = np.array([[118, 116, 132], [132, 128, 138], [106, 108, 128], [140, 134, 136], [124, 122, 142], [112, 110, 122]], float)
GAP = np.array([40, 42, 62], float)
img = np.zeros((H, W, 3), float); img[:] = GAP
def noise(cell, seed):
    rr = np.random.default_rng(seed); g = rr.random((H // cell + 2, W // cell + 2))
    ys, xs = np.mgrid[0:H, 0:W]; fx, fy = xs / cell, ys / cell; ix, iy = fx.astype(int), fy.astype(int); tx, ty = fx - ix, fy - iy
    return (g[iy, ix] * (1 - tx) + g[iy, ix + 1] * tx) * (1 - ty) + (g[iy + 1, ix] * (1 - tx) + g[iy + 1, ix + 1] * tx) * ty
big = noise(60, 1)
def stone(x0, y0, x1, y1, tone=0.0, broken=False):
    c = BASE[r.integers(len(BASE))] * (0.84 + 0.3 * big[min(H - 1, y0), min(W - 1, max(0, x0))] + r.uniform(-0.08, 0.08) + tone)
    for y in range(max(0, y0), min(H, y1 - 1)):
        for x in range(max(0, x0), min(W, x1 - 1)):
            k = 1.14 if (y == y0 or x == x0) else (0.82 if (y == y1 - 2 or x == x1 - 2) else 1.0)
            if broken and (x - x0) + (y - y0) < 4: continue      # 缺角
            if broken and (x1 - x) + (y1 - y) < 6: k *= 0.7
            img[y, x] = c * k
x = -int(r.integers(0, 20))
while x < W:      # 壓頂石
    w = int(r.choice([34, 40, 46])); stone(x, 0, x + w, 7, 0.14); x += w
rows = [(7, 17), (17, 28), (28, 40)]
for (y0, y1) in rows:
    x = -int(r.integers(0, 24))
    while x < W:
        w = int(r.choice([14, 18, 22, 26, 32]))
        stone(x, y0, x + w, y1, -0.03 * rows.index((y0, y1)), r.random() < 0.07); x += w
n = r.random((H, W)); img[n < 0.05] *= 0.9; img[n > 0.96] *= 1.08
# 排水口：深色拱洞＋下方的水漬
for cx in (150, 430, 650):
    for y in range(11, 19):
        for x in range(cx - 4, cx + 5):
            if y == 11 and abs(x - cx) > 2: continue
            img[y, x] = [16, 16, 30] if abs(x - cx) < 4 and y > 11 else [78, 76, 92]
    for y in range(19, H):
        wd = 2 + (y - 19) // 6
        img[y, cx - wd:cx + wd + 1] *= np.array([0.6, 0.72, 0.66])
# 繫船鐵環
for cx in (60, 290, 540, 720):
    for (dx, dy) in [(0, 0), (-1, 1), (1, 1), (-2, 2), (2, 2), (-2, 3), (2, 3), (-1, 4), (1, 4), (0, 5)]:
        img[10 + dy, cx + dx] = [30, 28, 40]
    img[9, cx - 1:cx + 2] = [60, 56, 70]
    img[16:22, cx] *= 0.75      # 鏽痕
# 青苔：石縫與石面上成團
mn = noise(22, 4) * 0.6 + noise(6, 5) * 0.4
ys = np.mgrid[0:H, 0:W][0]
mm = (mn + ys / H * 0.25 > 0.68) & (r.random((H, W)) < 0.8)
MOSS = np.array([[74, 96, 66], [92, 110, 70], [60, 80, 64]], float)
idx = r.integers(0, 3, (H, W)); img[mm] = MOSS[idx[mm]] * (0.7 + 0.5 * (1 - ys[mm] / H))[:, None]
# 水線污痕：底部 7 點陣漸深、帶綠
for y in range(H - 8, H):
    k = (y - (H - 8)) / 8.0
    edge = (np.sin(np.arange(W) / 9.0) * 1.5 + np.sin(np.arange(W) / 23.0) * 1.5).astype(int)
    for x in range(W):
        if y >= H - 6 + edge[x] - 1: img[y, x] = img[y, x] * (0.62 - 0.25 * k) * np.array([0.8, 1.0, 0.92])
out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGB').quantize(colors=40, method=Image.MEDIANCUT, dither=Image.NONE).convert('RGB')
out.save(os.path.join(T, 'quaywall.png'))
mp = os.path.join(T, 'meta.json'); meta = json.load(open(mp)); meta['quaywall'] = [W, H]; json.dump(meta, open(mp, 'w'), indent=1); print('ok')
