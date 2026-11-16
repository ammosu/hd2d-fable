#!/usr/bin/env python3
"""小孩手修：art/work/child_restored.png（30×47）→ art/work/child_fixed.png → tex/pilot_child_anim.png（3 格：抬頭看／伸手／舉高去接，後兩格由手修後的基底直接改像素）＋ art/sheet_child.png
座標 = 圖上的 (x, y)。 python3 art/fix_child.py"""
import os, sys, json
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from fixlib import *
c = Canvas(os.path.join(A, 'work', 'child_restored.png'))
K = {'s': 'K2', 'd': 'K1', 'n': 'D1', 'e': 'D1', 'o': 'D0', 'w': 'X0', 'b': 'D3', 'h': 'D4', 'H': 'D3', 'p': 'R7', 'm': 'R1', 'g': 'G2', 'G': 'G3', 'k': 'G0', 'x': 'G1', 'c': 'D4', 'i': 'D5'}
# ================================================================ 第 1 輪
# --- 外框：還原後全身都是同一個近黑紅 → 依部位改成同色系深色（頭髮／背包／褲鞋 = 深褐、上衣 = 深綠、腿 = 褐）
c.swap(3, 4, 26, 25, {'R0': 'D1'})
c.swap(10, 26, 22, 34, {'R0': 'G0'})
c.swap(6, 26, 9, 34, {'R0': 'D1'}); c.swap(7, 33, 22, 42, {'R0': 'D1'})
# --- 臉（還原後眼睛只剩幾個深色點、位置歪掉）：整塊重畫。朝右的 3/4 側面：近的眼睛 3×4、遠的眼睛 2×4，白色高光；腮紅；張開一點的小嘴
c.rows(13, 13, [
    'hhhshsshh..',
    'nssssssssn.',
    'nsooossoon.',
    'nsewesswen.',
    'nseeesseesn',
    'nscicssicsn',
    'nsspssssdsn',
    '.nsssmmssn.',
    '..nnssssn..',
], K)
c.pts([(10, 22), (11, 22), (12, 22)], 'D1'); c.pts([(10, 20), (10, 21), (11, 21), (11, 20)], 'D3')      # 臉左下原本露出一截膚色（下巴畫太寬）→ 收成髮尾
# --- 頭髮：後腦一大片同色 → 髮束之間加暗線、頭頂加亮部
c.pts([(8, 10), (8, 11), (9, 12), (12, 9), (13, 10), (16, 9), (17, 10), (20, 11), (21, 12)], 'D3')
c.pts([(10, 7), (11, 7), (12, 7), (9, 8), (10, 8), (18, 8), (19, 9)], 'D5')
# --- 上衣：亮暗交錯成橫條紋 → 整理成左亮右暗的兩階，領口一點暗
c.swap(10, 26, 21, 34, {'G1': 'G2'})
c.pts([(15, 26), (15, 27), (16, 27)], 'G1'); c.vline(18, 28, 31, 'G2'); c.vline(11, 27, 30, 'G3')
# --- 腿與鞋：膝蓋加一點暗部，鞋面加亮點
c.pts([(11, 39), (17, 39)], 'K1'); c.pts([(12, 40), (18, 40)], 'D5')
c.end_round('round1 outline hues, face redraw, hair/shirt layers')
c.save(os.path.join(A, 'work', 'child_fixed.png'))
print('total changed', c.total())
sheet(os.path.join(A, 'work', 'child_restored.png'), os.path.join(A, 'work', 'child_fixed.png'), [(0, 0, 30, 47)], os.path.join(A, 'sheet_child.png'))
# ================================================================ 動畫格：由手修後的基底直接改像素
# 格 1（伸手）：把垂在身側的右手臂（第 20–22 行、第 28–34 列）擦掉、身體邊緣補外框，改畫一條往右平伸的手臂（綠袖 3 點陣＋手 2 點陣）
# 格 2（舉高）：手臂改成往右上斜伸，手在臉的高度
def arm(kind):
    f = c.clone()
    for y in range(28, 35):
        for x in (20, 21, 22): f.px(x, y, None)
    f.vline(19, 28, 33, 'G0')
    if kind == 1:
        f.rows(20, 27, ['kkkk..', 'gGgssn', 'kkksn.'], {**K, '.': None})
    else:
        f.rows(20, 23, ['...nn.', '..nssn', '.kGsn.', 'kgGk..', 'kgk...'], {**K, '.': None})
    return f.a
frames = [c.a.copy(), arm(1), arm(2)]
strip = np.concatenate(frames, axis=1)
Image.fromarray(strip).save(os.path.join(A, '..', 'tex', 'pilot_child_anim.png'))
mp = os.path.join(A, '..', 'tex', 'meta.json'); m = json.load(open(mp)); m['pilot_child_anim'] = [strip.shape[1], strip.shape[0]]; m['pilot_child_anim_frames'] = 3; json.dump(m, open(mp, 'w'), indent=1)
Image.fromarray(strip).resize((strip.shape[1] * 10, strip.shape[0] * 10), Image.NEAREST).save(os.path.join(A, 'work', 'child_frames_x10.png'))
