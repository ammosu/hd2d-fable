#!/usr/bin/env python3
"""店員手修：art/work/baker_restored.png（40×69）→ art/work/baker_fixed.png → tex/pilot_baker_anim.png（3 格：捧著／遞出一半／伸直遞出，後兩格由手修後的基底直接搬移、補畫像素）＋ art/sheet_baker.png
座標 = 圖上的 (x, y)。 python3 art/fix_baker.py"""
import os, sys, json
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from fixlib import *
c = Canvas(os.path.join(A, 'work', 'baker_restored.png'))
K = {'s': 'K2', 'd': 'K1', 'l': 'K3', 'o': 'D0', 'e': 'D1', 'w': 'X0', 'b': 'D3', 'c': 'D4', 'p': 'R7', 'm': 'R1', 'h': 'D3', 'H': 'D4', 'g': 'D5', 'n': 'D1',
     'W': 'X0', 'C': 'P5', 'G': 'M1', 'r': 'R4', 'R': 'R5', 'q': 'R3', 'O': 'R0', 'y': 'L1', 'Y': 'L2', 'B': 'D5', 'k': 'D2', '.': None}
# ================================================================ 第 1 輪：還原後各部位的顏色互相污染（頭巾裡混進膚色與褐色、圍裙上是褐色線、鞋子上是紅色），先逐區換回該部位的色階
c.swap(6, 5, 37, 12, {'K2': 'P5', 'K1': 'M1'})                                   # 頭巾上半：膚色其實是頭巾的暗面 → 米色／灰
c.swap(21, 13, 37, 23, {'K2': 'P5', 'K1': 'M1', 'D4': 'M1', 'D3': 'M0', 'M2': 'P5'})   # 頭巾垂在右側的部分
c.swap(24, 24, 34, 34, {'K2': 'P5', 'K1': 'M1', 'D4': 'M1'})                     # 頭巾的結
c.swap(2, 11, 23, 33, {'R0': 'D1'})                                              # 頭髮與臉的外框：近黑紅 → 深褐（同色系）
c.swap(5, 33, 18, 39, {'K2': 'L2', 'X0': 'P2', 'D5': 'L1', 'D3': 'D4', 'D4': 'D5'})   # 麵包：割紋原本是膚色 → 淺金黃；外皮統一成橘金
c.swap(4, 36, 24, 58, {'R6': 'R5', 'R5': 'R4', 'R4': 'R3', 'R3': 'R2'})          # 連身裙：codex 偏亮橘 → 橘紅（深一階）
c.swap(5, 44, 19, 54, {'D5': 'M1', 'K2': 'P5', 'M2': 'P5'})                      # 圍裙：口袋線原本是褐色 → 灰；暗面用米色
c.swap(20, 40, 26, 49, {'K2': 'P5', 'K1': 'M1'})                                 # 圍裙的蝴蝶結帶子
c.swap(7, 59, 22, 64, {'R5': 'D5', 'R0': 'D1', 'D4': 'D3'})                      # 鞋：亮面原本是紅色 → 淺褐；外框深褐
# --- 臉（還原後眼睛是一團深色、沒有形狀）：重畫。3/4 側面朝左：左眼 2×5、右眼 3×5，各有白色高光與較淺的下半虹膜；上緣睫毛線；腮紅；小嘴
K.update({'h': 'D4', 'H': 'D3', 'n': 'D1', 'o': 'D0', 'e': 'D1', 'b': 'D3', 'c': 'D4'})
c.rows(6, 18, [
    'hhHhhhhHhhhhHh',
    'hsHhsshHhsshhh',
    'nsssssssssssHh',
    'nsoosssssooosh',
    'nsewssssseweHh',
    'nsewsssssewehh',
    'nseesssssebehh',
    'nsbcsssssbcbHh',
    'nssssdsssssshh',
    'nppsssssspphhh',
    '.nssmmsssssHh.',
    '..nssssssssnh.',
    '...nnssssnn...',
], K)
# --- 頭髮：整片同一個褐色 → 加暗部（瀏海之間、耳後、髮尾）與亮部（頭頂受光的兩撮）
c.pts([(8, 15), (8, 16), (8, 17), (14, 15), (15, 15), (14, 16), (15, 16), (13, 17), (20, 24), (21, 24), (20, 25), (21, 25), (21, 26), (22, 26),
       (4, 20), (4, 21), (5, 22), (4, 28), (5, 28), (5, 29), (5, 31), (20, 28), (21, 28), (21, 29), (20, 30)], 'D3')
c.pts([(10, 13), (11, 13), (12, 13), (9, 14), (10, 14), (6, 16), (6, 17), (17, 14), (18, 14), (19, 15)], 'D5')
c.end_round('round1 per-part recolour, face redraw, hair layers')
if os.path.exists(os.path.join(A, 'fix_baker_r2.py')): exec(open(os.path.join(A, 'fix_baker_r2.py')).read())
c.save(os.path.join(A, 'work', 'baker_fixed.png'))
print('total changed', c.total())
sheet(os.path.join(A, 'work', 'baker_restored.png'), os.path.join(A, 'work', 'baker_fixed.png'), [(0, 0, 40, 69)], os.path.join(A, 'sheet_baker.png'))
if os.path.exists(os.path.join(A, 'frames_baker.py')): exec(open(os.path.join(A, 'frames_baker.py')).read())
