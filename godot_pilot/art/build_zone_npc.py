#!/usr/bin/env python3
"""新區 NPC 的動畫格：art/work/<name>_plain.png（賣菜婦人、老爺爺：量化到共用調色盤）／未量化的還原圖（小女孩：調色盤沒有粉紅色，量化後裙子會變米色）
→ tex/pilot_<name>_anim.png。動作只搬像素：
  婦人、小女孩：0 原圖／1 上半身下沉 1 點陣（呼吸）
  老爺爺：0 原圖／1 上半身往左 1 點陣／2 往右 1 點陣（隨音樂搖擺）
  python3 -I art/build_zone_npc.py"""
import os, sys, json
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import depixel
T = os.path.join(A, '..', 'tex')
def load(name, pitch, plain=True):
    if plain: return np.array(Image.open(os.path.join(A, 'work', f'{name}_plain.png')).convert('RGBA'))
    o, _, _ = depixel(Image.open(os.path.join(A, 'raw', f'{name}_v1.png')).convert('RGBA'), False, force_p=pitch)
    a = o[..., 3] > 127; ys, xs = np.where(a); o = o[ys.min():ys.max() + 1, xs.min():xs.max() + 1]; o[..., 3] = np.where(o[..., 3] > 127, 255, 0)
    out = np.zeros((o.shape[0] + 8, o.shape[1] + 8, 4), np.uint8); out[4:-4, 4:-4] = o; return out
def shift(base, cut, dx, dy):
    f = base.copy(); f[:cut] = 0
    up = base[:cut]
    ys, xs = np.where(up[..., 3] > 0)
    for y, x in zip(ys, xs):
        yy, xx = y + dy, x + dx
        if 0 <= yy < f.shape[0] and 0 <= xx < f.shape[1]: f[yy, xx] = up[y, x]
    # 下沉時，原本上半身最下一列與下半身之間的縫用下半身補（保持連續）
    return f
meta_p = os.path.join(T, 'meta.json'); meta = json.load(open(meta_p))
for name, pitch, plain, frames in (('npc_veg', 20.0, True, [(0, 0), (0, 1)]), ('npc_girl', 22.8, False, [(0, 0), (0, 1)]), ('npc_accordion', 20.4, True, [(0, 0), (-1, 0), (1, 0)]), ('npc_painter', 20.2, False, [(0, 0), (0, 1)])):
    b = load(name, pitch, plain)
    cut = int(b.shape[0] * 0.62)
    fr = [b if (dx, dy) == (0, 0) else shift(b, cut, dx, dy) for dx, dy in frames]
    if name == 'npc_painter':      # 畫架不跟著呼吸：右側（畫架）那幾欄維持原圖
        for f in fr[1:]: f[:, 34:] = b[:, 34:]
    sheet = np.concatenate(fr, axis=1)
    Image.fromarray(sheet).save(os.path.join(T, f'pilot_{name}_anim.png'))
    meta[f'pilot_{name}_anim'] = [sheet.shape[1], sheet.shape[0]]; meta[f'pilot_{name}_anim_frames'] = len(fr)
    print(name, sheet.shape)
json.dump(meta, open(meta_p, 'w'))
