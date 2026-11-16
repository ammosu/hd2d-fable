#!/usr/bin/env python3
"""紅屋頂第二版手修：art/work/roof2_restored.png（198×89）→ tex/pilot_roof.png ＋ art/sheet_roof.png
瓦片 8×8 點陣、第 r 排（0–10）從第 7+8r 列開始，奇數排往左錯開 4 點陣；tile(r, c) 的左上角 = (8c − 4·(r 為奇數), 7 + 8r)。
每一輪都是 9 倍放大看過後，對指定的瓦片或座標直接改像素。 python3 art/fix_roof2.py"""
import os, sys
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from fixlib import *
c = Canvas(os.path.join(A, 'work', 'roof2_restored.png'))
from roof_tile import tile_px, RR, DK
def tile(r, cc, i, slip=0, chip=None):
    """重畫第 r 排第 cc 片：i = 底色（0 深紅 1 磚紅 2 亮紅 3 橘褐）；slip = 往下滑幾個點陣；chip = 'l'/'r' 下緣缺一角"""
    x0 = 8 * cc - (4 if r % 2 else 0); y0 = 7 + 8 * r + slip
    for dy in range(8):
        for dx in range(8):
            x, y = x0 + dx, y0 + dy
            if not (0 <= x < 198 and 0 <= y < 89): continue
            k = tile_px(dx, dy, i)
            c.px(x, y, k)
    for s_ in range(slip):
        for dx in range(7): c.px(x0 + dx, 7 + 8 * r + s_, 'R0')          # 滑下去之後上面露出的空隙
    if chip:
        cx = x0 if chip == 'l' else x0 + 5
        for (dx, dy) in ((0, 5), (1, 5), (0, 6), (1, 6), (0, 4) if chip == 'l' else (1, 4)): c.px(cx + dx, y0 + dy, 'R0')

# ================================================================ 第 1 輪
# --- 色差：還原後幾乎整片同一階紅 → 逐片指定底色（排, 片, 色）：深紅的舊瓦、橘褐的補瓦散開排，同色不連成一片；只用紅褐色系
for r, cc, i in [(0, 2, 0), (0, 7, 2), (0, 9, 0), (0, 13, 3), (0, 16, 0), (0, 19, 2), (0, 22, 0),
                 (1, 1, 2), (1, 4, 0), (1, 8, 3), (1, 11, 0), (1, 14, 2), (1, 18, 0), (1, 21, 2), (1, 24, 0),
                 (2, 0, 0), (2, 3, 2), (2, 6, 0), (2, 10, 2), (2, 12, 0), (2, 15, 3), (2, 20, 0), (2, 23, 2),
                 (3, 2, 0), (3, 5, 2), (3, 9, 0), (3, 13, 2), (3, 17, 0), (3, 19, 3), (3, 22, 0),
                 (4, 1, 2), (4, 4, 0), (4, 8, 2), (4, 11, 0), (4, 14, 0), (4, 18, 2), (4, 21, 0), (4, 24, 2),
                 (5, 0, 3), (5, 3, 0), (5, 7, 2), (5, 10, 0), (5, 16, 2), (5, 20, 0), (5, 23, 0),
                 (6, 2, 2), (6, 5, 0), (6, 9, 3), (6, 12, 0), (6, 15, 2), (6, 19, 0), (6, 22, 2),
                 (7, 1, 0), (7, 6, 2), (7, 8, 0), (7, 13, 0), (7, 17, 2), (7, 21, 3), (7, 24, 0),
                 (8, 0, 2), (8, 4, 3), (8, 7, 0), (8, 11, 2), (8, 14, 0), (8, 18, 0), (8, 23, 2),
                 (9, 3, 0), (9, 5, 2), (9, 10, 0), (9, 12, 3), (9, 16, 0), (9, 20, 2), (9, 22, 0),
                 (10, 1, 0), (10, 6, 2), (10, 9, 0), (10, 15, 2), (10, 19, 0), (10, 24, 3)]:
    tile(r, cc, i)
# --- 排得太整齊（像磚牆）：幾片往下滑 1 點陣、幾片下緣缺角
for r, cc, i, slip, chip in [(1, 6, 1, 1, None), (2, 17, 1, 1, None), (4, 6, 1, 1, None), (5, 13, 2, 1, None), (6, 24, 1, 1, None), (8, 9, 1, 1, None), (9, 18, 1, 1, None), (3, 11, 1, 1, None),
                             (2, 8, 1, 0, 'l'), (4, 16, 1, 0, 'r'), (6, 7, 1, 0, 'r'), (7, 15, 1, 0, 'l'), (9, 1, 1, 0, 'r'), (1, 20, 1, 0, 'l'), (8, 21, 1, 0, 'l')]:
    tile(r, cc, i, slip, chip)
# --- 裂瓦：三片各一道 1 點陣寬的斜裂
c.pts([(35, 25), (36, 26), (36, 27), (37, 28)], 'R0'); c.pts([(122, 49), (121, 50), (121, 51), (120, 52)], 'R0'); c.pts([(163, 66), (164, 67), (164, 68), (165, 69), (165, 70)], 'R0')
# --- 屋脊瓦（第 0–6 列）：還原後各節長短不一、接縫斷續 → 整條重畫：每節 12 點陣（11＋1 接縫），上緣兩列亮、中間底色、下緣暗，最下面一列是脊瓦壓在瓦上的深影
RIDGE = [2, 1, 2, 1, 3, 1, 2, 1, 1, 2, 1, 3, 1, 2, 1, 2, 1]
for x in range(198):
    seg = x // 12; e = x % 12 == 11; i = RIDGE[seg % len(RIDGE)]
    for y, k in enumerate([RR[min(i + 1, 3)], RR[min(i + 1, 3)], RR[i], RR[i], RR[i], DK[i], 'R0']):
        c.px(x, y, 'R0' if (e and y < 6) else k)
    if x % 12 in (0, 10): c.px(x, 0, 'R0')      # 每節上緣兩端收圓
# --- 青苔：只長在瓦縫（暗綠小群），左下、右上、中間偏右各一處
KG = {'a': 'G0', 'b': 'G1', 'c': 'G2'}
c.rows(2, 69, ['.bb.', 'bcba', '.ab.'], KG); c.rows(10, 77, ['bcb', '.ab'], KG); c.rows(178, 21, ['.bcb.', 'abcba', '..b..'], KG); c.rows(190, 29, ['bb', 'cb', 'a.'], KG); c.rows(118, 61, ['bcb', 'ab.'], KG); c.rows(60, 37, ['ab', 'bc'], KG)
c.end_round('round1 per-tile colour, slips, chips, cracks, ridge redraw, moss')
if os.path.exists(os.path.join(A, 'fix_roof2_r2.py')): exec(open(os.path.join(A, 'fix_roof2_r2.py')).read())
c.save(os.path.join(A, 'work', 'roof2_fixed.png'), rgb=True)
c.save(os.path.join(A, '..', 'tex', 'pilot_roof.png'), rgb=True)
print('total changed', c.total())
sheet(os.path.join(A, 'work', 'roof2_restored.png'), os.path.join(A, 'work', 'roof2_fixed.png'), [(0, 0, 100, 50), (98, 0, 198, 50), (40, 39, 140, 89)], os.path.join(A, 'sheet_roof.png'), k=8)
