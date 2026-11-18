#!/usr/bin/env python3
"""新區地面：art/raw/z{w,e}_{0..13}_v*.png（codex 分塊，每塊約 219×146 點陣）→ tex/pilot_zone_{w,e}.png（1472×320，32 PPM）
對應世界座標：x 46 m（西區 −62..−16、東區 16..62）× z −7.6..2.4（第 0 列 = z −7.6，最後一列 = 堤岸邊）。
還原與拼接沿用 build_ground.py 的 load()／paste_seam()（固定 7 px 格距、逐塊石頭上色、沿石縫切開重疊的 18 點陣）。
排法：下排（靠堤岸，有壓頂石）用分塊 7..13；上排用 0..6；最上面一段（第 0..45 列）先用上排分塊的水平翻轉鋪底。
  python3 -I art/build_zone_ground.py [w|e ...]"""
import os, sys, glob
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
import build_ground as bg
W, H = 1472, 320
bg.W, bg.H = W, H
def latest(name):
    fs = sorted(glob.glob(os.path.join(A, 'raw', name + '_v*.png')), key=lambda f: int(f.rsplit('_v', 1)[1][:-4]))
    return '_v' + fs[-1].rsplit('_v', 1)[1][:-4]
for z in (sys.argv[1:] or ['w', 'e']):
    P = []
    for i in range(14):
        n = f'z{z}_{i}'; bg.VER[n] = latest(n)
        P.append(bg.load(n, 7.0))
    canvas = np.zeros((H, W, 3), np.uint8)
    # 鋪底：上排分塊翻轉（只露在最上面一段與左右邊角）
    for row, oy in ((0, -100), (0, 46), (0, H - 146)):
        for k, ox in enumerate(range(-60, W, 201)):
            src = P[k % 7][:, ::-1]
            y0, y1 = max(oy, 0), min(oy + src.shape[0], H); x0, x1 = max(ox, 0), min(ox + src.shape[1], W)
            canvas[y0:y1, x0:x1] = src[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    filled = np.zeros((H, W), bool); log = []
    for k in range(7):
        ox = 10 + k * 207
        for idx, oy in ((k, 46), (k + 7, H - P[k + 7].shape[0])):
            pc = P[idx]
            bg.paste_seam(canvas, filled, pc, ox, oy, log)
    out = os.path.join(A, '..', 'tex', f'pilot_zone_{z}.png')
    Image.fromarray(canvas).save(out)
    Image.fromarray(canvas).resize((W * 2, H * 2), Image.NEAREST).save(os.path.join(A, 'work', f'zone_{z}_x2.png'))
    print(z, canvas.shape, 'seams', len(log))
