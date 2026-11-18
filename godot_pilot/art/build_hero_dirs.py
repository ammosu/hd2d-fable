#!/usr/bin/env python3
"""主角側面／背面：art/raw/hero_{side,back}_v1.png → art/work/hero_{side,back}_restored.png（46×68，人物 60 點陣高、底邊對齊正面版）
量化做法與 build_hero.py 相同（分部位：頭部暖色 → 髮色階、身體暖色 → 木褐、藍 → 斗篷、青綠 → 圍巾、膚色）。"""
import os, sys
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import depixel, to_palette, check
from palette import sub
front = np.array(Image.open(os.path.join(A, 'work', 'hero_fixed.png')).convert('RGBA'))
fy = np.where(front[..., 3] > 0)[0]; FT, FB = fy.min(), fy.max()          # 正面版人物的上下緣
DIRS = sys.argv[1:] or ['side', 'back']
for d in DIRS:
    _a = np.array(Image.open(os.path.join(A, 'raw', f'hero_{d}_v1.png')).convert('RGBA'))[..., 3] > 127
    _y = np.where(_a)[0]; fp = (_y.max() - _y.min() + 1) / 60.0      # 格距 = 人物原圖高 ÷ 60（與正面版同為 60 點陣高；自動偵測會抓錯）
    f = os.path.join(A, 'raw', f'hero_{d}_v1.png')
    o, p, _ = depixel(Image.open(f).convert('RGBA'), False, force_p=fp)
    print(d, 'pitch', p, o.shape, 'err %.1f' % check(f, o, p))
    a = o[..., 3] > 127; ys, xs = np.where(a)
    o = o[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    o[..., 3] = np.where(o[..., 3] > 127, 255, 0)
    rgb = o[..., :3].astype(np.float32); r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hh = o.shape[0]
    yy = np.arange(hh)[:, None] * np.ones((1, o.shape[1]))
    skin = (r > 215) & (g > 165) & (b > 120)
    teal = (g > r + 14) & (g > b - 14)
    blue = (b > r + 12) & ~teal
    head = yy < hh * 37 / 60
    q = o.copy()
    o2 = o.copy(); o2[..., :3] = np.clip(rgb * np.array([1.0, 0.82, 0.8]), 0, 255).astype(np.uint8)   # 這兩張髮色偏棕，往紅褐拉
    hm = head & ~skin & ~blue & ~teal
    q[hm] = to_palette(o2, sub('H', 'R0', 'R1', 'R2'))[hm]
    m = ~head & ~skin & ~blue & ~teal; q[m] = to_palette(o, sub('D', 'P4', 'P5', 'M2', 'L1', 'R0'))[m]
    q[skin] = to_palette(o, sub('K', 'X0', 'R7'))[skin]
    q[blue] = to_palette(o, sub('B'))[blue]
    q[teal] = to_palette(o, sub('T'))[teal]
    q[o[..., 3] == 0] = 0
    print(d, 'figure', q.shape)
    out = np.zeros_like(front)
    h, w = q.shape[:2]
    h2 = min(h, FB - FT + 1 + 2)
    y0 = FB + 1 - h; x0 = (46 - w) // 2
    ys0 = max(0, -y0)
    out[max(0, y0):FB + 1, x0:x0 + w] = q[ys0:]
    Image.fromarray(out).save(os.path.join(A, 'work', f'hero_{d}_restored.png'))
