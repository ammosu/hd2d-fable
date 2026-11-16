#!/usr/bin/env python3
"""中央屋正面：art/raw/wall_v1.png（磚、石基、灰泥分格）＋ art/raw/wall_plaster_v1.png（山牆用的灰泥）→ art/work/wall_restored.png（139×147，未手修）
兩張都是對齊格線的假像素，追蹤格線還原（格距 6.08 px 與 11.27 px）。codex 畫的立面比例與木樑粗細和 3D 模型對不上
（模型的木樑是 3～4.5 點陣寬的立體方塊），所以這裡只取 codex 的「材質」——三格灰泥、磚牆、石基、山牆灰泥——依模型的實際座標重新排版；
木構架的位置先填單色，之後在 fix_wall.py 逐點畫。版面（列由上往下，1 列 = 1/32 m，底列 = 地面）：
  山牆 0–50｜上樑 51–54｜灰泥格 55–93｜下樑 94–99｜紅磚 100–137｜石基 138–146；立柱在第 0–2、44–48、90–94、136–138 行。"""
import os, sys
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import restore, to_palette, check, despeckle
from palette import PAL, sub
W, H = 139, 147
w1, p1 = restore(os.path.join(A, 'raw', 'wall_v1.png')); print('wall_v1 pitch %.2f' % p1, w1.shape, 'err %.1f' % check(os.path.join(A, 'raw', 'wall_v1.png'), w1, p1))
w2, p2 = restore(os.path.join(A, 'raw', 'wall_plaster_v1.png')); print('plaster pitch %.2f' % p2, w2.shape, 'err %.1f' % check(os.path.join(A, 'raw', 'wall_plaster_v1.png'), w2, p2))
w1 = w1[..., :3].astype(np.float32); w2 = w2[..., :3].astype(np.float32)
def match(a, target, mask=None, contrast=1.0):
    """把區域的平均色對到 target（各色版各自乘一個倍率）——對齊原本貼圖 × 材質 tint 的亮度，即時光照才會維持原來的曝光"""
    m = a[mask].mean(0) if mask is not None else a.reshape(-1, 3).mean(0)
    o = a * (np.array(target, np.float32) / m)
    if contrast != 1.0: o = np.array(target, np.float32) + (o - np.array(target, np.float32)) * contrast
    return np.clip(o, 0, 255)
def is_plaster(a): return (a[..., 0] - a[..., 2] < 70) & (a.sum(2) > 420)
out = np.zeros((H, W, 3), np.float32); kind = np.zeros((H, W), np.uint8)      # kind：1 灰泥 2 磚 3 石基 4 木
PL = (203, 170, 136)
def put_plaster(src, sy, sx, ty, tx, h, w):
    blk = src[sy:sy + h, sx:sx + w]; out[ty:ty + h, tx:tx + w] = match(blk, PL, is_plaster(blk), 1.25); kind[ty:ty + h, tx:tx + w] = 1
put_plaster(w2, 38, 0, 0, 0, 51, 70)          # 山牆左半
put_plaster(w2, 0, 42, 0, 70, 51, 69)         # 山牆右半
put_plaster(w1, 84, 14, 55, 3, 39, 41)        # 灰泥格 A
put_plaster(w1, 84, 72, 55, 49, 39, 41)       # 灰泥格 B
put_plaster(w1, 66, 154, 55, 95, 39, 41)      # 灰泥格 C
blk = w1[149:187, 30:169]; out[100:138] = match(blk, (158, 86, 72), None, 1.1); kind[100:138] = 2
blk = w1[188:197, 30:169]; out[138:147] = match(blk, (104, 86, 76), None, 1.3); kind[138:147] = 3
for r0, r1 in ((51, 54), (94, 99)): kind[r0:r1 + 1] = 4
for c0, c1 in ((0, 2), (44, 48), (90, 94), (136, 138)): kind[51:100, c0:c1 + 1] = 4
rgba = np.dstack([np.clip(out, 0, 255).astype(np.uint8), np.full((H, W), 255, np.uint8)])
q = rgba.copy()
m = kind == 1; q[m] = to_palette(rgba, sub('P', 'M1', 'M2', 'R1', 'R2', 'R3', 'R4', 'D2', 'D3', 'D4'))[m]
f = out; green = (f[..., 1] > f[..., 0] * 0.95) & (f[..., 1] > f[..., 2] + 14)      # 只有原圖真的偏綠的點陣才能用苔色
m = kind == 2; q[m] = to_palette(rgba, sub('R', 'M', 'D1'))[m]
m = kind == 3; q[m] = to_palette(rgba, sub('W', 'S1', 'S2'))[m]
m = (kind >= 2) & (kind <= 3) & green; q[m] = to_palette(rgba, sub('G1', 'G2', 'G0'))[m]
q[kind == 4] = PAL['D1'] + (255,)
keep = set(sub('R0', 'G'))
q3, n = despeckle(q[..., :3], lambda c: c in keep, min_px=1, rounds=1)      # 只清單一點陣的孤立雜點
print('despeckle', n, 'colors', len(set(map(tuple, q3.reshape(-1, 3)))))
# 逐塊磚整理（還原階段）：被勾縫圍起來的一塊磚改成單一底色（該塊最多的顏色），去掉量化造成的斑駁；燒黑、破損的深色點留著
from build_ground import label4
MORT = {PAL[k] for k in ('M0', 'M1', 'M2')}; KEEPB = {PAL['R0'], PAL['G0'], PAL['G1'], PAL['G2']}
mort = np.zeros((H, W), bool)
for y in range(100, 138):
    for x in range(W): mort[y, x] = tuple(q3[y, x]) in MORT
lab, comps = label4((kind == 2) & ~mort); nb = 0
for comp in comps:
    if not (20 <= len(comp) <= 190): continue
    cols = [tuple(q3[y, x]) for y, x in comp if tuple(q3[y, x]) not in KEEPB]
    if not cols: continue
    mode = max(set(cols), key=cols.count); nb += 1
    for y, x in comp:
        if tuple(q3[y, x]) not in KEEPB: q3[y, x] = mode
print('bricks flattened', nb, '/', len(comps))
for k, nm in ((1, 'plaster'), (2, 'brick'), (3, 'plinth')): print(nm, 'mean', q3[kind == k].mean(0).round(0))
Image.fromarray(q3).save(os.path.join(A, 'work', 'wall_restored.png'))
Image.fromarray(q3).resize((W * 6, H * 6), Image.NEAREST).save(os.path.join(A, 'work', 'wall_restored_x6.png'))
