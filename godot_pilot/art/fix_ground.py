#!/usr/bin/env python3
"""地面手修：art/work/ground_restored.png → tex/pilot_plaza.png（RGBA；alpha 是手繪的水窪遮罩）＋ art/sheet_ground.png
每一輪都是「8 倍放大看 → 改指定座標的像素」。python3 art/fix_ground.py"""
import os, sys
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from fixlib import *
import fix_ground_data as D
c = Canvas(os.path.join(A, 'work', 'ground_restored.png'))

# ---------------------------------------------------------------- 第 1 輪：拼接造成的壞點（座標清單在 fix_ground_data.py）
c.pts(D.SEAM, 'S0')                       # 兩塊石頭直接黏在一起的地方補石縫
c.pts(D.SLIVER, 'S0')                     # 被接縫切出來的石頭碎片併入石縫
for x, y, h in D.SPECK: c.px(x, y, h)     # 孤立的石縫雜點改回石面色
c.end_round('round1 seams/slivers/specks')
exec(open(os.path.join(A, 'fix_ground_r2.py')).read()) if os.path.exists(os.path.join(A, 'fix_ground_r2.py')) else None

c.save(os.path.join(A, 'work', 'ground_fixed.png'))
c.save(os.path.join(A, '..', 'tex', 'pilot_plaza.png'))
print('total changed', c.total())
sheet(os.path.join(A, 'work', 'ground_restored.png'), os.path.join(A, 'work', 'ground_fixed.png'), [(416, 440, 520, 500), (600, 420, 704, 480), (728, 440, 832, 500)], os.path.join(A, 'sheet_ground.png'))
