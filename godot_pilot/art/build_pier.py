#!/usr/bin/env python3
"""棧橋木板貼圖 tex/pilot_planks.png（128×64＝8 條木板，每條 8 點陣高＝0.25 m，32 PPM）。
參考 MengTo 3d-wood-material 的原則改成點陣版：木紋順著板長、每塊板子色調與紋路不同、板緣一條亮邊、板縫暗線、偶有節疤與裂紋。"""
import os, json, random
from PIL import Image
import sys; sys.path.insert(0, os.path.dirname(__file__))
from palette import PAL
T = os.path.join(os.path.dirname(__file__), '..', 'tex')
rnd = random.Random(7)
# 每條板子的色階（暗→亮）：曬舊的灰褐木與較新的褐木交錯
ramps = [
    ['D2', 'D3', 'D4', 'D5', 'P0'],
    ['W0', 'W1', 'W2', 'W3', 'W4'],
    ['D3', 'D4', 'D5', 'P0', 'P1'],
    ['D2', 'W1', 'W2', 'W3', 'W4'],
]
W, H = 128, 64
im = Image.new('RGB', (W, H))
px = im.load()
for b in range(8):
    r = [PAL[k] for k in ramps[rnd.randrange(len(ramps))]]
    y0 = b * 8
    base = 2 if rnd.random() < 0.7 else 3
    for x in range(W):
        px[x, y0] = r[min(base + 1, 4)]               # 受光的板緣
        for y in range(1, 7): px[x, y0 + y] = r[base]
        px[x, y0 + 7] = PAL['D0']                     # 板縫
    # 木紋：沿板長的深色細線，偶爾錯一列（波動）
    for _ in range(rnd.randint(7, 11)):
        x = rnd.randrange(W); y = rnd.randint(1, 6); n = rnd.randint(8, 40); c = r[base - 1]
        for i in range(n):
            if rnd.random() < 0.06: y = max(1, min(6, y + rnd.choice((-1, 1))))
            px[(x + i) % W, y0 + y] = c
    # 較亮的纖維
    for _ in range(rnd.randint(3, 6)):
        x = rnd.randrange(W); y = rnd.randint(2, 5); n = rnd.randint(5, 18)
        for i in range(n): px[(x + i) % W, y0 + y] = r[base + 1]
    # 節疤（暗心＋亮圈）
    if rnd.random() < 0.6:
        x = rnd.randrange(W); y = rnd.randint(2, 4)
        for dx in (-2, -1, 0, 1, 2): px[(x + dx) % W, y0 + y] = r[base + 1]
        px[x % W, y0 + y] = r[0]; px[(x + 1) % W, y0 + y] = r[0]; px[x % W, y0 + y + 1] = r[base - 1]
    # 乾裂（最暗色短線）
    if rnd.random() < 0.5:
        x = rnd.randrange(W); y = rnd.randint(2, 5)
        for i in range(rnd.randint(4, 10)): px[(x + i) % W, y0 + y] = r[0]
im.save(os.path.join(T, 'pilot_planks.png'))
mp = os.path.join(T, 'meta.json'); m = json.load(open(mp)); m['pilot_planks'] = [W, H]; json.dump(m, open(mp, 'w'))
im.resize((W * 6, H * 6), Image.NEAREST).save('/tmp/pilot_planks_x6.png')
print('ok')
