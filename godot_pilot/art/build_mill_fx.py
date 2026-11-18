#!/usr/bin/env python3
"""水車磨坊的落水與水花（程式畫的點陣，4 格循環）→ tex/pilot_fall.png、tex/pilot_splash.png"""
import os, json
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(A, '..', 'tex')
rng = np.random.default_rng(3)
cols = np.array([[236, 240, 250], [196, 214, 236], [150, 176, 214], [108, 132, 182]], np.uint8)
W, H, N = 14, 40, 4
fr = []
cols_off = rng.integers(0, H, W); speed = rng.choice([1, 2], W)
shade = np.array([3, 2, 1, 1, 0, 0, 1, 0, 0, 1, 1, 2, 2, 3])[:W]
for f in range(N):
    im = np.zeros((H + 8, W + 8, 4), np.uint8)
    for x in range(W):
        for y in range(H):
            v = (y - f * 4 * speed[x] + cols_off[x]) % 9
            c = shade[x] if v > 1 else max(shade[x] - 2, 0)
            if x in (0, W - 1) and (y + f) % 3 == 0: continue      # 邊緣斷續
            im[y + 4, x + 4, :3] = cols[c]; im[y + 4, x + 4, 3] = 255
    fr.append(im)
Image.fromarray(np.concatenate(fr, axis=1)).save(os.path.join(T, 'pilot_fall.png'))
# 水花：底部一團白色泡沫，4 格輪流冒起
W2, H2 = 40, 18
fs = []
for f in range(N):
    im = np.zeros((H2 + 8, W2 + 8, 4), np.uint8)
    r = np.random.default_rng(10 + f)
    for k in range(70):
        x = int(np.clip(r.normal(W2 / 2, W2 / 5), 0, W2 - 1)); y = int(np.clip(H2 - 1 - abs(r.normal(0, 4.5 - abs(x - W2 / 2) / 6)), 0, H2 - 1))
        c = cols[0] if r.random() < 0.6 else cols[1]
        for dx, dy in ((0, 0), (1, 0), (0, 1)):
            if r.random() < 0.8 and y + dy < H2: im[y + dy + 4, x + dx + 4, :3] = c; im[y + dy + 4, x + dx + 4, 3] = 255
    fs.append(im)
Image.fromarray(np.concatenate(fs, axis=1)).save(os.path.join(T, 'pilot_splash.png'))
m = json.load(open(os.path.join(T, 'meta.json')))
m['pilot_fall'] = [(W + 8) * N, H + 8]; m['pilot_fall_frames'] = N
m['pilot_splash'] = [(W2 + 8) * N, H2 + 8]; m['pilot_splash_frames'] = N
json.dump(m, open(os.path.join(T, 'meta.json'), 'w')); print('ok')
# 溪谷的大瀑布：寬 44、高 140 點陣，4 格循環（中間較亮、兩側較暗，邊緣不規則）
W, H = 60, 236
r = np.random.default_rng(7)
off = r.integers(0, 40, W); sp = r.choice([2, 3, 4], W)
edge_l = (np.sin(np.arange(H) * 0.21) * 1.5 + r.normal(0, 0.6, H)).round().astype(int)
edge_r = (np.sin(np.arange(H) * 0.17 + 1.0) * 1.5 + r.normal(0, 0.6, H)).round().astype(int)
cols5 = np.array([[240, 242, 250], [210, 222, 240], [170, 190, 222], [130, 152, 196], [96, 112, 160]], np.uint8)
fb = []
for f in range(N):
    im = np.zeros((H + 8, W + 8, 4), np.uint8)
    for y in range(H):
        xl = 2 + edge_l[y] + int(y * 0.02); xr = W - 3 + edge_r[y] - int(y * 0.0)
        for x in range(max(0, xl), min(W, xr)):
            d = min(x - xl, xr - x)
            base = 0 if d > 12 else (1 if d > 7 else (2 if d > 3 else 3))
            v = (y - f * sp[x] * 3 + off[x]) % 13
            c = base + (1 if v < 3 else 0)
            if v == 12 and base < 2: c = 0
            im[y + 4, x + 4, :3] = cols5[min(c, 4)]; im[y + 4, x + 4, 3] = 255
    fb.append(im)
Image.fromarray(np.concatenate(fb, axis=1)).save(os.path.join(T, 'pilot_falls_big.png'))
m = json.load(open(os.path.join(T, 'meta.json')))
m['pilot_falls_big'] = [(W + 8) * N, H + 8]; m['pilot_falls_big_frames'] = N
json.dump(m, open(os.path.join(T, 'meta.json'), 'w')); print('big ok')
