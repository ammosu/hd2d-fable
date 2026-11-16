#!/usr/bin/env python3
"""共用調色盤（64 色）。 python3 art/palette.py → art/palette.png、art/palette.txt
取色來源：現有場景貼圖 ×材質 tint 後的主色（plaza、brick、plaster2、stonewall、w_roof_red2、hero）與概念圖 target.png 的色相，
再手動整理成色階。貼圖畫的是「中性漫射色」：夕陽的橘金與陰影的藍紫由即時光照產生，所以這裡沒有夕陽色的石頭。
暖色階（受光後偏金橘）：R 陶土磚紅、P 灰泥、W 暖石、D 木、L 落葉、H 髮、K 膚；冷色階（陰影裡偏藍紫）：S 冷石、B 斗篷藍、T 圍巾青綠、G 青苔。"""
import os
from PIL import Image, ImageDraw
RAMPS = [
 ('S', '冷石（廣場石板、石縫）', ['25233a', '343545', '55526a', '686272', '797181', '867c84', '9a8d92', 'b3a5a3']),
 ('W', '暖石（牆腳石基、邊石）', ['3c3127', '5c493c', '735b4d', '8c7566', 'a89384']),
 ('R', '陶瓦／紅磚', ['3a1214', '5a1c1a', '772418', '8e2b1e', 'a53627', 'bc4a2e', 'cf6a44', 'c98a78']),
 ('M', '勾縫／灰白', ['aa8f86', 'cba599', 'e2cdb8']),
 ('P', '灰泥', ['8f6f52', 'ab8762', 'bc9875', 'cfad88', 'dcc09c', 'ead6b6']),
 ('D', '木構架／深色外框', ['1c0c08', '2e140c', '45200f', '5f3018', '7d4526', '9a6238']),
 ('G', '青苔', ['2f3f2f', '47603c', '68803f', '8fa052']),
 ('L', '落葉', ['b4421c', 'dc7a22', 'ebb23a']),
 ('H', '頭髮（暗部借用 R0–R2）', ['6e2a26', '94392e', 'b8553a', 'd88a5a']),
 ('K', '皮膚', ['b06d4e', 'd6a07a', 'f0c8a4', 'fbe4cc']),
 ('B', '斗篷藍', ['161a38', '24326a', '35539c', '4f7ac4', '7fa8de']),
 ('T', '圍巾青綠', ['134a48', '1f7566', '36a085', '6cc8a4']),
 ('V', '紫灰石（廣場石板的色差）', ['74607a', '8f7790']),
 ('X', '其他（高光白、鑄鐵黑；腮紅借用 R7）', ['fff6e8', '1a1a24']),
]
def rgb(h): return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
PAL = {f'{k}{i}': rgb(h) for k, _, hs in RAMPS for i, h in enumerate(hs)}
def sub(*keys):
    """取出子集合：'S' 整條色階，'R0' 單色"""
    out = []
    for k in keys:
        out += [v for n, v in PAL.items() if n == k or (len(k) == 1 and n[0] == k)]
    return out
if __name__ == '__main__':
    A = os.path.dirname(os.path.abspath(__file__))
    C = 24; im = Image.new('RGB', (8 * C, len(RAMPS) * C), (0, 0, 0)); d = ImageDraw.Draw(im)
    with open(os.path.join(A, 'palette.txt'), 'w') as f:
        f.write(f'# 共用調色盤：{len(PAL)} 色（名稱 hex R G B）；palette.png 每列一條色階，由暗到亮\n')
        for y, (k, desc, hs) in enumerate(RAMPS):
            f.write(f'# {k}: {desc}\n')
            for i, h in enumerate(hs):
                d.rectangle([i * C, y * C, i * C + C - 1, y * C + C - 1], fill=rgb(h))
                f.write(f'{k}{i} #{h} {rgb(h)[0]} {rgb(h)[1]} {rgb(h)[2]}\n')
    im.save(os.path.join(A, 'palette.png')); print(len(PAL), 'colors')
