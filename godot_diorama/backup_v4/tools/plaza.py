#!/usr/bin/env python3
"""程序化產生這個廣場專用、不重複的石板貼圖：tex/plaza.png（1024×560 = 32 m × 17.5 m，32 點陣 / 公尺）
世界座標對應：x ∈ [-16,16] → 0..1024；z ∈ [-15, 2.5] → 0..560（堤岸邊在最下緣）
內容：波浪狀一排排的手鑿方石（大小、顏色逐塊不同）、屋前的排水溝與鑄鐵溝蓋、巷子的小方石與中央水溝、
堤岸邊的大塊壓頂石、石縫青苔、磨損發亮的走道、潮濕深色斑。 python3 tools/plaza.py"""
import json, os
import numpy as np
from PIL import Image
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tex')
W, H = 1024, 560
rng = np.random.default_rng(7)
X = lambda x: int(round((x + 16) * 32)); Z = lambda z: int(round((z + 15) * 32))

def vnoise(w, h, cell, seed):
    r = np.random.default_rng(seed)
    gw, gh = w // cell + 2, h // cell + 2
    g = r.random((gh, gw))
    ys, xs = np.mgrid[0:h, 0:w]
    fx, fy = xs / cell, ys / cell
    ix, iy = fx.astype(int), fy.astype(int); tx, ty = fx - ix, fy - iy
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    return (g[iy, ix] * (1 - tx) + g[iy, ix + 1] * tx) * (1 - ty) + (g[iy + 1, ix] * (1 - tx) + g[iy + 1, ix + 1] * tx) * ty

