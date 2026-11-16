#!/usr/bin/env python3
"""把 sprite 印成文字格（每個像素 = 調色盤色名），手修時對座標用。 python3 art/grid.py work/x.png [x0 y0 x1 y1]"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from palette import PAL
inv = {v: k for k, v in PAL.items()}
a = np.array(Image.open(sys.argv[1]).convert('RGBA'))
x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6]) if len(sys.argv) > 5 else (0, 0, a.shape[1], a.shape[0])
print('    ' + ''.join('%-3d' % x for x in range(x0, x1)))
for y in range(y0, y1):
    print('%2d  ' % y + ''.join(('.. ' if a[y, x, 3] == 0 else inv.get(tuple(a[y, x, :3]), '??') + ' ') for x in range(x0, x1)))
