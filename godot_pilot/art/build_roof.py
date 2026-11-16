#!/usr/bin/env python3
"""紅屋頂：art/raw/roof_v1.png → art/work/roof_restored.png（198×89，未手修）
codex 這張的假像素格不一致（瓦的階梯約 7～10 px、瓦縫線只有 1～2 px），所以用固定格距 6.854 px 重新點陣化
（選這個格距是為了讓「屋脊瓦＋8 排瓦」剛好等於斜面的 89 個點陣），比一格細的深色瓦縫另外保留；再裁出左邊 198 行。"""
import os, sys
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import restore, to_palette, tone, check, despeckle
from palette import PAL, sub
P = 610.0 / 89.0
f = os.path.join(A, 'raw', 'roof_v1.png')
o, _ = restore(f, pitch=P, grid=False, lines=0.16)
print('restored', o.shape, 'err %.1f' % check(f, o, P))
o = o[:89, :198]
rgb = o[..., :3].astype(np.float32)
green = (rgb[..., 1] > rgb[..., 0] * 0.8) & (rgb[..., 1] > rgb[..., 2] + 15)
grey = (rgb[..., 0] - rgb[..., 2] < 40) & (rgb.sum(2) > 330)
# 色調：對齊原本屋頂（w_roof_red2 × tint）的平均亮度，平均約 (128,43,36)；codex 的偏亮偏粉
t = tone(o, gain=0.88, sat=1.1, shift=(0, -8, -10))
tf = t[..., :3].astype(np.float32); body = rgb.sum(2) > 300; m = tf[body].mean(0)
tf[body] = m + (tf[body] - m) * 1.7      # 瓦片之間的色差拉大（量化後才分得出階）
t[..., :3] = np.clip(tf, 0, 255).astype(np.uint8)
red = to_palette(t, sub('R', 'D0', 'D1', 'D2', 'D3'))
out = red.copy()
out[green] = to_palette(o, sub('G'))[green]
out[grey] = to_palette(tone(o, gain=0.8), sub('S3', 'S4', 'S5', 'S6'))[grey]
keep = set(sub('G', 'D0', 'D1', 'R0'))
o3, n = despeckle(out[..., :3], lambda c: c in keep, min_px=2, rounds=1)
out[..., :3] = o3
# 逐片瓦整理（還原階段）：被深色瓦縫圍起來的一片瓦改成單一底色（該片最多的顏色）、下緣一列亮一階（瓦的厚邊）→ 去掉量化造成的斑駁亂點
from build_ground import label4
RR = [PAL[k] for k in ('R1', 'R2', 'R3', 'R4', 'R5', 'R6')]
dark = np.zeros(out.shape[:2], bool)
for k in ('R0', 'D0', 'D1', 'D2'): dark |= (out[..., :3] == np.array(PAL[k], np.uint8)).all(-1)
lab, comps = label4(~dark); flat = 0
for comp in comps:
    if not (12 <= len(comp) <= 170): continue
    ys = np.array([c[0] for c in comp]); xs = np.array([c[1] for c in comp])
    cols = [tuple(c) for c in out[ys, xs, :3]]
    if any(c not in RR and c != PAL['R7'] for c in cols) : continue      # 有苔或灰瓦的不動
    mode = max(set(cols), key=cols.count); i = RR.index(mode) if mode in RR else 4
    for y, x in comp:
        k = i
        if y + 1 < 89 and dark[y + 1, x]: k = min(i + 1, len(RR) - 1)
        out[y, x, :3] = RR[k]
    flat += 1
print('tiles flattened', flat, '/', len(comps))
print('despeckle', n, 'mean', out[..., :3].reshape(-1, 3).mean(0).round(0), 'colors', len(set(map(tuple, out[..., :3].reshape(-1, 3)))))
Image.fromarray(out[..., :3]).save(os.path.join(A, 'work', 'roof_restored.png'))
Image.fromarray(out[..., :3]).resize((198 * 5, 89 * 5), Image.NEAREST).save(os.path.join(A, 'work', 'roof_restored_x5.png'))
