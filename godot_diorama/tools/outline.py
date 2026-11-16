#!/usr/bin/env python3
"""統一輪廓：把 sprite 的近黑外框改成「鄰近內部顏色的深色版」（深色調同色系外框），和沒有外框的牆面、地面貼圖較一致。
python3 tools/outline.py   （直接改 tex/ 裡的 sprite；已處理過的不會再變）"""
import glob, os, colorsys
import numpy as np
from PIL import Image
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
PRE = ('props_', 'props2_', 'street2_', 'npcs_0', 'cat_anim', 'doors_', 'windows_', 'windows2_', 'lamp', 'boat', 'flowers_', 'grasses_', 'bushes_', 'plants2_', 'ivy_', 'laundry_', 'trunk', 'hero_b', 'patches_')
n_all = 0
for f in sorted(glob.glob(os.path.join(T, '*.png'))):
    if not os.path.basename(f).startswith(PRE): continue
    a = np.array(Image.open(f).convert('RGBA')); H, W = a.shape[:2]; out = a.copy(); n = 0
    dark = (a[..., 3] > 0) & (a[..., :3].max(axis=2) < 62)
    for y, x in zip(*np.where(dark)):
        acc = []; 
        for r in (1, 2, 3):
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < H and 0 <= xx < W and a[yy, xx, 3] > 0 and not dark[yy, xx]: acc.append(a[yy, xx, :3])
            if acc: break
        if not acc: continue
        c = np.mean(acc, axis=0) / 255.0
        h, s, v = colorsys.rgb_to_hsv(*c)
        r_, g_, b_ = colorsys.hsv_to_rgb(h, min(1.0, s * 0.9 + 0.1), max(0.2, v * 0.36))
        out[y, x, :3] = [int(r_ * 255 * 0.95), int(g_ * 255 * 0.85), int(b_ * 255 * 1.0 + 12)]; n += 1
    if n: Image.fromarray(out, 'RGBA').save(f); n_all += n
print('recolored outline px:', n_all)
