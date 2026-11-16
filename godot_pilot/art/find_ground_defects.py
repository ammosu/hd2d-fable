#!/usr/bin/env python3
"""地面手修第 1 輪的「找問題」工具：列出拼接造成的具體壞點，寫成 art/fix_ground_data.py（純座標資料），由 fix_ground.py 套用。
  SEAM   ：兩張分塊相接處，左右或上下兩個點陣分屬不同分塊、卻都不是石縫（兩塊石頭直接黏在一起）→ 補一個石縫點陣
  SLIVER ：被接縫切出來、小於 7 個點陣的石頭碎片 → 併入石縫
  SPECK  ：孤立的單一石縫點陣（四周都是石面）→ 改回周圍的石面色
只找不改；清單我看過 8 倍放大圖後才套用。"""
import os, sys
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from palette import PAL
from build_ground import is_joint, label4
im = np.array(Image.open(os.path.join(A, 'work', 'ground_restored.png')).convert('RGB'))
src = np.load(os.path.join(A, 'work', 'ground_src.npy'))
H, W = src.shape
J = is_joint(im)
VIS = (slice(186, 560), slice(96, 934))      # 只處理鏡頭看得到的範圍
seam = []
for dy, dx in ((0, 1), (1, 0)):
    a = src[:H - dy, :W - dx]; b = src[dy:, dx:]
    d = (a != b) & (a > 0) & (b > 0) & ~J[:H - dy, :W - dx] & ~J[dy:, dx:]
    for y, x in zip(*np.where(d)):
        if 186 <= y < 560 and 96 <= x < 934: seam.append((int(x + dx), int(y + dy)))
seam = sorted(set(seam))
J2 = J.copy()
for x, y in seam: J2[y, x] = True
lab, comps = label4(~J2[VIS])
sliver = []
seamset = set(seam)
for comp in comps:
    if len(comp) < 7:      # 第二階段：小圓石鋪面本來就有小碎石，只處理「貼著接縫」的碎片
        pts = [(int(x + 96), int(y + 186)) for y, x in comp]
        if any((px + dx, py + dy) in seamset for px, py in pts for dx in (-1, 0, 1) for dy in (-1, 0, 1)): sliver += pts
speck = []
n4 = np.zeros((H, W), int); n4[1:] += J2[:-1]; n4[:-1] += J2[1:]; n4[:, 1:] += J2[:, :-1]; n4[:, :-1] += J2[:, 1:]
n8 = n4.copy(); n8[1:, 1:] += J2[:-1, :-1]; n8[1:, :-1] += J2[:-1, 1:]; n8[:-1, 1:] += J2[1:, :-1]; n8[:-1, :-1] += J2[1:, 1:]
iron = (im == np.array(PAL['X1'], np.uint8)).all(-1)
sb = np.zeros((H, W), bool)
for x_, y_ in seam: sb[max(y_ - 10, 0):y_ + 11, max(x_ - 10, 0):x_ + 11] = True
for y, x in zip(*np.where(J2 & (n8 == 0) & ~iron & sb)):      # 孤立石縫點：只處理接縫附近（石面上的單點是 codex 畫的小凹痕，留著）
    if 187 <= y < 559 and 97 <= x < 933 and (x, y) not in set(seam):
        speck.append((int(x), int(y), '#%02x%02x%02x' % tuple(im[y, x - 1])))
with open(os.path.join(A, 'fix_ground_data.py'), 'w') as f:
    f.write('# 由 find_ground_defects.py 找出的壞點座標（地面貼圖 1024×560 的像素座標）。\n')
    f.write('SEAM = %r\n\nSLIVER = %r\n\nSPECK = %r\n' % (seam, sliver, speck))
print('seam', len(seam), 'sliver', len(sliver), 'speck', len(speck))
