#!/usr/bin/env python3
"""量測截圖：亮度百分位（2/50/98）與飽和像素的色相分布。 python3 tools/measure.py a.png b.png ..."""
import sys, colorsys
import numpy as np
from PIL import Image
for f in sys.argv[1:]:
    im = Image.open(f).convert('RGB')
    a = np.array(im).astype(float)
    l = a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114
    hsv = np.array(im.convert('HSV')).astype(float)
    h = hsv[..., 0] / 255 * 360; s = hsv[..., 1] / 255; v = hsv[..., 2] / 255
    sat = (s > 0.35) & (v > 0.2)
    n = max(sat.sum(), 1)
    ro = (sat & ((h < 50) | (h >= 330))).sum() / n * 100
    ye = (sat & (h >= 50) & (h < 70)).sum() / n * 100
    gr = (sat & (h >= 70) & (h < 170)).sum() / n * 100
    bp = (sat & (h >= 170) & (h < 330)).sum() / n * 100
    p = np.percentile(l, [2, 50, 98])
    print(f"{f.split('/')[-1]}: 亮度 2/50/98 = {p[0]:.1f}/{p[1]:.1f}/{p[2]:.1f} | 飽和像素佔 {sat.mean()*100:.0f}%：紅橘 {ro:.0f}%、黃 {ye:.0f}%、綠 {gr:.0f}%、藍紫 {bp:.0f}%")
