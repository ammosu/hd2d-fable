#!/usr/bin/env python3
"""把 post.py 切出來的多格（name_0..n-1）以「腳底中心」對齊，拼成等寬的動畫橫條 tex/<out>.png，並寫入 meta 的 frames。
python3 tools/sheet.py out name n [anchor=feet|center]"""
import json, os, sys
import numpy as np
from PIL import Image
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
out, name, n = sys.argv[1], sys.argv[2], int(sys.argv[3]); anchor = sys.argv[4] if len(sys.argv) > 4 else 'feet'
PAD = 4
fr = []
for i in range(n):
    a = np.array(Image.open(os.path.join(T, f'{name}_{i}.png')).convert('RGBA'))
    ys, xs = np.where(a[..., 3] > 0); a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    al = a[..., 3] > 0
    if anchor == 'feet':
        cols = np.where(al[-4:].any(axis=0))[0]; ax = int(round((cols.min() + cols.max()) / 2))
    else: ax = a.shape[1] // 2
    fr.append((a, ax))
L = max(ax for a, ax in fr); R = max(a.shape[1] - ax for a, ax in fr); Hh = max(a.shape[0] for a, ax in fr)
fw, fh = L + R + 2 * PAD, Hh + 2 * PAD
sheet = np.zeros((fh, fw * n, 4), np.uint8)
for i, (a, ax) in enumerate(fr):
    x0 = i * fw + PAD + L - ax; y0 = fh - PAD - a.shape[0]
    sheet[y0:y0 + a.shape[0], x0:x0 + a.shape[1]] = a
Image.fromarray(sheet, 'RGBA').save(os.path.join(T, out + '.png'))
mp = os.path.join(T, 'meta.json'); meta = json.load(open(mp)); meta[out] = [fw * n, fh]; meta[out + '_frames'] = n; json.dump(meta, open(mp, 'w'), indent=1)
print(out, fw, fh, 'x', n)
