#!/usr/bin/env python3
"""水車磨坊的素材（codex 生成 → 還原成真點陣）：
  mill_soil → tex/pilot_mill_soil.png（麥田地面，平鋪）
  mill_wheat → tex/pilot_mill_wheat.png（一排麥子）
  mill_hay → tex/pilot_hay_a.png、pilot_hay_b.png（乾草堆、乾草捆）
  npc_miller → tex/pilot_npc_miller_anim.png（扛麵粉袋的工人，2 格：原圖／上半身下沉 1 點陣）
  python3 -I art/build_mill_assets.py"""
import os, sys, json, glob
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import depixel
T = os.path.join(A, '..', 'tex')
meta_p = os.path.join(T, 'meta.json'); meta = json.load(open(meta_p))
def raw(n): return Image.open(sorted(glob.glob(os.path.join(A, 'raw', n + '_v*.png')))[-1]).convert('RGBA')
def quant(o, n=32):
    al = o[..., 3].copy()
    q = np.array(Image.fromarray(o[..., :3]).quantize(n, dither=Image.Dither.NONE).convert('RGB'))
    return np.dstack([q, al])
def crop_pad(o):
    o[..., 3] = np.where(o[..., 3] > 127, 255, 0); o[o[..., 3] == 0] = 0
    ys, xs = np.where(o[..., 3] > 0); o = o[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    out = np.zeros((o.shape[0] + 8, o.shape[1] + 8, 4), np.uint8); out[4:-4, 4:-4] = o; return out
def save(name, a, frames=None):
    Image.fromarray(a).save(os.path.join(T, name + '.png'))
    meta[name] = [a.shape[1], a.shape[0]]
    if frames: meta[name + '_frames'] = frames
    print(name, a.shape)
# 地面
o, p, _ = depixel(raw('mill_soil'), True); print('soil pitch', p)
save('pilot_mill_soil', quant(o, 28))
# 麥子：一排
o, p, _ = depixel(raw('mill_wheat'), False, force_p=11.31); print('wheat pitch', p)
save('pilot_mill_wheat', crop_pad(quant(o, 44)))
# 乾草：左右兩個分開
o, p, _ = depixel(raw('mill_hay'), False); print('hay pitch', p)
o = quant(o, 24)
cols = (o[..., 3] > 127).any(0); xs = np.where(cols)[0]
gaps = [x for x in range(xs.min(), xs.max()) if not cols[x]]
cut = gaps[len(gaps) // 2]
save('pilot_hay_a', crop_pad(o[:, :cut].copy())); save('pilot_hay_b', crop_pad(o[:, cut:].copy()))
# 工人：2 格呼吸
o, p, _ = depixel(raw('npc_miller'), False, force_p=20.2); print('miller pitch', p)
b = crop_pad(quant(o, 36))
cut = int(b.shape[0] * 0.62)
f1 = b.copy(); f1[:cut] = 0
up = b[:cut]; ys, xs = np.where(up[..., 3] > 0)
for y, x in zip(ys, xs):
    if y + 1 < f1.shape[0]: f1[y + 1, x] = up[y, x]
save('pilot_npc_miller_anim', np.concatenate([b, f1], axis=1), 2)
json.dump(meta, open(meta_p, 'w'))
