#!/usr/bin/env python3
"""截圖後的比對與量測（輸出到 shots/godot_diorama/）：
  compare_target.png（目標圖｜成品並排）、tone_three_level.png（三階明度：目標、成品、兩張 refs_hd2d）、
  地面佔比（compare_mask.png 的白色比例）、主角／店員＋小孩／貓活動區 在 full_1..3 之間的變動像素。
python3 tools/report.py "hero=x,y,w,h" "event=x,y,w,h" "cat=x,y,w,h" """
import os, sys, subprocess
import numpy as np
from PIL import Image, ImageDraw
T = os.path.dirname(os.path.abspath(__file__))
S = os.path.normpath(os.path.join(T, '..', '..', 'shots', 'godot_diorama'))
R = os.path.normpath(os.path.join(T, '..', '..'))
tg = Image.open(os.path.join(R, 'target', 'diorama', 'target.png')).convert('RGB').resize((1920, 1080), Image.LANCZOS)
f1 = Image.open(os.path.join(S, 'full_1.png')).convert('RGB')
sheet = Image.new('RGB', (1920 * 2 + 12, 1080 + 40), (24, 22, 30)); d = ImageDraw.Draw(sheet)
sheet.paste(tg, (0, 40)); sheet.paste(f1, (1932, 40))
d.text((8, 12), 'TARGET (concept image)', fill=(255, 255, 255)); d.text((1940, 12), 'GODOT (full_1.png)', fill=(255, 255, 255))
sheet.save(os.path.join(S, 'compare_target.png'))
subprocess.run(['python3', os.path.join(T, 'tone.py'), os.path.join(S, 'tone_three_level.png'), 'target=' + os.path.join(R, 'target/diorama/target.png'), 'godot=' + os.path.join(S, 'full_1.png'), 'ref_town=' + os.path.join(R, 'refs_hd2d/steam_1971650_3.jpg'), 'ref_ruin=' + os.path.join(R, 'refs_hd2d/steam_1850510_2.jpg'), 'ref_forest=' + os.path.join(R, 'refs_hd2d/steam_1971650_1.jpg')])
mp = os.path.join(S, 'compare_mask.png')
if os.path.exists(mp):
    m = np.array(Image.open(mp).convert('L')); print(f'地面佔比（廣場＋堤岸＋石階，未被遮住的部分）：{(m > 128).mean() * 100:.1f}%')
W = os.path.join(T, 'work')      # 量測用的三張是另外拍的（關掉落葉粒子，才不會把飄過的葉子算進去）
fs = [np.array(Image.open(os.path.join(W, f'full_{i}.png')).convert('RGB')).astype(int) for i in (1, 2, 3)]
for a in sys.argv[1:]:
    name, r = a.split('='); x, y, w, h = [int(v) for v in r.split(',')]
    x0, y0 = max(x, 0), max(y, 0); x1, y1 = min(x + w, 1920), min(y + h, 1080)
    out = []
    for i, j in ((0, 1), (1, 2)):
        df = np.abs(fs[i][y0:y1, x0:x1] - fs[j][y0:y1, x0:x1]).sum(axis=2) > 36
        out.append(int(df.sum()))
    print(f'{name} 區域 {x0},{y0} {x1 - x0}x{y1 - y0}：變動像素 1→2 = {out[0]}，2→3 = {out[1]}（區域共 {(x1 - x0) * (y1 - y0)} px）')
