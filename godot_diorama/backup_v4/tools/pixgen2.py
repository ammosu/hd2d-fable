#!/usr/bin/env python3
"""程式畫的小貼圖（新場景用）：遮雨棚條紋、格紋桌布、木箱面、木桶側面與桶頂、燈籠、前景失焦楓葉框景。 python3 tools/pixgen2.py"""
import json, os, glob
import numpy as np
from PIL import Image, ImageFilter
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
mp = os.path.join(T, 'meta.json'); meta = json.load(open(mp))
rng = np.random.default_rng(3)
def save(name, a, frames=None):
    a = np.clip(a, 0, 255).astype(np.uint8)
    Image.fromarray(a, 'RGBA' if a.shape[2] == 4 else 'RGB').save(os.path.join(T, name + '.png'))
    meta[name] = [a.shape[1], a.shape[0]]
    if frames: meta[name + '_frames'] = frames
def speck(a, amt=0.06):
    n = rng.random(a.shape[:2])
    a[n < amt] *= 0.9; a[n > 1 - amt] *= 1.07
    return a
# 遮雨棚：紅白直條（8 點陣一條），上緣暗、下緣扇貝邊（透明）
w, h = 64, 28
a = np.zeros((h, w, 4), float)
for x in range(w):
    red = (x // 8) % 2 == 0
    c = np.array([176, 58, 52]) if red else np.array([232, 214, 186])
    for y in range(h):
        k = 0.8 + 0.25 * y / h
        if x % 8 == 0: k *= 0.86
        a[y, x, :3] = c * k; a[y, x, 3] = 255
    cx = (x % 8) - 3.5
    for y in range(h - 4, h):
        if abs(cx) > 3.6 - (y - (h - 4)) * 1.0: a[y, x, 3] = 0
a[h - 5, :, :3] *= 0.75
save('awning', a)
# 格紋桌布
a = np.zeros((32, 32, 3), float)
for y in range(32):
    for x in range(32):
        rx, ry = (x // 4) % 2, (y // 4) % 2
        a[y, x] = [226, 208, 190] if rx + ry == 0 else ([170, 60, 70] if rx + ry == 2 else [204, 120, 120])
save('cloth', speck(a))
# 木箱面：外框＋斜撐＋直木板
s = 22
a = np.zeros((s, s, 3), float)
for y in range(s):
    for x in range(s):
        c = np.array([150, 104, 70.0]) * (0.92 + 0.1 * ((x // 5) % 2))
        if x % 5 == 0: c *= 0.72
        if abs(x - y) <= 1: c = np.array([170, 120, 80.0]) * (1.0 if x - y != 1 else 0.75)
        if x < 3 or y < 3 or x >= s - 3 or y >= s - 3:
            c = np.array([124, 84, 60.0])
            if x == 2 or y == 2 or x == s - 3 or y == s - 3: c *= 0.7
            if x == 0 or y == 0: c *= 1.2
        a[y, x] = c
save('crate', speck(a))
# 木桶側面（可沿圓周平鋪：8 點陣一片桶板），兩道鐵箍
w, h = 16, 20
a = np.zeros((h, w, 3), float)
for y in range(h):
    for x in range(w):
        c = np.array([138, 92, 62.0]) * (0.9 + 0.12 * ((x // 4) % 2))
        if x % 4 == 0: c *= 0.7
        if y in (3, 4, 15, 16): c = np.array([78, 72, 92.0]) * (1.15 if y in (3, 15) else 0.85)
        if y == 0: c *= 1.2
        if y == h - 1: c *= 0.7
        a[y, x] = c
save('barrel', speck(a))
s = 18
a = np.zeros((s, s, 3), float)
for y in range(s):
    for x in range(s):
        r = np.hypot(x - 8.5, y - 8.5)
        c = np.array([122, 82, 58.0]) * (0.95 + 0.1 * ((x // 4) % 2))
        if x % 4 == 0: c *= 0.75
        if r > 6.5: c = np.array([160, 110, 74.0])
        a[y, x] = c
save('barreltop', speck(a))
# 燈籠（小）：鐵框＋發光玻璃
a = np.zeros((14, 10, 4), float)
for y in range(14):
    for x in range(10):
        c = None
        if 3 <= y <= 10 and 1 <= x <= 8: c = [255, 214, 120] if 2 <= x <= 7 and 4 <= y <= 9 else [56, 46, 62]
        if c and 3 <= x <= 6 and 5 <= y <= 8: c = [255, 244, 190]
        if y in (1, 2) and 2 <= x <= 7: c = [56, 46, 62]
        if y == 0 and 4 <= x <= 5: c = [56, 46, 62]
        if y in (11, 12) and 2 <= x <= 7: c = [66, 54, 70]
        if c and x in (4, 5) and 3 <= y <= 10 and False: c = [56, 46, 62]
        if c: a[y, x, :3] = c; a[y, x, 3] = 255
save('lantern', np.pad(a, ((4, 4), (4, 4), (0, 0))))
# 淺色木板（船、長椅）：長條木板 5 點陣一條，接縫很少（每 64 點陣一處、逐條錯開），有細木紋
a = np.zeros((40, 128, 3), float)
for y in range(40):
    row = y // 5
    tone = [1.0, 0.9, 1.06, 0.95, 0.86, 1.02, 0.92, 1.08][row % 8]
    for x in range(128):
        c = np.array([168, 112, 74.0]) * tone
        if y % 5 == 0: c *= 1.12
        if y % 5 == 4: c *= 0.62
        if (x + row * 37) % 128 == 0 and y % 5 != 4: c *= 0.75
        if y % 5 == 2 and ((x + row * 13) % 23) < 9: c *= 0.93
        a[y, x] = c
save('wood', speck(a, 0.03))
# 前景失焦的楓葉框景：手繪的楓枝（看得出葉形）放大後只做輕微模糊，畫在景深之後
def frame(name, W, H, items, blur, seed):
    r = np.random.default_rng(seed)
    src = Image.open(os.path.join(T, 'w_branch.png')).convert('RGBA')
    sa = np.array(src).astype(float)
    # 調成被夕陽照到的紅橘色（原圖偏暗酒紅）
    lum = sa[..., :3].mean(axis=2, keepdims=True) / 255.0
    sa[..., :3] = np.clip(np.array([255, 120, 70.0]) * (0.25 + lum * 2.4) * np.array([1.0, 0.85 + 0.6 * lum[..., 0].mean(), 0.9]), 0, 255)
    src = Image.fromarray(sa.astype(np.uint8), 'RGBA')
    cv = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for (x, y, sc, rot, flip) in items:
        im = src.transpose(Image.FLIP_LEFT_RIGHT) if flip else src
        im = im.resize((int(im.width * sc), int(im.height * sc)), Image.NEAREST).rotate(rot, Image.NEAREST, expand=True)
        cv.alpha_composite(im, (int(x - im.width / 2), int(y - im.height / 2)))
    a = np.array(cv).astype(float)
    a[..., :3] *= (a[..., 3:4] / 255.0)
    pm = Image.fromarray(a.astype(np.uint8), 'RGBA').filter(ImageFilter.GaussianBlur(blur))
    b = np.array(pm).astype(float)
    al = np.clip(b[..., 3:4], 1, 255)
    b[..., :3] = b[..., :3] / al * 255.0
    save(name, b)
frame('frame_tl', 576, 432, [(170, 150, 5, 0, False), (380, 60, 4, 30, False)], 7.0, 1)
frame('frame_bl', 460, 324, [(150, 250, 4.5, 150, False), (330, 330, 3.5, 200, True)], 6.5, 2)
frame('frame_br', 420, 300, [(300, 230, 4.5, 190, True), (140, 320, 3.5, 160, False)], 6.5, 3)
json.dump(meta, open(mp, 'w'), indent=1)
print('ok')
