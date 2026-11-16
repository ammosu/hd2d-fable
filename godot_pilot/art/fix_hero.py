#!/usr/bin/env python3
"""主角手修：art/work/hero_restored.png（46×68，人物在第 4–41 行、第 4–63 列）→ art/work/hero_fixed.png
→ tex/pilot_hero_anim.png（4 格：睜眼／閉眼／下沉睜眼／下沉閉眼，全部由手修後的基底圖直接改像素產生）＋ art/sheet_hero.png
全部是指定座標的像素修改（座標 = 圖上的 x, y）。 python3 art/fix_hero.py"""
import os, sys, json
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from fixlib import *
c = Canvas(os.path.join(A, 'work', 'hero_restored.png'))
K = {'s': 'K2', 'd': 'K1', 'l': 'K3', 'o': 'R0', 'e': 'D1', 'w': 'X0', 'b': 'D3', 'c': 'D4', 'i': 'D5', 'p': 'R7', 'm': 'R1',
     'h': 'H0', 'H': 'H1', 'G': 'H2', 'g': 'H3', 'x': 'T0', 't': 'T1', 'T': 'T2', 'L': 'T3', 'k': 'B0', '1': 'B1', '2': 'B2', '3': 'B3', '4': 'B4',
     'O': 'R0', 'n': 'D2', 'M': 'M2', 'P': 'P4', 'q': 'D0'}

# ================================================================ 第 1 輪
# --- 臉（還原後眼睛糊成一團深色、高光跑到眼睛外側、嘴只剩兩個雜點）：整個重畫
# 眼睛 4×6：上緣睫毛線、左上白色高光、深褐瞳孔、下半較淺的虹膜；外側各一點睫毛；腮紅 3 點陣；鼻影 1 點陣；小嘴 2×2
c.rows(15, 25, [
    'soooo.....soooos',
    'oowees....seweoo',
    'deweessss.seweed',
    'sebbessssssebbes',
    'secibssssssbcies',
    'sdbcdsssdssdbcds',
    'spppsssssssspppss'[:16],
    'ssps...mm...spss'[:16],
], K)
c.rows(20, 32, ['ss', 's'], K); c.rows(24, 32, ['sss'], K)          # 嘴兩側原本的雜點清成膚色
c.rows(22, 33, ['pp'], K)                                           # 下唇
c.px(21, 33, 'K2'); c.px(24, 33, 'K2')
# 瀏海在臉上的影子（髮緣下方一列膚色改暗一階）
c.pts([(16, 23), (17, 23), (26, 23), (27, 23), (28, 23), (16, 24), (29, 24), (27, 19), (27, 20), (27, 21)], 'K1')
c.pts([(18, 34), (27, 34)], 'K1')                                   # 下巴兩側收邊
# --- 圍巾（還原後混進斗篷的深藍、髮色、純黑褐外框）：整圈重畫成 4 階青綠，脖子露出的 3 點陣改成陰影膚色
c.rows(15, 35, [
    'xxTLTxxdddxTLTx',
    'xTLTTtxxxxxtTTx',
    '..xtTTLLTTTTtxk1k'[:17],
], K)
c.rows(17, 38, ['1xxtTTLTTtxk'], K)
c.rows(17, 39, ['kkxttTTtxx1'], K)
c.rows(13, 40, ['kkk331xxtTTxxk233kk'], K)
c.rows(14, 41, ['k2kk2kkkxxxk231kk'], K)
# 垂下來的一端：左緣深、中間一條亮、右緣暗，尾端做成兩齒的流蘇
c.rows(22, 42, ['xtTTtk', 'xtTLTk', '.TTLTt', '.xTLTt', '..tTTt', '..tTLt', '..xTxT', '...x.x'], K)
# --- 斗篷外框：原本左邊是褐色、右邊是近黑褐，統一成同色系的深藍
c.pts([(13, 36), (13, 37), (31, 37), (12, 38), (32, 38), (12, 39), (32, 39), (13, 42), (12, 43), (11, 44), (11, 45), (10, 46), (10, 47),
       (11, 48), (12, 48), (13, 48), (31, 42), (32, 43), (33, 44), (33, 45), (33, 47), (32, 48), (31, 48), (21, 48), (20, 49)], 'B0')
