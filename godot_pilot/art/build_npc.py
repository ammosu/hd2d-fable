#!/usr/bin/env python3
"""四個 NPC：art/raw/<name>_vN.png → art/work/<name>_restored.png（真點陣、量化到共用調色盤的子集合、四周 4 點陣透明邊；未手修）
格距：先用「同色連續長度」的統計估出大約的格距，再在附近掃描、取放大回去誤差最小者（codex 的格子不完全均勻，所以追蹤格線還原）。 python3 art/build_npc.py [name ...]"""
import os, sys
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import depixel, to_palette, check
from palette import PAL, sub
PAD = 4
# 分色類量化：整張一起取最近色時，codex 偏粉偏亮的顏色會被吸到別的部位的色階（主角的紅髮就被吸成膚色），所以先依原圖顏色分類，各類只能用自己的色階
DEF = {'dark': ['D0', 'D1', 'R0'], 'skin': ['K', 'X0', 'R7'], 'white': ['X0', 'M2', 'P5'], 'grey': ['M1', 'M0', 'S6', 'W3'], 'yellow': ['L2', 'P2', 'P3', 'P1'],
       'orange': ['L1', 'R6', 'H3', 'D5'], 'red': ['R1', 'R2', 'R3', 'R4', 'R5'], 'green': ['G'], 'olive': ['G1', 'G2', 'G3'], 'brown': ['D1', 'D2', 'D3', 'D4', 'D5'], 'pink': ['R7', 'K1']}
NPC = {
 'baker':  dict(raw='baker_v3.png', pitch=(19.0, 21.2), cls={'orange': ['R5', 'R6', 'L1', 'L2', 'D5'], 'red': ['R2', 'R3', 'R4', 'R5'], 'yellow': ['L2', 'P2', 'L1']},
                band=(0, 36, {'red': ['D2', 'D3', 'D4'], 'orange': ['D4', 'D5'], 'brown': ['D1', 'D2', 'D3', 'D4']})),      # 頭部（第 0–35 列）的紅褐 = 頭髮 → 木褐色階
 'child':  dict(raw='child_v1.png', pitch=(24.5, 27.5), cls={'orange': ['D4', 'D5'], 'red': ['D2', 'D3', 'R7'], 'yellow': ['D5', 'P2'], 'grey': ['W1', 'W2', 'W3']}),
 'cat':    dict(raw='cat_v3.png', pitch=(22.5, 24.8), cls={'orange': ['R6', 'H3', 'L1'], 'brown': ['D2', 'D3', 'D4', 'H2'], 'red': ['H2', 'R6'], 'yellow': ['H3', 'P4'], 'grey': ['M1', 'P4']}),
 'fisher': dict(raw='fisher_v1.png', pitch=(18.2, 19.6), cls={'orange': ['D5', 'L1', 'R6'], 'grey': ['M1', 'M0', 'W2', 'W3', 'S3'], 'red': ['R6', 'R7', 'D4']},
                band=(0, 22, {k: ['L2', 'P2', 'P3', 'P1', 'D4'] for k in ('skin', 'orange', 'red', 'brown', 'yellow', 'pink', 'white', 'grey')})),      # 草帽（第 0–21 列）一律用稻草色階
 'npc_veg': dict(raw='npc_veg_v1.png', pitch=(19.2, 20.6), cls={'yellow': ['L2', 'P2', 'P3', 'P1'], 'red': ['R1', 'R2', 'R3', 'R4']}),          # 新區：賣菜婦人
 'npc_girl': dict(raw='npc_girl_v1.png', pitch=(22.8, 24.4), cls={'yellow': ['H3', 'L2', 'P2', 'D5'], 'orange': ['H3', 'D5', 'L1']}),        # 新區：提籃小女孩（金棕髮）
 'npc_accordion': dict(raw='npc_accordion_v1.png', pitch=(20.4, 21.8)),                                                                   # 新區：拉手風琴的老爺爺
}
def classify(o):
    r, g, b = [o[..., i].astype(np.float32) for i in range(3)]; mx = np.maximum(np.maximum(r, g), b); mn = np.minimum(np.minimum(r, g), b); sm = r + g + b
    cls = np.full(o.shape[:2], 'brown', dtype=object)
    cls[(r > 130) & (g < 95) & (r - g > 70)] = 'red'
    cls[(r > 175) & (g > 75) & (g < 165) & (b < 110) & (r - b > 90)] = 'orange'
    cls[(r > 185) & (g > 140) & (b < 150) & (r - b > 75)] = 'yellow'
    cls[(np.abs(r - g) < 24) & (g > b + 28) & (r < 195) & (sm > 170)] = 'olive'
    cls[(g > r + 6) & (g > b + 6)] = 'green'
    cls[(mx - mn < 38) & (sm > 300)] = 'grey'
    cls[(mn > 170) & (mx - mn < 55)] = 'white'
    cls[(r > 205) & (g > 150) & (b > 105) & (r - b > 38) & (r - b < 115) & ~((mn > 170) & (mx - mn < 55))] = 'skin'
    cls[(r > 200) & (g > 110) & (g < 165) & (b > 100) & (b < 165)] = 'pink'
    cls[sm < 170] = 'dark'
    return cls
for name in (sys.argv[1:] or list(NPC)):
    cfg = NPC[name]; f = os.path.join(A, 'raw', cfg['raw']); im = Image.open(f).convert('RGBA'); best = None
    for p in np.arange(cfg['pitch'][0], cfg['pitch'][1], 0.1):
        o, _, _ = depixel(im, False, force_p=float(p)); e = check(f, o, p)
        if best is None or e < best[0]: best = (e, float(p), o)
    e, p, o = best
    a = o[..., 3] > 127; ys, xs = np.where(a); o = o[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    o[..., 3] = np.where(o[..., 3] > 127, 255, 0)
    cls = classify(o); q = o.copy(); table = dict(DEF); table.update(cfg.get('cls', {}))
    for k, cols in table.items():
        m = (cls == k) & (o[..., 3] > 0)
        if m.any(): q[m] = to_palette(o, sub(*cols))[m]
    if 'band' in cfg:
        y0, y1, tb = cfg['band']; rows = np.zeros(o.shape[:2], bool); rows[max(y0 - PAD, 0):max(y1 - PAD, 0)] = True
        for k, cols in tb.items():
            m = (cls == k) & (o[..., 3] > 0) & rows
            if m.any(): q[m] = to_palette(o, sub(*cols))[m]
    q[o[..., 3] == 0] = 0
    out = np.zeros((q.shape[0] + PAD * 2, q.shape[1] + PAD * 2, 4), np.uint8); out[PAD:-PAD, PAD:-PAD] = q
    print(f'{name}: pitch {p:.1f} err {e:.1f} sprite {out.shape[1]}x{out.shape[0]} (content {q.shape[1]}x{q.shape[0]}) colors {len(set(map(tuple, out.reshape(-1, 4)))) - 1}')
    Image.fromarray(out).save(os.path.join(A, 'work', f'{name}_restored.png'))
