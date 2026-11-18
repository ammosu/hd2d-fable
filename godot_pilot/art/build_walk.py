#!/usr/bin/env python3
"""主角走路格（正面／側面／背面）：從手修後的基底 art/work/hero_fixed.png 搬像素產生，不重新生成。
4 格：0 左腳踏出（左靴往下 1、右靴抬起 2）／1 經過（身體上提 1）／2 右腳踏出（鏡像）／3 經過。
側面：只看得到一條腿，踏出格把腿複製成前後兩條（前腿往左 2、後腿往右 2 並壓暗一階）。
輸出 tex/pilot_hero_walk_{front,side,back}.png（184×68，每格 46×68，與待機格同尺寸）。 python3 art/build_walk.py"""
import os
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(A, '..', 'tex')
base = np.array(Image.open(os.path.join(A, 'work', 'hero_fixed.png')).convert('RGBA'))
H, W = base.shape[:2]
BODY_END = 56                      # 第 0–55 列：頭、斗篷（腳的上方）；56–63：雙靴
L = (15, 23)                       # 左靴所在欄（畫面左）
R = (23, 31)
def frame(dl, dr, body_dy):
    out = np.zeros_like(base)
    legs = base[BODY_END:64]
    for (x0, x1), dy in ((L, dl), (R, dr)):
        seg = legs[:, x0:x1]
        y0 = BODY_END + dy
        dst = out[y0:y0 + seg.shape[0], x0:x1]
        m = seg[..., 3] > 0
        dst[m] = seg[m]
    body = base[:BODY_END]
    y0 = body_dy
    if y0 < 0: body = body[-y0:]; y0 = 0
    m = body[..., 3] > 0
    tgt = out[y0:y0 + body.shape[0]]
    tgt[m] = body[m]            # 斗篷蓋在抬起的靴子上
    return out
frames = [frame(1, -2, 0), frame(0, 0, -1), frame(-2, 1, 0), frame(0, 0, -1)]
sheet = np.concatenate(frames, axis=1)
Image.fromarray(sheet).save(os.path.join(T, 'pilot_hero_walk_front.png'))
Image.fromarray(sheet).resize((sheet.shape[1] * 6, sheet.shape[0] * 6), Image.NEAREST).save(os.path.join(A, 'work', 'walk_front_x6.png'))
print(sheet.shape)


def updown(src, body_end, L, R, name):
    global base, BODY_END
    base, BODY_END = src, body_end
    globals()['L'], globals()['R'] = L, R
    fr = [frame(1, -2, 0), frame(0, 0, -1), frame(-2, 1, 0), frame(0, 0, -1)]
    save(fr, name)

def save(fr, name):
    sheet = np.concatenate(fr, axis=1)
    Image.fromarray(sheet).save(os.path.join(T, f'pilot_hero_walk_{name}.png'))
    Image.fromarray(sheet).resize((sheet.shape[1] * 6, sheet.shape[0] * 6), Image.NEAREST).save(os.path.join(A, 'work', f'walk_{name}_x6.png'))

back = np.array(Image.open(os.path.join(A, 'work', 'hero_back_restored.png')).convert('RGBA'))
updown(back, 57, (13, 23), (23, 33), 'back')

side = np.array(Image.open(os.path.join(A, 'work', 'hero_side_restored.png')).convert('RGBA'))
SB = 55
def side_frame(spread, body_dy, swap):
    out = np.zeros_like(side)
    leg = side[SB:64]
    dark = leg.copy(); dark[..., :3] = (dark[..., :3] * 0.72).astype(np.uint8)
    back_leg, front_leg = (leg, dark) if swap else (dark, leg)
    for seg, dx in ((back_leg, spread), (front_leg, -spread)):
        m = seg[..., 3] > 0
        sh = np.zeros_like(seg); sh[:, max(0, dx):seg.shape[1] + min(0, dx)] = seg[:, max(0, -dx):seg.shape[1] - max(0, dx)]
        m = sh[..., 3] > 0
        out[SB:64][m] = sh[m]
    body = side[:SB]; y0 = body_dy
    if y0 < 0: body = body[-y0:]; y0 = 0
    m = body[..., 3] > 0
    out[y0:y0 + body.shape[0]][m] = body[m]
    return out
save([side_frame(3, 0, False), side_frame(0, -1, False), side_frame(3, 0, True), side_frame(0, -1, True)], "side")

# 斜前（fl）／斜後（bl）：兩條腿都看得到，做法同正面（以中線分左右腿）
fl = np.array(Image.open(os.path.join(A, 'work', 'hero_fl_restored.png')).convert('RGBA'))
updown(fl, 56, (12, 21), (21, 31), 'fl')
bl = np.array(Image.open(os.path.join(A, 'work', 'hero_bl_restored.png')).convert('RGBA'))
updown(bl, 57, (13, 22), (22, 32), 'bl')
