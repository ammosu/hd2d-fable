# 亮度百分位：python3 -I tools/measure.py a.png b.png ...
import sys, numpy as np
from PIL import Image
for f in sys.argv[1:]:
    a = np.array(Image.open(f).convert('RGB'), dtype=np.float32)
    l = a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114
    print(f'{f}: p5={np.percentile(l,5):.0f} p25={np.percentile(l,25):.0f} p50={np.percentile(l,50):.0f} p95={np.percentile(l,95):.0f}')
