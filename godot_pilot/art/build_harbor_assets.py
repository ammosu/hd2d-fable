#!/usr/bin/env python3
"""出海口燈塔素材（codex → 真點陣）：lighthouse、harbor_boat、harbor_props（切三件）、gull（兩格動畫）
  python3 -I art/build_harbor_assets.py"""
import os, sys, json, glob
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import depixel
T = os.path.join(A, '..', 'tex')
meta_p = os.path.join(T, 'meta.json'); meta = json.load(open(meta_p))
def raw(n): return Image.open(sorted(glob.glob(os.path.join(A, 'raw', n + '_v*.png')))[-1]).convert('RGBA')
def quant(o, n=32):
    al = o[..., 3].copy(); q = np.array(Image.fromarray(o[..., :3]).quantize(n, dither=Image.Dither.NONE).convert('RGB')); return np.dstack([q, al])
def crop_pad(o):
    o[..., 3] = np.where(o[..., 3] > 127, 255, 0); o[o[..., 3] == 0] = 0
    ys, xs = np.where(o[..., 3] > 0); o = o[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    out = np.zeros((o.shape[0] + 8, o.shape[1] + 8, 4), np.uint8); out[4:-4, 4:-4] = o; return out
def runs(o):
    cols = (o[..., 3] > 127).any(0); r, x = [], 0
    while x < len(cols):
        if cols[x]:
            s = x
            while x < len(cols) and cols[x]: x += 1
            if x - s > 3: r.append((s, x))
        x += 1
    return r
def save(name, a, fr=None):
    Image.fromarray(a).save(os.path.join(T, name + '.png')); meta[name] = [a.shape[1], a.shape[0]]
    if fr: meta[name + '_frames'] = fr
    print(name, a.shape)
im = raw('lighthouse'); o, p, _ = depixel(im, False, force_p=im.size[0] / 72.0); save('pilot_lighthouse', crop_pad(quant(o, 40)))
im = raw('harbor_boat'); o, p, _ = depixel(im, False, force_p=im.size[0] / 160.0); save('pilot_harbor_boat', crop_pad(quant(o, 40)))
im = raw('harbor_props'); o, p, _ = depixel(im, False, force_p=im.size[0] / 144.0); o = quant(o, 32)
r = runs(o); print('props runs', r)
for nm, (a, b) in zip('abc', r[:3]): save('pilot_harbor_' + nm, crop_pad(o[:, a:b].copy()))
im = raw('gull'); o, p, _ = depixel(im, False, force_p=im.size[0] / 64.0); o = quant(o, 12)
r = runs(o); print('gull runs', r)
fr = [crop_pad(o[:, a:b].copy()) for a, b in r[:2]]
H = max(f.shape[0] for f in fr); W = max(f.shape[1] for f in fr)
sheet = np.zeros((H, W * 2, 4), np.uint8)
for i, f in enumerate(fr):
    y = (H - f.shape[0]) // 2; x = (W - f.shape[1]) // 2
    sheet[y:y + f.shape[0], i * W + x:i * W + x + f.shape[1]] = f
save('pilot_gull', sheet, 2)
json.dump(meta, open(meta_p, 'w'))