# 色票：冷紫灰到暖粉灰（albedo；夕陽照到變橘金、陰影裡變紫藍）
BASE = np.array([[120, 112, 126], [134, 124, 132], [112, 108, 130], [146, 132, 130], [126, 120, 140], [154, 142, 140], [104, 102, 124], [138, 126, 118]], float)
GAP = np.array([44, 42, 66], float)
MOSS = np.array([[70, 86, 62], [88, 100, 66], [58, 74, 60]], float)
img = np.zeros((H, W, 3), float); img[:] = GAP
gapmask = np.ones((H, W), bool)
big = vnoise(W, H, 96, 1); mid = vnoise(W, H, 28, 2)
# 磨損的走道：巷口 → 主角 → 石階，石頭較亮較平
ys, xs = np.mgrid[0:H, 0:W]
def seg_dist(ax, ay, bx, by):
    px, py = xs - ax, ys - ay; dx, dy = bx - ax, by - ay
    t = np.clip((px * dx + py * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(px - t * dx, py - t * dy)
path = np.minimum(seg_dist(X(-2.1), Z(-9), X(-1.8), Z(-3.5)), np.minimum(seg_dist(X(-1.8), Z(-3.5), X(4.5), Z(1.2)), seg_dist(X(-1.8), Z(-3.5), X(7.0), Z(-3.2))))
worn = np.clip(1 - path / 46.0, 0, 1) * (0.6 + 0.4 * mid)

def stone(x0, y0, x1, y1, off=None, tone=0.0, cut=True):
    """畫一塊石頭：x0..x1、y0..y1（不含右下 1 點陣的石縫）；off = 每一欄的縱向位移（波浪）"""
    x0 = max(x0, 0); x1 = min(x1, W)
    if x1 - x0 < 3: return
    cx, cy = min(W - 1, (x0 + x1) // 2), int(np.clip((y0 + y1) // 2 + (off[min(W - 1, (x0 + x1) // 2)] if off is not None else 0), 0, H - 1))
    c = BASE[rng.integers(len(BASE))] * (0.82 + 0.3 * big[cy, cx] + rng.uniform(-0.07, 0.07) + tone + 0.16 * worn[cy, cx])
    hsh = rng.uniform(-0.06, 0.06); c = c * np.array([1 + hsh, 1.0, 1 - hsh]) * (1 + rng.uniform(-0.05, 0.05))
    if rng.random() < 0.06: c = c * 0.78
    if rng.random() < 0.05: c = c * np.array([1.1, 1.0, 0.92])
    w, h = x1 - x0 - 1, y1 - y0 - 1
    for xx in range(x0, x0 + w):
        o = int(off[xx]) if off is not None else 0
        for yy in range(y0, y0 + h):
            y = yy + o
            if y < 0 or y >= H: continue
            lx, ly = xx - x0, yy - y0
            if cut and (lx in (0, w - 1)) and (ly in (0, h - 1)) and w > 4 and h > 4: continue      # 圓角
            k = 1.0
            if ly == 0 or lx == 0: k = 1.13
            elif ly == h - 1 or lx == w - 1: k = 0.84
            img[y, xx] = c * k; gapmask[y, xx] = False

# 一般區域：波浪狀的一排排方石
off = np.round(3.2 * np.sin(np.arange(W) / 41.0) + 2.2 * np.sin(np.arange(W) / 97.0 + 1.3) + 1.5 * np.sin(np.arange(W) / 17.0 + 0.4)).astype(int)
y = -8
while y < H + 8:
    h = int(rng.choice([7, 8, 8, 9, 9, 10, 11]))
    x = -int(rng.integers(0, 12))
    while x < W:
        w = int(rng.choice([8, 9, 10, 11, 12, 13, 14, 16, 19]))
        if rng.random() < 0.035 and h >= 9:      # 偶爾一塊拆成上下兩小塊
            stone(x, y, x + w, y + h // 2 + 1, off); stone(x, y + h // 2, x + w, y + h, off)
        else: stone(x, y, x + w, y + h, off)
        x += w
    y += h

def clear(x0, y0, x1, y1):
    img[y0:y1, x0:x1] = GAP; gapmask[y0:y1, x0:x1] = True

# 補丁：幾處換成大塊石板（後來重鋪的）與小方石（修補過的），打破「每塊一樣大」
def patch(x0, z0, x1, z1, kind):
    px0, py0, px1, py1 = X(x0), Z(z0), X(x1), Z(z1)
    clear(px0, py0, px1, py1)
    yy = py0
    while yy < py1:
        hh = int(rng.choice([15, 17, 20])) if kind == 'big' else int(rng.choice([5, 6]))
        hh = min(hh, py1 - yy)
        xx = px0 - (int(rng.integers(0, 14)) if kind == 'big' else int(rng.integers(0, 4)))
        while xx < px1:
            ww = int(rng.choice([22, 27, 33])) if kind == 'big' else int(rng.choice([5, 6, 7]))
            a0, a1 = max(xx, px0), min(xx + ww, px1)
            if a1 - a0 >= 3 and hh >= 3: stone(a0, yy, a1, yy + hh, None, 0.05 if kind == 'big' else -0.05)
            xx += ww
        yy += hh
for pt in [(1.6, -2.9, 4.4, -1.9, 'big'), (-5.6, -0.4, -3.4, 0.6, 'big'), (4.6, 0.2, 6.4, 1.3, 'big'), (0.4, -0.9, 2.0, 0.1, 'small'), (-0.8, -3.2, 0.6, -2.4, 'small'), (5.6, -1.4, 7.0, -0.6, 'small'), (-7.5, 0.9, -6.2, 1.6, 'small')]:
    patch(*pt)

# 巷子（x -3.3 ～ -0.8，z < -4.6）：直向的小方石＋中央一條淺水溝
ax0, ax1, ay1 = X(-3.3), X(-0.8), Z(-4.5)
clear(ax0, 0, ax1, ay1)
for xx0 in range(ax0, ax1, 8):
    yy = -int(rng.integers(0, 6))
    while yy < ay1:
        hh = int(rng.choice([7, 8, 9, 10, 12])); stone(xx0, yy, min(xx0 + 8, ax1), min(yy + hh, ay1), None, -0.03); yy += hh
gx = X(-2.05)
clear(gx - 3, 0, gx + 4, ay1)
yy = 0
while yy < ay1:
    hh = int(rng.choice([12, 14, 16])); stone(gx - 3, yy, gx + 4, min(yy + hh, ay1), None, -0.2, False); yy += hh

# 水井四周：三圈放射狀的環形鋪石（中心 8.3, 0.1），外圈一道深色邊石
wcx, wcy = X(8.3), Z(0.1)
rr = np.hypot(xs - wcx, ys - wcy); ang = np.arctan2(ys - wcy, xs - wcx)
ringmask = rr < 62
img[ringmask] = GAP; gapmask[ringmask] = True
for (r0, r1, nseg, tone) in [(22, 33, 18, 0.06), (34, 46, 26, 0.0), (47, 58, 34, 0.04), (59, 62, 60, -0.2)]:
    for k in range(nseg):
        a0 = 2 * np.pi * k / nseg - np.pi + (0.5 if r0 == 34 else 0.0) * 2 * np.pi / nseg
        da = (ang - a0) % (2 * np.pi)
        m = (rr >= r0) & (rr < r1 - 1) & (da * rr > 0.9) & (da < 2 * np.pi / nseg)
        if not m.any(): continue
        c = BASE[rng.integers(len(BASE))] * (0.9 + rng.uniform(-0.07, 0.09) + tone)
        img[m] = c; gapmask[m] = False
        inner = m & (rr < r0 + 1.2); img[inner] = c * 1.12
        outer = m & (rr >= r1 - 2.2); img[outer] = c * 0.86
# 從水井通往堤岸的一道窄排水溝
for yy in range(wcy + 62, H - 34):
    img[yy, wcx - 2:wcx + 2] = np.array([70, 66, 86]) * (0.8 if yy % 9 == 0 else 1.0); gapmask[yy, wcx - 2:wcx + 2] = False
    img[yy, wcx - 3] = GAP; img[yy, wcx + 2] = GAP
# 屋前的排水溝：一條橫向的深色長石（z = -3.9），中間兩個鑄鐵溝蓋
dy = Z(-3.95)
clear(0, dy - 1, W, dy + 7)
x = 0
while x < W:
    w = int(rng.choice([18, 22, 26])); stone(x, dy, x + w, dy + 7, None, -0.18, False); x += w
def grate(cx, cy, w=22, h=9):
    x0, y0 = cx - w // 2, cy - h // 2
    img[y0 - 1:y0 + h + 1, x0 - 1:x0 + w + 1] = [44, 38, 56]
    img[y0:y0 + h, x0:x0 + w] = [74, 70, 88]
    for xx in range(x0 + 2, x0 + w - 1, 3): img[y0 + 1:y0 + h - 1, xx:xx + 2] = [22, 18, 30]
    img[y0, x0:x0 + w] = [104, 98, 116]
    gapmask[y0 - 1:y0 + h + 1, x0 - 1:x0 + w + 1] = False
grate(X(-1.9), dy + 3); grate(X(6.6), dy + 3); grate(X(3.2), Z(0.9), 16, 16)

# 堤岸邊：兩排大塊壓頂石（較亮、邊緣整齊）
by = H - 34
clear(0, by, W, H)
x = -int(rng.integers(0, 20))
while x < W:
    w = int(rng.choice([22, 26, 30])); stone(x, by + 1, x + w, by + 14, None, 0.03); x += w
x = -int(rng.integers(0, 20))
while x < W:
    w = int(rng.choice([30, 36, 42])); stone(x, by + 14, x + w, H + 1, None, 0.12); x += w

# 石面細節：零星深淺點、裂痕
sp = rng.random((H, W))
img[(sp < 0.04) & ~gapmask] *= 0.9
img[(sp > 0.972) & ~gapmask] *= 1.08
for _ in range(700):
    cx, cy = int(rng.integers(8, W - 8)), int(rng.integers(8, H - 8))
    for i in range(int(rng.integers(3, 8))):
        if not gapmask[cy, cx]: img[cy, cx] *= 0.7
        cx += int(rng.integers(0, 2)); cy += int(rng.integers(-1, 2))
        if not (0 < cx < W - 1 and 0 < cy < H - 1): break
# 潮濕深色斑（堤岸邊、排水溝旁、牆腳）
damp = vnoise(W, H, 44, 5) * 0.6 + vnoise(W, H, 13, 6) * 0.4
edge = np.clip(1 - np.abs(ys - (dy + 3)) / 26.0, 0, 1) + np.clip((ys - (H - 60)) / 40.0, 0, 1) * 0.8
dm = np.clip((damp + edge * 0.35 - 0.62) * 5, 0, 1)
dm = np.round(dm * 2) / 2
img *= (1 - 0.2 * dm)[..., None] * np.array([1.0, 1.0, 1.04])
# 石縫青苔：在石縫與鄰接的石邊，依雜訊成片出現
mn = vnoise(W, H, 36, 8) * 0.65 + vnoise(W, H, 9, 9) * 0.35 + edge * 0.12
near_gap = gapmask.copy()
near_gap[1:] |= gapmask[:-1]; near_gap[:, 1:] |= gapmask[:, :-1]
mm = (mn > 0.6) & gapmask & (rng.random((H, W)) < 0.85)
mm2 = (mn > 0.68) & near_gap & ~gapmask & (rng.random((H, W)) < 0.45)
idx = rng.integers(0, 3, (H, W))
img[mm] = MOSS[idx[mm]] * 0.85
img[mm2] = MOSS[idx[mm2]]
out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGB').quantize(colors=40, method=Image.MEDIANCUT, dither=Image.NONE).convert('RGB')
out.save(os.path.join(T, 'plaza.png'))
mp = os.path.join(T, 'meta.json'); meta = json.load(open(mp)); meta['plaza'] = [W, H]; json.dump(meta, open(mp, 'w'), indent=1)
print('plaza.png', out.size)
