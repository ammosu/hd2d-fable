#!/usr/bin/env python3
"""遠景屋頂剪影（兩層）：tex/skyline_a.png（近、暗）、tex/skyline_b.png（遠、淡，含鐘樓）。
一排山牆屋與橫脊屋的像素剪影：朝太陽（左）的屋面與屋脊有背光亮邊、零星亮窗、煙囪。 python3 tools/skyline.py"""
import json, os
import numpy as np
from PIL import Image
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
mp = os.path.join(T, 'meta.json'); meta = json.load(open(mp))
def layer(name, W, H, seed, wall, roof, roof_lit, rim, win, base, tower):
    r = np.random.default_rng(seed)
    a = np.zeros((H, W, 4), np.uint8)
    def px(x, y, c):
        if 0 <= x < W and 0 <= y < H: a[y, x] = list(c) + [255]
    x = -int(r.integers(0, 12)); k = 0
    while x < W:
        w = int(r.integers(22, 40)); eave = base - int(r.integers(10, 24)); gable = r.random() < 0.55
        if tower and k == tower:
            w = 13; eave = base - 46
            for yy in range(eave, H):
                for xx in range(x, x + w): px(xx, yy, wall if xx > x + 3 else tuple(int(v * 1.25) for v in wall))
            for i in range(20):      # 尖頂
                hw = max(0, (w // 2) - i * (w // 2 + 1) // 20)
                for xx in range(x + w // 2 - hw, x + w // 2 + hw + 1): px(xx, eave - 1 - i, roof_lit if xx < x + w // 2 else roof)
                px(x + w // 2 - hw, eave - 1 - i, rim)
            for yy in (eave + 5, eave + 6, eave + 7, eave + 8): px(x + 6, yy, win); px(x + 7, yy, win)
            x += w + int(r.integers(0, 3)); k += 1; continue
        rh = w // 2 if gable else int(r.integers(7, 12))
        for yy in range(eave, H):
            for xx in range(x, x + w): px(xx, yy, wall)
        if gable:      # 山牆朝前：三角形牆面＋兩條斜屋簷
            for i in range(rh):
                x0 = x + i; x1 = x + w - 1 - i
                for xx in range(x0, x1 + 1): px(xx, eave - 1 - i, wall)
                px(x0, eave - 1 - i, rim); px(x0 - 1, eave - i, rim); px(x0 + 1, eave - 1 - i, roof_lit)
                px(x1, eave - 1 - i, roof); px(x1 + 1, eave - i, roof)
        else:           # 橫脊：一整片屋面（上亮下暗）＋屋脊亮邊
            for i in range(rh):
                for xx in range(x - 1 + i // 3, x + w + 1 - i // 3): px(xx, eave - 1 - i, roof_lit if i > rh * 0.45 else roof)
            for xx in range(x - 1 + rh // 3, x + w + 1 - rh // 3): px(xx, eave - rh, rim)
            for i in range(0, rh, 3):
                for xx in range(x, x + w, 2): px(xx + (i // 3) % 2, eave - 1 - i, tuple(int(v * 0.86) for v in roof))
        # 煙囪
        if r.random() < 0.7:
            cx = x + int(r.integers(4, w - 6)); top = eave - rh - int(r.integers(2, 6)) if not gable else eave - abs(w // 2 - (cx - x)) - int(r.integers(8, 12))
            for yy in range(top, top + 9):
                px(cx, yy, rim if yy > top else wall); px(cx + 1, yy, wall); px(cx + 2, yy, roof)
            for xx in range(cx - 1, cx + 4): px(xx, top, tuple(int(v * 0.8) for v in roof))
        # 窗
        for wy in range(eave + 3, min(H - 6, eave + 22), 9):
            for wx in range(x + 4, x + w - 5, 8):
                if r.random() < 0.42:
                    for dy in range(4):
                        for dx in range(3): px(wx + dx, wy + dy, win if (dx, dy) != (1, 1) else tuple(int(v * 0.8) for v in win))
                elif r.random() < 0.5:
                    for dy in range(4):
                        for dx in range(3): px(wx + dx, wy + dy, tuple(int(v * 0.72) for v in wall))
        if gable and r.random() < 0.6:
            px(x + w // 2, eave - rh // 2, win); px(x + w // 2 - 1, eave - rh // 2, win); px(x + w // 2, eave - rh // 2 + 1, win); px(x + w // 2 - 1, eave - rh // 2 + 1, win)
        x += w + int(r.integers(-3, 3)); k += 1
    Image.fromarray(a, 'RGBA').save(os.path.join(T, name + '.png')); meta[name] = [W, H]
layer('skyline_a', 680, 120, 5, (66, 56, 92), (50, 46, 82), (84, 66, 100), (236, 150, 86), (255, 196, 104), 60, 0)
layer('skyline_b', 680, 110, 9, (120, 92, 116), (104, 84, 114), (142, 104, 120), (250, 184, 120), (255, 214, 140), 62, 7)
json.dump(meta, open(mp, 'w'), indent=1); print('ok')
