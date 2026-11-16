#!/usr/bin/env python3
"""屋頂貼圖變體：把手繪的 128px 瓦片圖鋪成 512×512（16 m 見方，單一屋頂上不重複），逐片瓦分割後各自抖動色相與明度（±8%），
再依亂數加貼花：缺瓦（露出深色底）、補丁瓦（顏色不同的新瓦，三種色）、青苔（下緣點狀，三種綠）、水漬（往下流的暗痕）。
全部在點陣格上處理，所以仍是銳利的像素。輸出 tex/roof_red4.png、tex/roof_slate4.png。 python3 tools/roofgen.py"""
import json, os, colorsys
import numpy as np
from PIL import Image
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
mp = os.path.join(T, 'meta.json'); meta = json.load(open(mp))
def label(mask):
    H, W = mask.shape; lab = np.zeros((H, W), np.int32); n = 0
    for y in range(H):
        for x in range(W):
            if mask[y, x] and not lab[y, x]:
                n += 1; st = [(y, x)]; lab[y, x] = n
                while st:
                    cy, cx = st.pop()
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not lab[ny, nx]: lab[ny, nx] = n; st.append((ny, nx))
    return lab, n
def gen(src, out, seed, patch_cols, moss_cols):
    r = np.random.default_rng(seed)
    base = np.array(Image.open(os.path.join(T, src + '.png')).convert('RGB')).astype(float)
    a = np.tile(base, (4, 4, 1)); H, W = a.shape[:2]
    lum = a.mean(axis=2)
    lab, n = label(lum > np.percentile(lum, 16))      # 深色的縫把瓦片分開
    med = np.median(lum[lab > 0])
    ys, xs = np.mgrid[0:H, 0:W]
    for i in range(1, n + 1):
        m = lab == i; cnt = m.sum()
        if cnt < 12 or cnt > 400: continue
        ml = lum[m].mean()
        if ml < med * 0.84: a[m] *= med * 0.95 / ml      # 原圖裡固定位置的深色瓦：拉回一般亮度
        k = 1.0 + r.uniform(-0.08, 0.08); h = r.uniform(-0.05, 0.05)
        a[m] *= np.array([k * (1 + h), k, k * (1 - h)])
        u = r.random()
        if u < 0.012:      # 缺瓦
            a[m] = a[m] * 0.32 + np.array([10, 8, 16])
        elif u < 0.05:     # 補丁瓦
            c = np.array(patch_cols[r.integers(len(patch_cols))], float)
            a[m] = (a[m].mean(axis=1, keepdims=True) / 255.0) * c * 1.5
        elif u < 0.12:     # 青苔：長在瓦的下半，點狀
            y0, y1 = ys[m].min(), ys[m].max()
            mm = m & (ys > y0 + (y1 - y0) * r.uniform(0.2, 0.6)) & (r.random((H, W)) < 0.7)
            a[mm] = np.array(moss_cols[r.integers(len(moss_cols))], float) * r.uniform(0.8, 1.1)
        elif u < 0.135:    # 水漬：往下拖一道暗痕
            x0 = int(xs[m].mean()); y0 = int(ys[m].max())
            for yy in range(y0, min(H, y0 + int(r.integers(10, 26)))): a[yy, x0:x0 + 2] *= 0.8
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGB').save(os.path.join(T, out + '.png')); meta[out] = [W, H]
gen('w_roof_red2', 'roof_red4', 1, [(214, 120, 70), (150, 70, 60), (190, 150, 110)], [(96, 110, 60), (120, 124, 66), (78, 92, 62)])
gen('w_roof_slate2', 'roof_slate4', 2, [(120, 130, 160), (96, 90, 120), (150, 140, 150)], [(84, 106, 80), (104, 120, 84), (70, 90, 78)])
json.dump(meta, open(mp, 'w'), indent=1); print('ok')
