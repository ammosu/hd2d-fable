#!/usr/bin/env python3
"""貓手修：art/work/cat_restored.png（52×39）→ art/work/cat_fixed.png → tex/pilot_cat_anim.png（跑步 4 格：伸展／收腳／直腿蹬地／騰空，後三格由手修後的基底直接擦掉腿、重畫腿）＋ art/sheet_cat.png
座標 = 圖上的 (x, y)。 python3 art/fix_cat.py"""
import os, sys, json
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from fixlib import *
c = Canvas(os.path.join(A, 'work', 'cat_restored.png'))
K = {'o': 'D4', 'w': 'X0', 'm': 'M2', 'k': 'D2', 'e': 'D0', 'b': 'D3', 'p': 'R7', 'r': 'R6', 'h': 'H3', '.': None}
# ================================================================ 第 1 輪
c.swap(33, 8, 42, 13, {'K1': 'R7', 'K2': 'R7'})                      # 耳朵內側：被量化成膚色 → 粉紅
c.swap(4, 14, 49, 34, {'K2': 'M2', 'P4': 'M2'}); c.swap(9, 5, 16, 9, {'P4': 'M2', 'K2': 'M2'})   # 白毛的暗面：混進膚色與土黃 → 統一成米白
c.swap(4, 4, 49, 34, {'L1': 'R6', 'H2': 'D4'})                       # 橘毛：過亮的橘點併入底色；橘毛上的褐色外框統一
# 眼睛（還原後是白、黑、褐交錯的 3×3 雜點）：重畫成深色圓眼＋左上一點白色高光，下緣一點褐
c.rows(40, 16, ['ewe', 'eee', 'beb'], K); c.px(39, 16, 'H3'); c.px(43, 16, 'H3'); c.px(43, 17, 'X0'); c.px(39, 17, 'R6')
c.pts([(45, 19)], 'R7'); c.pts([(44, 21), (45, 21)], 'D3')           # 鼻子、嘴角
# 橘白交界：背上的橘斑下緣原本是鋸齒亂點 → 手排成兩段平順的弧
c.pts([(22, 19), (23, 19), (30, 22), (31, 22)], 'X0'); c.pts([(18, 21), (19, 21)], 'H3')
# 尾巴：橘白相間的環紋補清楚（原本只剩尾尖白、其餘一片橘）
c.pts([(10, 13), (11, 13), (10, 14), (11, 14), (9, 17), (10, 17), (11, 17), (10, 18)], 'M2')
# 橘毛加一階暗部（背脊下緣、後頸）與亮部（頭頂、背上受光）
c.pts([(24, 20), (25, 20), (26, 20), (27, 21), (28, 21), (33, 15), (34, 15), (35, 15)], 'R6')
c.end_round('round1 fur colours, eye redraw, markings')
c.save(os.path.join(A, 'work', 'cat_fixed.png'))
print('total changed', c.total())
sheet(os.path.join(A, 'work', 'cat_restored.png'), os.path.join(A, 'work', 'cat_fixed.png'), [(0, 0, 52, 39)], os.path.join(A, 'sheet_cat.png'))
# ================================================================ 跑步 4 格：由手修後的基底直接改像素
def no_legs():
    """擦掉前後腿（第 29 列以下全部；第 26–28 列裡伸出身體兩端的部分），把肚子下緣與前胸、後臀補上外框"""
    f = c.clone()
    f.a[29:, :] = 0
    f.a[26:29, :9] = 0; f.a[26:29, 39:] = 0
    for x in range(9, 39): f.px(x, 28, 'D4')
    f.vline(8, 25, 27, 'D4'); f.vline(39, 24, 27, 'D4')
    return f
def legs(kind):
    f = no_legs(); KK = K
    if kind == 'gather':      # 收腳：後腿往前、前腿往後，在肚子下面交會
        f.rows(13, 28, ['owwo....', '.owwo...', '..owmo..', '...owwo.', '...owwwo', '....ooo.'], KK)
        f.rows(29, 28, ['....owwo', '...owwo.', '..omwo..', '.owwo...', 'owwwo...', '.ooo....'], KK)
    elif kind == 'stand':     # 直腿蹬地
        f.rows(11, 28, ['owwo.', 'owmo.', 'owmo.', 'owwo.', 'owwwo', '.oooo'], KK)
        f.rows(33, 28, ['owwo.', 'owmo.', 'owmo.', 'owwo.', 'owwwo', '.oooo'], KK)
    return f.a
base = c.a.copy()
air = np.zeros_like(base); air[:-1] = base[1:]      # 騰空：整隻往上 1 點陣
frames = [base, legs('gather'), legs('stand'), air]
strip = np.concatenate(frames, axis=1)
Image.fromarray(strip).save(os.path.join(A, '..', 'tex', 'pilot_cat_anim.png'))
mp = os.path.join(A, '..', 'tex', 'meta.json'); m = json.load(open(mp)); m['pilot_cat_anim'] = [strip.shape[1], strip.shape[0]]; m['pilot_cat_anim_frames'] = 4; json.dump(m, open(mp, 'w'), indent=1)
Image.fromarray(strip).resize((strip.shape[1] * 6, strip.shape[0] * 6), Image.NEAREST).save(os.path.join(A, 'work', 'cat_frames_x6.png'))
