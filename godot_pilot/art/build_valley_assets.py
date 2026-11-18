#!/usr/bin/env python3
"""楓林溪谷素材（codex → 真點陣）：valley_rock、valley_moss（平鋪）、stone_lantern、river_rocks（切成三顆）
  python3 -I art/build_valley_assets.py"""
import os, sys, json, glob
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import depixel
from build_mill_assets import quant, crop_pad
T = os.path.join(A, '..', 'tex')
meta_p = os.path.join(T, 'meta.json'); meta = json.load(open(meta_p))
def raw(n): return Image.open(sorted(glob.glob(os.path.join(A, 'raw', n + '_v*.png')))[-1]).convert('RGBA')
def save(name, a):
    Image.fromarray(a).save(os.path.join(T, name + '.png')); meta[name] = [a.shape[1], a.shape[0]]; print(name, a.shape)
for n, k, fp in (('valley_rock', 36, None), ('valley_moss', 40, None)):
    im = raw(n); o, p, _ = depixel(im, True, force_p=fp); print(n, 'pitch', p, im.size)
    save('pilot_' + n, quant(o, k))
im = raw('stone_lantern'); o, p, _ = depixel(im, False, force_p=im.size[1] / 80.0); print('lantern pitch', p)
save('pilot_stone_lantern', crop_pad(quant(o, 28)))
im = raw('river_rocks'); o, p, _ = depixel(im, False, force_p=im.size[0] / 144.0); print('rocks pitch', p)
o = quant(o, 28)
cols = (o[..., 3] > 127).any(0)
runs, x = [], 0
while x < len(cols):
    if cols[x]:
        s = x
        while x < len(cols) and cols[x]: x += 1
        if x - s > 4: runs.append((s, x))
    x += 1
print('runs', runs)
for nm, (a, b) in zip('abc', runs[:3]): save('pilot_rock_' + nm, crop_pad(o[:, a:b].copy()))
json.dump(meta, open(meta_p, 'w'))
