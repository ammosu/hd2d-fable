#!/usr/bin/env python3
"""釣魚老人手修：art/work/fisher_restored.png（67×65）→ art/work/fisher_fixed.png → tex/pilot_fisher_anim.png（4 格：釣竿竿尖抬高 0／1／2／3 點陣，由手修後的基底直接重畫釣竿那條線）＋ art/sheet_fisher.png
座標 = 圖上的 (x, y)。 python3 art/fix_fisher.py"""
import os, sys, json
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from fixlib import *
c = Canvas(os.path.join(A, 'work', 'fisher_restored.png'))
K = {'a': 'P4', 'b': 'P3', 'c': 'P2', 'Y': 'L2', 'o': 'D2', 'g': 'G1', 'G': 'G2', 'k': 'G0', 's': 'K2', 'd': 'K1', 'r': 'R6', 'p': 'R7', 'w': 'X0', 'm': 'M2', 'M': 'M1', 'e': 'D1', '_': None}
# ================================================================ 第 1 輪
# --- 草帽與臉（還原後草編紋和臉、鬍子的顏色全部攪在一起，看不出五官）：整個頭部（第 26–62 行、第 6–31 列）逐列重畫：
#     帽頂（草編用三階稻草色交錯＋零星亮黃）、深綠帽帶、寬帽簷（下緣一列暗面）、帽簷下的臉（白眉、瞇成一條線的眼、紅鼻頭）、白色大鬍子（三階）、後腦的白髮
HEAD = [
    '_______________ooooooooo_____________',
    '_____________ooaabaabaaboo___________',
    '____________oaabaaYaabaabYo__________',
    '____________oabaabaaYaabaabo_________',
    '___________oaaYaabaabaaYaabco________',
    '___________oabaabaaYaabaabaaco_______',
    '___________okkgggGGgggGGgggkko_______',
    '___________okgGGgggGGgggGGggko_______',
    '____oooooooookkgggggggggggkkoooooo___',
    '__ooaabaabaaooookkkkkkkkkoooaabaabao_',
    '_oaabaaYaabaabaabooooooooobaabaaYaabo',
    'oabaabaabaaYaabaabaabaaYaabaabaabaaco',
    'occbccbccbccbccbccbccbccbccbccbccbcco',
    '_ooooooooooooooooooooooooooooooooooo_',
    '...___..osssssssssMMwo_______________',
    '...___.osswwwsssssdMwwo______________',
    '...___orsseeessssdsmwwo______________',
    '...___orrsssspssdssmMwo______________',
    '..._..owwwwwsssswwmmMo_______________',
    '.....owwwwwwwwwwwwmmMo...............',
    '.....owwmwwwwwwmwwmMo................',
    '.....owwwwmwwwwwwmmMo................',
    '......owwwwwmwwwwmMo.................',
    '.......owwwwwwwwmMo..................',
    '........owwmwwwmMo...................',
    '.........owwwwmoo....................',
]
c.rows(26, 6, HEAD, K)
c.swap(44, 24, 60, 31, {'M1': 'G1', 'M0': 'G0', 'X0': 'G2', 'K2': 'G2', 'K1': 'G1', 'P3': 'G2', 'P4': 'G2', 'R6': 'G1', 'D5': 'G1'})   # 鬍子右邊原本是後腦與帽簷的殘留（粉灰雜色）→ 改成外套肩膀的綠
# --- 釣竿：還原後是斷斷續續的虛線 → 先整條擦掉，動畫格那邊再畫成連續的 1 點陣斜線
for y in range(12, 37):
    for x in range(10, 33 if y < 30 else 30):
        if c.a[y, x, 3] > 0 and c.get(x, y) in (PAL['D3'], PAL['D4'], PAL['D2'], PAL['D1']) and x < 26 + (y - 20) * 0.9 + 6 and not (26 <= x and 6 <= y <= 31): c.px(x, y, None)
# --- 木箱：codex 畫成亮橘色 → 改回木頭色；魚簍上緣的膚色 → 稻草色
c.swap(44, 46, 60, 62, {'R6': 'D5', 'L1': 'D4', 'L2': 'D5'}); c.swap(14, 46, 26, 62, {'K2': 'P4', 'K1': 'P3'})
# --- 手：握竿的兩隻手原本是土黃色 → 膚色，下緣暗一階
c.swap(30, 34, 40, 44, {'P3': 'K2', 'P4': 'K2', 'P2': 'K1'})
c.end_round('round1 head redraw, rod erase, crate/hands colours')
# ================================================================ 第 2 輪（10 倍放大看第 1 輪結果後）
c.a[0:37, 0:26] = 0; c.a[32:37, 26:31] = 0          # 舊釣竿的虛線殘段（兩條平行的斷線＋左上角兩個孤立點）全部清掉；釣竿由動畫格重畫
c.a[20:32, 53:67] = 0                               # 右肩外面多出來一塊（舊帽簷的殘留，被染成綠色＋一點黃）清掉
c.vline(52, 24, 31, 'G0')                           # 清掉之後肩膀右緣補深綠外框
c.pts([(31, 25), (31, 26), (31, 27), (32, 28), (33, 29), (34, 30)], 'D2')      # 鬍子左下緣補外框
c.a[24:36, 26:31] = 0; c.a[31:37, 31:34] = 0         # 鬍子左下方還有幾個舊釣竿的殘點
c.end_round('round2 leftovers cleanup')
c.save(os.path.join(A, 'work', 'fisher_fixed.png'))
print('total changed', c.total())
sheet(os.path.join(A, 'work', 'fisher_restored.png'), os.path.join(A, 'work', 'fisher_fixed.png'), [(0, 0, 67, 65)], os.path.join(A, 'sheet_fisher.png'), k=6)
# ================================================================ 釣竿 4 格：手的位置固定，竿尖抬高 0／1／2／3 點陣（整條線重畫，等於以手為支點轉動）
def rod(lift):
    f = c.clone(); x0, y0, x1, y1 = 8, 10 - lift, 32, 38
    n = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(n + 1):
        x = round(x0 + (x1 - x0) * i / n); y = round(y0 + (y1 - y0) * i / n)
        if f.a[y, x, 3] == 0 or i < n - 2: f.px(x, y, 'D4' if i < 4 else 'D3')
    return f.a
frames = [rod(0), rod(1), rod(2), rod(3)]
strip = np.concatenate(frames, axis=1)
Image.fromarray(strip).save(os.path.join(A, '..', 'tex', 'pilot_fisher_anim.png'))
mp = os.path.join(A, '..', 'tex', 'meta.json'); m = json.load(open(mp)); m['pilot_fisher_anim'] = [strip.shape[1], strip.shape[0]]; m['pilot_fisher_anim_frames'] = 4; json.dump(m, open(mp, 'w'), indent=1)
Image.fromarray(frames[0]).resize((67 * 10, 65 * 10), Image.NEAREST).save(os.path.join(A, 'work', 'fisher_f0_x10.png'))