# 斗篷的層次：肩膀亮面、兩道直摺的暗線、下襬亮邊
c.pts([(15, 38), (30, 38), (14, 39), (31, 39)], 'B4')
c.pts([(29, 43), (29, 44), (29, 45), (30, 46), (17, 44), (16, 46), (16, 47)], 'B1')
c.pts([(12, 47), (13, 47), (30, 48), (29, 48)], 'B4')
# --- 手：原本是 4 個同色點陣的斜塊，改成上亮下暗的小拳頭
c.pts([(12, 51)], 'K3'); c.pts([(14, 52)], 'K1'); c.pts([(31, 51)], 'K3'); c.pts([(30, 52)], 'K1')
# --- 襪子（原本和皮膚同色，分不出來）：改成米白，內側暗一階；靴口露出的一點也改
c.rows(17, 56, ['MMP', 'MPP'], K); c.rows(25, 56, ['PMM', 'PPM'], K)
c.px(18, 58, 'M2'); c.px(26, 58, 'M2')
# --- 靴底加一條深色鞋底線，靴子外框統一成 D2
c.pts([(17, 63), (18, 63), (19, 63), (20, 63), (21, 63), (24, 63), (25, 63), (26, 63), (27, 63)], 'D1')
c.pts([(15, 58), (15, 59), (29, 58), (29, 59), (21, 59), (21, 61), (21, 63), (24, 60), (24, 59)], 'D2')
# --- 頭髮：高光加最亮一階（原本只有 3 階）；兩個脫離輪廓的孤立外框點拿掉
c.pts([(13, 15), (13, 16), (12, 16), (23, 18), (24, 18), (32, 16), (15, 17), (16, 17)], 'H3')
c.px(40, 19, None); c.px(4, 23, None)
c.end_round('round1 face/scarf/cloak outline/hands/socks/hair')
for r in ('fix_hero_r2.py', 'fix_hero_r3.py'):
    if os.path.exists(os.path.join(A, r)): exec(open(os.path.join(A, r)).read())

c.save(os.path.join(A, 'work', 'hero_fixed.png'))
print('total changed', c.total())

# ================================================================ 待機動畫格：由手修後的基底直接改像素
base = c.a.copy()
def blink(a):
    b = Canvas.__new__(Canvas); b.a = a.copy()
    # 閉眼：眼睛 4×6 的範圍改回膚色，只留一條往下彎的眼線與外側睫毛
    b.rows(15, 25, ['sssss.....ssssss', 'sssss.....ssssss'[:16], 'dssss....'], K); b.rows(25, 27, ['sssssd'], K)
    b.rows(15, 28, ['oossoo', 'soooos', 'ssssss'], K); b.rows(25, 28, ['oossoo', 'soooos', 'ssssss'], K)
    b.px(23, 30, 'K1')
    return b.a
def sink(a):
    o = a.copy(); o[5:51] = a[4:50]; o[4] = 0      # 上半身（第 4–49 列）整體下移 1 點陣（最上面一列清空），裙子最上面一列被蓋掉（吐氣下沉）；腳與手不動
    return o
frames = [base, blink(base), sink(base), sink(blink(base))]
strip = np.concatenate(frames, axis=1)
Image.fromarray(strip).save(os.path.join(A, '..', 'tex', 'pilot_hero_anim.png'))
mp = os.path.join(A, '..', 'tex', 'meta.json'); m = json.load(open(mp)); m['pilot_hero_anim'] = [strip.shape[1], strip.shape[0]]; m['pilot_hero_anim_frames'] = 4; json.dump(m, open(mp, 'w'), indent=1)
Image.fromarray(strip).resize((strip.shape[1] * 6, strip.shape[0] * 6), Image.NEAREST).save(os.path.join(A, 'work', 'hero_frames_x6.png'))
sheet(os.path.join(A, 'work', 'hero_restored.png'), os.path.join(A, 'work', 'hero_fixed.png'), [(0, 0, 46, 68)], os.path.join(A, 'sheet_hero.png'))
