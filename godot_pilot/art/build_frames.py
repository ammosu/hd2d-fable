#!/usr/bin/env python3
"""各站前景框景：codex 原圖 → 縮小、預先糊成失焦前景 → tex/pilot_frame_wheat.png、pilot_frame_net.png"""
import os, glob, json
import numpy as np
from PIL import Image, ImageFilter
A = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(A, '..', 'tex')
meta = json.load(open(os.path.join(T, 'meta.json')))
for n in ('frame_wheat', 'frame_net'):
    im = Image.open(sorted(glob.glob(os.path.join(A, 'raw', n + '_v*.png')))[-1]).convert('RGBA')
    im = im.resize((576, int(576 * im.height / im.width)), Image.LANCZOS)
    a = np.array(im).astype(float)
    # 預乘後模糊，避免透明邊緣出現黑邊
    rgb = a[..., :3] * (a[..., 3:4] / 255.0)
    pm = np.dstack([rgb, a[..., 3]]).clip(0, 255).astype(np.uint8)
    b = np.array(Image.fromarray(pm).filter(ImageFilter.GaussianBlur(5))).astype(float)
    al = b[..., 3:4] / 255.0
    out = np.dstack([np.where(al > 0.01, b[..., :3] / np.maximum(al, 0.01), 0), b[..., 3]]).clip(0, 255).astype(np.uint8)
    Image.fromarray(out).save(os.path.join(T, 'pilot_' + n + '.png')); meta['pilot_' + n] = [out.shape[1], out.shape[0]]
    print(n, out.shape)
json.dump(meta, open(os.path.join(T, 'meta.json'), 'w'))
