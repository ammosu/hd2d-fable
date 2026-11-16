#!/usr/bin/env python3
"""紅屋頂手修：art/work/roof_restored.png（198×89）→ tex/pilot_roof.png ＋ art/sheet_roof.png
每一輪都是 9 倍放大看過後，對指定座標（或以指定座標為種子的那一片瓦）直接改像素。 python3 art/fix_roof.py"""
import os, sys
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from fixlib import *
c = Canvas(os.path.join(A, 'work', 'roof_restored.png'))
DARK = {PAL[k] for k in ('R0', 'R1', 'D0', 'D1', 'D2')}
RAMP = ['R1', 'R2', 'R3', 'R4', 'R5', 'R6']
def tile(x, y, base, rim=None, limit=190):
    """重畫一片瓦：從種子 (x, y) 出發，把被深色瓦縫圍住的整片瓦塗成 base，貼著下緣瓦縫的那一列塗成 rim（瓦的厚邊，亮一階）"""
    if c.get(x, y) in DARK: print('  !! seed on outline', x, y); return
    if rim is None: rim = RAMP[min(RAMP.index(base) + 1, 5)] if base in RAMP else base
    st = [(x, y)]; seen = {(x, y)}
    while st:
        cx, cy = st.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < 198 and 0 <= ny < 89 and (nx, ny) not in seen and c.get(nx, ny) not in DARK: seen.add((nx, ny)); st.append((nx, ny))
        if len(seen) > limit: print('  !! tile leak', x, y); return
    for px_, py_ in seen:
        below_dark = py_ + 1 < 89 and c.get(px_, py_ + 1) in DARK and (px_, py_ + 1) not in seen
        c.px(px_, py_, rim if below_dark else base)

# ================================================================ 第 1 輪
# --- 斑駁的瓦（量化後一片瓦裡兩三個顏色交錯成亂點）：逐片重畫成單一底色＋下緣亮邊
for x, y, b in [(48, 22, 'R4'), (130, 24, 'R2'), (110, 72, 'R2'), (182, 24, 'R2'), (178, 52, 'R4'), (20, 84, 'R3'), (96, 42, 'R2'), (136, 34, 'R3'),
                (62, 4, 'R4'), (100, 4, 'R4'), (150, 4, 'R5'), (22, 4, 'R4'), (186, 4, 'R4'), (128, 42, 'R4'), (190, 50, 'R3')]:
    tile(x, y, b)
# --- 色差太少（幾乎全是同兩階紅）：挑出散開的瓦片改底色——褪色偏粉的舊瓦、偏橘的新補瓦、燒得較深的瓦
for x, y, b in [(8, 13, 'R2'), (40, 13, 'R5'), (72, 13, 'R3'), (118, 13, 'R2'), (160, 13, 'R4'), (190, 13, 'R5'),
                (14, 24, 'R4'), (86, 24, 'R2'), (112, 24, 'R5'), (152, 24, 'R4'),
                (4, 34, 'R2'), (24, 34, 'R4'), (56, 34, 'R2'), (104, 34, 'R5'), (170, 34, 'R2'),
                (8, 44, 'R4'), (60, 44, 'R2'), (112, 44, 'R4'), (144, 44, 'R2'), (176, 44, 'R5'),
                (14, 54, 'R2'), (46, 54, 'R5'), (78, 54, 'R2'), (124, 54, 'R4'), (160, 54, 'R2'),
                (6, 64, 'R4'), (58, 64, 'R2'), (90, 64, 'R4'), (132, 64, 'R5'), (166, 64, 'R2'),
                (22, 74, 'R2'), (70, 74, 'R4'), (104, 74, 'R2'), (150, 74, 'R4'), (186, 74, 'R2'),
                (36, 84, 'R4'), (86, 84, 'R2'), (120, 84, 'R5'), (170, 84, 'R3')]:
    tile(x, y, b)
tile(96, 24, 'R7', 'M1'); tile(30, 64, 'R7', 'M1'); tile(144, 84, 'R7', 'M1')          # 褪色偏粉的舊瓦
tile(40, 74, 'R6', 'R7'); tile(154, 34, 'R6', 'R7')                                    # 兩片較新的橘色補瓦
# --- 灰色補瓦（石板瓦）：原本下緣有粉色雜點，重畫成灰階＋亮邊
tile(158, 44, 'S4', 'S6')
c.end_round('round1 tiles repaint/variation')
if os.path.exists(os.path.join(A, 'fix_roof_r2.py')): exec(open(os.path.join(A, 'fix_roof_r2.py')).read())
c.save(os.path.join(A, 'work', 'roof_fixed.png'), rgb=True)
c.save(os.path.join(A, '..', 'tex', 'pilot_roof.png'), rgb=True)
print('total changed', c.total())
sheet(os.path.join(A, 'work', 'roof_restored.png'), os.path.join(A, 'work', 'roof_fixed.png'), [(0, 0, 100, 50), (98, 0, 198, 50), (40, 39, 140, 89)], os.path.join(A, 'sheet_roof.png'), k=8)
