#!/usr/bin/env python3
"""程式畫的小像素元件（鳥、蝴蝶、落葉、煙、遠景剪影）→ tex/。 python3 tools/pixgen.py"""
import json, os, random
import numpy as np
from PIL import Image
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
MP = os.path.join(OUT, 'meta.json')
meta = json.load(open(MP)) if os.path.exists(MP) else {}

def art(name, rows_list, pal):
    """rows_list：多格動畫（橫向排列）；字元對應 pal 顏色，'.' 透明"""
    h = len(rows_list[0]); w = len(rows_list[0][0])
    a = np.zeros((h, w * len(rows_list), 4), np.uint8)
    for f, rows in enumerate(rows_list):
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c != '.': a[y, f * w + x] = pal[c] + (255,)
    Image.fromarray(a, 'RGBA').save(os.path.join(OUT, name + '.png'))
    meta[name] = [a.shape[1], a.shape[0]]; meta[name + '_frames'] = len(rows_list)

# 鳥：兩格拍翅（側面剪影，黃昏逆光所以偏暗）
K = {'a': (38, 30, 48), 'b': (70, 52, 66), 'c': (230, 150, 90)}
art('bird', [
 ["..aa........", "...aa.......", "...aaa......", "....aab.....", "...aaaabac..", ".aaaaaaaa...", "....aaa.....", "............"],
 ["............", "............", "............", "....aab.....", "...aaaabac..", ".aaaaaaaa...", "...aaaa.....", "..aaa......."],
], K)
# 蝴蝶：兩格（張翅／合翅）
for nm, pal in (('bfly_o', {'a': (60, 34, 30), 'b': (255, 150, 40), 'c': (255, 214, 110), 'w': (255, 244, 220)}),
                ('bfly_b', {'a': (36, 40, 80), 'b': (110, 170, 255), 'c': (200, 230, 255), 'w': (255, 255, 255)}),
                ('bfly_w', {'a': (90, 80, 70), 'b': (255, 246, 214), 'c': (255, 255, 240), 'w': (255, 230, 120)})):
    art(nm, [
     ["bb.....bb", "bcb...bcb", "bccb.bccb", ".bcbabcb.", "..bbabb..", ".bcbabcb.", ".bwb.bwb.", "..b...b.."],
     ["...b.b...", "..bcbcb..", "..bcacb..", "..bcacb..", "...bab...", "..bcacb..", "..bwbwb..", "...b.b..."],
     ["....b....", "...bcb...", "...bab...", "...bab...", "...bab...", "...bab...", "...bwb...", "....b...."],
    ], pal)

# 大蝴蝶（13×11，三格：張翅 → 半合 → 合翅，後兩格由第一格往中線壓縮）
BF = [".bb.......bb.", "bccb.....bccb", "bcwcb...bcwcb", "bcccb.a.bcccb", ".bccbbabbccb.", "..bbbbabbbb..", ".bcccbabcccb.", ".bcwcb.bcwcb.", "..bcb...bcb..", "...b.....b...", "............."]
def squeeze(rows, f):
    out = []
    for r in rows:
        n = ['.'] * 13
        for x, c in enumerate(r):
            if c != '.':
                nx = 6 + int(round((x - 6) * f))
                if n[nx] == '.' or c in 'aw': n[nx] = c
        out.append(''.join(n))
    return out
for nm, pal in (('bflyL_o', {'a': (50, 26, 20), 'b': (150, 50, 10), 'c': (255, 140, 20), 'w': (255, 226, 90)}),
                ('bflyL_b', {'a': (20, 24, 70), 'b': (30, 60, 170), 'c': (70, 150, 255), 'w': (190, 240, 255)}),
                ('bflyL_y', {'a': (70, 50, 20), 'b': (190, 130, 10), 'c': (255, 226, 60), 'w': (255, 255, 200)})):
    art(nm, [BF, squeeze(BF, 0.6), squeeze(BF, 0.25)], pal)
# 落葉：四格（翻轉中的葉子），兩種顏色
for nm, pal in (('leaf_o', {'a': (160, 60, 20), 'b': (240, 130, 30), 'c': (255, 196, 70)}),
                ('leaf_r', {'a': (120, 30, 24), 'b': (214, 70, 36), 'c': (250, 140, 60)})):
    art(nm, [
     ["..bc..", ".bccb.", "bbcbba", ".bbba.", "..ba..", "..a..."],
     ["......", "..cc..", ".bccba", "abbba.", "..a...", "......"],
     ["...a..", "..ab..", ".abbb.", "abbcbb", ".bccb.", "..cb.."],
     ["......", "..a...", ".abbba", "abccb.", "..cc..", "......"],
    ], pal)
