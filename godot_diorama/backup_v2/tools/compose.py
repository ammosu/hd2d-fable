#!/usr/bin/env python3
"""把 codex 生的街面／堤岸分段拼成這條街專用的大張貼圖（不平鋪）：tex/street.png（768×109 = 24 m × 3.4 m）、tex/quay.png（768×40 = 24 m × 1.25 m）
python3 tools/compose.py"""
import json, os
import numpy as np
from PIL import Image
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
L = lambda n: np.array(Image.open(os.path.join(T, n + '.png')).convert('RGB'))
a, b, c = L('street_a'), L('street_b'), L('street_c')
segs = [c[9:118], a[9:118], b[9:118], a[9:118][:, ::-1]]
st = np.concatenate(segs, axis=1)
# 分段接縫處放一條窄的排水溝石（深色石條），蓋住接不上的石縫
for x in (192, 384, 576):
    for y in range(st.shape[0]):
        blk = (y // 7) % 2
        st[y, x - 2:x + 2] = (st[y, x - 2:x + 2] * 0.55 + np.array([10, 8, 14])).astype(np.uint8) if (y % 7) else (st[y, x - 2:x + 2] * 0.3).astype(np.uint8)
    st[:, x - 3] = (st[:, x - 3] * 0.45).astype(np.uint8); st[:, x + 2] = (st[:, x + 2] * 0.45).astype(np.uint8)
Image.fromarray(st).save(os.path.join(T, 'street.png'))
qa, qb = L('quay_a'), L('quay_b')
strip = lambda q: np.concatenate([q[0:22], q[100:118]], axis=0)       # 壓頂石＋一排石塊，接上最底下潮濕長苔的兩排
qy = np.concatenate([strip(qa), strip(qb), strip(qa)[:, ::-1], strip(qb)[:, ::-1]], axis=1)
Image.fromarray(qy).save(os.path.join(T, 'quay.png'))
m = json.load(open(os.path.join(T, 'meta.json')))
m['street'] = [st.shape[1], st.shape[0]]; m['quay'] = [qy.shape[1], qy.shape[0]]
json.dump(m, open(os.path.join(T, 'meta.json'), 'w'), indent=1)
print('street', st.shape, 'quay', qy.shape)
