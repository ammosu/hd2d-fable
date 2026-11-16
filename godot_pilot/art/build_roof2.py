#!/usr/bin/env python3
"""紅屋頂第二版（第二階段）：art/raw/roof2_v1.png → art/work/roof2_restored.png（198×89，未手修）
評審意見：瓦片比鄰近屋頂大、平塗偏扁、異色瓦脫離色盤。這一版 codex 重生成小片的長方形陶瓦（約 8×8 點陣，原本屋頂是 7×9），只有紅褐色系，每片自帶上亮下暗的形體明暗。
以固定格距 645/89 = 7.247 px 重新點陣化（屋脊瓦＋10 排瓦 = 89 列），保留比一格細的深色瓦縫；量化到 R 色階（不再逐片壓成單色，保留 codex 畫的明暗），只清單一點陣的孤立雜點。"""
import os, sys
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import restore, to_palette, tone, check, despeckle
from palette import PAL, sub
P = 645.0 / 89.0
f = os.path.join(A, 'raw', 'roof2_v1.png')
o, _ = restore(f, pitch=P, grid=False, lines=0.16)
print('restored', o.shape, 'err %.1f' % check(f, o, P))
o = o[:89, 7:205]
rgb = o[..., :3].astype(np.float32)
green = (rgb[..., 1] > rgb[..., 0] * 0.8) & (rgb[..., 1] > rgb[..., 2] + 15)
t = tone(o, gain=0.97, sat=1.05, shift=(0, -8, -10))      # 對齊原本屋頂（w_roof_red2 × tint）的亮度：平均約 (128,43,36)
tf = t[..., :3].astype(np.float32); body = rgb.sum(2) > 260; m = tf[body].mean(0)
tf[body] = m + (tf[body] - m) * 1.6
t[..., :3] = np.clip(tf, 0, 255).astype(np.uint8)
out = to_palette(t, sub('R0', 'R1', 'R2', 'R3', 'R4', 'R5', 'R6'))
out[green] = to_palette(o, sub('G0', 'G1', 'G2'))[green]
keep = set(sub('G', 'R0'))
o3, n = despeckle(out[..., :3], lambda c: c in keep, min_px=1, rounds=1)
out[..., :3] = o3
# 照瓦的排法重排（還原階段）：codex 的瓦縫經過重新點陣化後粗細不一、常常斷開，所以瓦的「格子」改由程式排——每片 8×8 點陣（7 點陣瓦面＋1 點陣直縫；最上列亮一階、最下面第二列暗一階、最下列是橫瓦縫），
# 上下排錯開半片；每片的底色取 codex 原圖在那片位置上最多的顏色（保留它逐片的深淺、橘褐補瓦的分布）。屋脊（第 0–6 列）沿用還原結果。
from collections import Counter
from roof_tile import tile_px, RR
RRc = [PAL[k] for k in RR]
src = out[..., :3].copy(); img = out[..., :3]
def tile_color(x0, y0):
    cnt = Counter(tuple(src[y, x]) for y in range(max(y0, 0), min(y0 + 7, 89)) for x in range(max(x0, 0), min(x0 + 7, 198)))
    for c_, _ in cnt.most_common():
        if c_ in RRc: return RRc.index(c_)
        if c_ == PAL['R6']: return 3
    return 1
nt = 0
for r in range(11):
    y0 = 7 + r * 8; off = -4 if r % 2 else 0
    for x0 in range(off, 198, 8):
        i = tile_color(x0, y0); nt += 1
        for dy in range(8):
            for dx in range(8):
                x, y = x0 + dx, y0 + dy
                if not (0 <= x < 198 and 0 <= y < 89): continue
                if tuple(src[y, x]) in (PAL['G0'], PAL['G1'], PAL['G2']): continue      # 苔留著
                k = tile_px(dx, dy, i)
                img[y, x] = PAL[k]
print('tiles laid out', nt)
print('despeckle', n, 'mean', out[..., :3].reshape(-1, 3).mean(0).round(0), 'colors', len(set(map(tuple, out[..., :3].reshape(-1, 3)))))
Image.fromarray(out[..., :3]).save(os.path.join(A, 'work', 'roof2_restored.png'))