# 煙：一團像素煙
art('puff', [["...ccc....", "..ccccc.c.", ".ccdccccc.", "cccddccccb", "ccccccccbb", ".cccccbbb.", "..ccbbbb..", "...bbb....", ".........."]], {'b': (132, 110, 140), 'c': (196, 170, 180), 'd': (236, 214, 208)})
art('bulb', [[".a.", "ccc", "ccc", ".c."]], {'a': (60, 44, 50), 'c': (255, 240, 200)})
art('lily', [
 ["..bbbb...", ".bcccbb..", "bccc.cbb.", "bcccccbb.", ".bbccbb..", "..bbb...."],
 ["...bbb...", ".bbcccb..", "bcccccbp.", "bccccbpw.", ".bbbbb...", "........."],
 [".bbb.....", "bcccb.bb.", "bccb.bccb", ".bb..bccb", "......bb.", "........."],
], {'b': (40, 110, 60), 'c': (90, 180, 80), 'p': (250, 170, 200), 'w': (255, 240, 240)})
# 煙囪的煙：四格（小 → 中 → 大 → 散開），左上受夕陽、右下是紫灰陰影
art('smoke', [
 ["..........", "..........", "..........", "...dc.....", "..dccb....", "..ccbb....", "...bb.....", "..........", "..........", ".........."],
 ["..........", "...ddc....", "..dcccb...", ".dccccbb..", ".cccccbb..", ".ccccbbb..", "..cbbbb...", "...bb.....", "..........", ".........."],
 ["..ddcc....", ".dccccc.b.", "dcccccccb.", "dccccccbbb", "ccccccbbbb", ".cccccbbb.", ".ccbbbbbb.", "..bbb.bb..", "...b......", ".........."],
 ["..........", ".dcc......", ".cccb..cc.", "..bb..cccb", "......cbbb", ".cc....bb.", ".cbb......", "..b...cb..", "..........", ".........."],
], {'b': (128, 104, 140), 'c': (196, 166, 176), 'd': (246, 214, 190)})
art('mote', [["cc", "cc"]], {'c': (255, 236, 170)})

# 遠景剪影：一排尖屋頂與鐘塔、樹團（單色，由引擎上色＋霧）
def skyline(name, W, H, seed, tower=True, trees=0.3):
    rng = random.Random(seed); a = np.zeros((H, W), np.uint8); x = 0
    while x < W:
        r = rng.random()
        if r < trees:   # 樹團
            w = rng.randint(14, 26); h = rng.randint(int(H * .3), int(H * .55))
            for i in range(w):
                for j in range(h):
                    dx = (i - w / 2) / (w / 2); dy = (j - h * .45) / (h * .55)
                    if dx * dx + dy * dy < 1 + 0.25 * np.sin(i * 1.7) * np.cos(j * 1.3): 
                        if 0 <= x + i < W: a[H - 1 - j, x + i] = 1
            x += w - 3
        else:
            w = rng.randint(14, 30); wall = rng.randint(int(H * .2), int(H * .45)); roof = rng.randint(6, 14)
            is_t = tower and r > 0.93
            if is_t: w = 10; wall = int(H * .7); roof = 14
            for i in range(w):
                d = abs(i - (w - 1) / 2) / ((w - 1) / 2)
                h = wall + int(roof * (1 - d))
                if 0 <= x + i < W: a[H - h:, x + i] = 1
            # 煙囪
            if not is_t and rng.random() < 0.6:
                cx = x + rng.randint(2, w - 5); a[H - wall - roof - 2:, cx:cx + 3] = np.maximum(a[H - wall - roof - 2:, cx:cx + 3], 1) if cx + 3 < W else 0
            # 亮窗（值 2）
            for _ in range(rng.randint(0, 3)):
                wx = x + rng.randint(2, max(3, w - 5)); wy = H - rng.randint(4, max(5, wall - 3))
                if wx + 2 < W: a[wy:wy + 3, wx:wx + 2] = 2
            x += w + rng.randint(-2, 3)
    out = np.zeros((H, W, 4), np.uint8)
    out[a == 1] = (255, 255, 255, 255); out[a == 2] = (255, 190, 90, 255)
    Image.fromarray(out, 'RGBA').save(os.path.join(OUT, name + '.png')); meta[name] = [W, H]
skyline('sky_a', 512, 72, 3)
skyline('sky_b', 512, 56, 9, trees=0.5)
# 遠山
def hills(name, W, H, seed):
    rng = np.random.default_rng(seed); x = np.arange(W)
    y = H * .45 + H * .25 * np.sin(x / W * 6.283 * 1 + rng.uniform(0, 6)) + H * .14 * np.sin(x / W * 6.283 * 3 + rng.uniform(0, 6)) + H * .06 * np.sin(x / W * 6.283 * 7 + rng.uniform(0, 6))
    a = np.zeros((H, W, 4), np.uint8)
    for i in range(W): a[H - int(y[i]):, i] = (255, 255, 255, 255)
    Image.fromarray(a, 'RGBA').save(os.path.join(OUT, name + '.png')); meta[name] = [W, H]
hills('hills', 512, 64, 5)
json.dump(meta, open(MP, 'w'), indent=1)
print('ok')
