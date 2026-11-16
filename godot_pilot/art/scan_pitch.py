#!/usr/bin/env python3
"""格距掃描：對每個候選格距還原後放大回去，和原圖比誤差；列出誤差最小的幾個（真格距的整數倍分之一也會低，要配合看圖判斷）。 python3 art/scan_pitch.py raw/x.png lo hi step"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from restore import *
f = sys.argv[1]; lo, hi, st = float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
im = Image.open(f).convert('RGBA'); res = []
for p in np.arange(lo, hi, st):
    try:
        o, _, _ = depixel(im, im.getextrema()[3][0] == 255, force_p=float(p)); e = check(f, o, p)
        a = o[..., 3] > 0; ys, xs = np.where(a); res.append((e, round(float(p), 2), xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))
    except Exception as ex: pass
for r in sorted(res)[:6]: print('  err %.1f pitch %s content %dx%d' % r)
