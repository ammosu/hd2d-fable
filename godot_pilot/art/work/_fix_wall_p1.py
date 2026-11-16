#!/usr/bin/env python3
"""中央屋正面手修：art/work/wall_restored.png（139×147）→ tex/pilot_wallB.png ＋ art/sheet_wall.png
座標 = 圖上的 (x, y)；y 由上往下，第 146 列貼地。木構架的位置對應 3D 模型的木樑方塊（見 build_wall.py 的版面說明）。
每一輪都是 7 倍放大看過後直接改像素／小範圍重畫。 python3 art/fix_wall.py"""
import os, sys
A = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, A)
from fixlib import *
c = Canvas(os.path.join(A, 'work', 'wall_restored.png'))
D = {'0': 'D0', '1': 'D0', '2': 'D1', '3': 'D2', '4': 'D3', '5': 'D4'}      # 木頭整體用深一階（第一次換入後木樑在夕陽下太亮太橘，半木造的深色骨架感不見了）

# ================================================================ 第 1 輪：木構架（還原圖上只是單色佔位）——逐點畫木紋、外框、釘頭
def hbeam(y0, rows, x0=0, x1=138):
    """橫樑：rows 是每一列的木紋字串（循環使用，起點逐列錯開，避免直條對齊）"""
    for j, r in enumerate(rows):
        for x in range(x0, x1 + 1): c.px(x, y0 + j, D[r[(x + j * 7) % len(r)]])
def vpost(x0, cols, y0, y1):
    for i, col in enumerate(cols):
        for y in range(y0, y1 + 1): c.px(x0 + i, y, D[col[(y + i * 5) % len(col)]])
# 上樑（第 51–54 列）：上緣深線、兩列木紋、下緣陰影線
hbeam(51, ['1', '3343332333433343333233343', '2322233222322322232223222', '0'])
# 下樑（第 94–99 列，比較粗）：上緣深線、亮面、木紋、暗面、下緣陰影線
hbeam(94, ['1', '4434443444344434443444434434', '3343332333433343333233343', '3233323332333233233323332', '2322233222322322232223222', '0'])
# 四根立柱（第 55–93 列）：左右各一行深色外框，中間是直木紋
vpost(0, ['3323332333233323333', '3433343334333343334', '1'], 55, 93)
vpost(44, ['1', '3323332333233323333', '4434344434443443444', '2322232223222322223', '1'], 55, 93)
vpost(90, ['1', '3233323332333323332', '4344434443444344434', '2232223222322232222', '1'], 55, 93)
vpost(136, ['1', '3433343334333433334', '3323332333233323333'], 55, 93)
# 釘頭：立柱與橫樑交接處各兩顆（1 點陣的近黑點，旁邊一點亮邊）
for px_ in (1, 46, 92, 137):
    for py_ in (52, 96):
        c.px(px_ - 1 if px_ > 1 else px_, py_, 'D0'); c.px(px_ + 1 if px_ < 137 else px_, py_, 'D0')
# 木節：下樑上兩個、上樑上一個（小小的深色環，中間亮一點）
for kx, ky in ((24, 96), (112, 96)):
    c.rows(kx, ky - 1, ['.11.', '1451', '.11.'], D)
c.rows(70, 52, ['121'], D)
# 山牆：中央短柱（第 68–71 行）與兩根斜撐（4 點陣厚、每往外 1 行就往上 1 列），都是平的畫上去的
vpost(68, ['1', '3323332333233323333', '4434344434443443444', '1'], 2, 50)
for k in range(0, 27):
    for i, sh in enumerate(('1', '3', '3' if k % 5 else '4', '2', '1')):
        c.px(66 - k, 44 - k + i, D[sh]); c.px(73 + k, 44 - k + i, D[sh])
# 木樑下方、灰泥上的接觸陰影（1 列，灰泥暗一階）；木樑毛邊（還原時留下的凸點）清掉
for x in range(139):
    if c.get(x, 50) == PAL['D1'] and not (68 <= x <= 71) and not (c.get(x, 49) in {PAL[k] for k in ('D1', 'D2', 'D3', 'D4')}): c.px(x, 50, 'P3')
for x in list(range(3, 44)) + list(range(49, 90)) + list(range(95, 136)):
    c.px(x, 55, 'P1'); 
    if c.get(x, 93) == PAL['D1']: c.px(x, 93, 'P3')
for y in range(56, 94):
    for x in (3, 49, 95): c.px(x, y, 'P2') if c.get(x, y) in {PAL['P3'], PAL['P4'], PAL['P5']} else None
c.hline(0, 138, 100, 'R1')          # 下樑在磚牆最上面一列投下的暗邊
c.end_round('round1 timber frame (drawn by hand)')
for r in ('fix_wall_r2.py', 'fix_wall_r3.py'):
    if os.path.exists(os.path.join(A, r)): exec(open(os.path.join(A, r)).read())
c.save(os.path.join(A, 'work', 'wall_fixed_p1.png'), rgb=True)
c.save(os.path.join(A, '..', 'tex', 'pilot_wallB_p1.png'), rgb=True)
print('total changed', c.total())
sheet(os.path.join(A, 'work', 'wall_restored.png'), os.path.join(A, 'work', 'wall_fixed_p1.png'), [(0, 0, 100, 56), (39, 50, 139, 100), (0, 92, 100, 147)], os.path.join(A, 'work', 'sheet_wall_phase1.png'), k=8)
