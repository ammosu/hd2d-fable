#!/usr/bin/env python3
"""主角：art/raw/hero_v3.png → art/work/hero_restored.png（真點陣、量化到調色盤、四周 4 點陣透明邊；未手修）
格距以「放大回去與原圖的誤差最小」掃描決定（19.9 px）；人物 38×60 點陣。"""
import os, sys
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import depixel, to_palette, check
from palette import PAL, sub
f = os.path.join(A, 'raw', 'hero_v3.png')
o, p, _ = depixel(Image.open(f).convert('RGBA'), False, force_p=19.9)
print('pitch', p, o.shape, 'err %.1f' % check(f, o, p))
a = o[..., 3] > 127; ys, xs = np.where(a)
o = o[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
o[..., 3] = np.where(o[..., 3] > 127, 255, 0)
# 分部位量化（整張一起取最近色時，codex 偏粉的紅髮會被吸到膚色／木色）：頭部的暖色 → 髮色階；身體的暖色 → 木褐色階；藍 → 斗篷；青綠 → 圍巾
rgb = o[..., :3].astype(np.float32); r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
yy = np.arange(o.shape[0])[:, None] * np.ones((1, o.shape[1]))
skin = (r > 215) & (g > 165) & (b > 120)
teal = (g > r + 14) & (g > b - 14)
blue = (b > r + 12) & ~teal
head = yy < 37
q = o.copy()
def setq(mask, keys):
    q[mask] = to_palette(o, sub(*keys))[mask]
hm = head & ~skin & ~blue & ~teal
o2 = o.copy(); o2[..., :3] = np.clip(rgb * np.array([0.84, 0.74, 0.74]), 0, 255).astype(np.uint8)      # codex 的髮色偏粉偏亮，壓回紅褐
q[hm] = to_palette(o2, sub('H', 'R0', 'R1', 'R2'))[hm]
setq(~head & ~skin & ~blue & ~teal, ['D', 'P4', 'P5', 'M2', 'L1', 'R0'])
setq(skin, ['K', 'X0', 'R7'])
setq(blue, ['B'])
setq(teal, ['T'])
q[o[..., 3] == 0] = 0
PAD = 4
out = np.zeros((q.shape[0] + PAD * 2, q.shape[1] + PAD * 2, 4), np.uint8); out[PAD:-PAD, PAD:-PAD] = q
print('sprite', out.shape, 'colors', len(set(map(tuple, out.reshape(-1, 4)))) - 1)
Image.fromarray(out).save(os.path.join(A, 'work', 'hero_restored.png'))
Image.fromarray(out).resize((out.shape[1] * 10, out.shape[0] * 10), Image.NEAREST).save(os.path.join(A, 'work', 'hero_restored_x10.png'))
