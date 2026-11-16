#!/usr/bin/env python3
"""地面：把 7 張 codex 分塊（art/raw/ground_*_v1.png）還原成 32 PPM 的真點陣、量化到調色盤、拼成 1024×560。
輸出 art/work/ground_restored.png（未手修；之後由 fix_ground.py 手修成 tex/pilot_plaza.png）。
codex 在這個密度下畫的是平滑插畫而不是對齊格線的假像素，所以「還原」= 以固定格距（7 px；巷子 9 px）取每格中央的中位數，
比一格細的深色石縫另外保留（restore.py 的 lines）。拼接：相鄰兩塊重疊 18 點陣，沿左（上）塊的石縫找一條最短路徑切開。"""
import os, sys, heapq
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from restore import restore, to_palette, tone, check, despeckle
from palette import PAL, sub
W, H = 1024, 560
COLS = sub('S', 'V', 'G', 'L', 'X1')
KEEP = set(sub('G', 'L', 'S0', 'S1', 'X1'))
JOINT = [PAL['S0'], PAL['S1'], PAL['X1']]

STONE = [PAL[k] for k in ('S2', 'S3', 'V0', 'S4', 'S5', 'V1', 'S6', 'S7')]      # 石面用色，由暗到亮
def label4(mask):
    H, W = mask.shape; lab = np.zeros((H, W), np.int32); n = 0; comps = []
    for y in range(H):
        for x in range(W):
            if mask[y, x] and not lab[y, x]:
                n += 1; st = [(y, x)]; lab[y, x] = n; comp = []
                while st:
                    cy, cx = st.pop(); comp.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        yy, xx = cy + dy, cx + dx
                        if 0 <= yy < H and 0 <= xx < W and mask[yy, xx] and not lab[yy, xx]: lab[yy, xx] = n; st.append((yy, xx))
                comps.append(comp)
    return lab, comps

def load(name, pitch, gmul=1.0):
    """還原一塊（還原階段，演算法處理；之後才是手修）：
    codex 在這個密度畫的是平滑插畫（石縫 4～5 px 的線、石面是漸層），直接縮小量化會得到斷掉的石縫與碎成亂點的石面。所以：
      1. 在原圖解析度把石縫（深色線）與每一塊石頭（被石縫圍起來的連通區）分出來；
      2. 每個點陣（pitch×pitch px）取「佔最多的那塊石頭」；石縫佔 45% 以上的點陣是石縫；相鄰兩個點陣若屬於不同石頭，中間補一個石縫點陣 → 石縫連續、1 點陣寬；
      3. 每塊石頭給單一底色（該石頭的平均色、把對比拉大後取最近的石面色）→ 逐塊有色差、沒有亂點；石頭下緣一列用最暗的石面色、上緣一列亮一階（很輕的形體明暗，不帶太陽方向）；
      4. 苔、落葉（鮮豔色）與鑄鐵溝蓋照原圖的點陣貼回去。"""
    f = os.path.join(A, 'raw', name + VER.get(name, '_v1') + '.png')
    o, _ = restore(f, pitch=pitch, grid=False, lines=0.2)
    err = check(f, o, pitch)
    raw = np.array(Image.open(f).convert('RGB')).astype(np.float32)
    lum = raw.sum(2); viv = ((raw[..., 1] > raw[..., 2] + 12) & (raw[..., 1] >= raw[..., 0] - 10)) | (raw[..., 0] > raw[..., 2] + 60)
    L = np.median(lum[~viv])
    from PIL import ImageFilter
    loc = np.array(Image.fromarray(np.clip(lum / 3, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(30))).astype(np.float32) * 3
    Jr = ((lum < 0.66 * L) | (lum < JT.get(name, 0.80) * loc)) & ~viv      # 石縫：比全圖石面暗很多，或比附近平均暗（有些分塊的石縫畫得很淺）
    half = ~Jr[::2, ::2]
    lab2, comps = label4(half)
    lab = np.repeat(np.repeat(lab2, 2, 0), 2, 1)[:raw.shape[0], :raw.shape[1]]; lab[Jr] = 0
    means = np.zeros((len(comps) + 1, 3), np.float32)
    for i, comp in enumerate(comps):
        ys = np.array([c[0] for c in comp]) * 2; xs = np.array([c[1] for c in comp]) * 2
        means[i + 1] = raw[ys, xs].mean(0)
    H, W = o.shape[:2]
    tl = np.zeros((H, W), np.int32); jf = np.zeros((H, W), np.float32)
    for j in range(H):
        y0, y1 = int(j * pitch), int((j + 1) * pitch)
        for i in range(W):
            x0, x1 = int(i * pitch), int((i + 1) * pitch)
            blk = lab[y0:y1, x0:x1].ravel(); jf[j, i] = (blk == 0).mean()
            nz = blk[blk > 0]
            if len(nz): tl[j, i] = np.bincount(nz).argmax()
    J = (jf >= 0.58) | (tl == 0)      # 第二階段：小圓石之間的石縫本來就寬，門檻提高一點免得整片發黑
    # 相鄰不同石頭之間補石縫（把石縫比例較高的那個點陣變成石縫）
    for dy, dx in ((0, 1), (1, 0)):
        a_ = tl[:H - dy, :W - dx]; b_ = tl[dy:, dx:]
        diff = (a_ != b_) & ~J[:H - dy, :W - dx] & ~J[dy:, dx:]
        ys, xs = np.where(diff)
        for y, x in zip(ys, xs):
            if J[y, x] or J[y + dy, x + dx]: continue
            if jf[y, x] >= jf[y + dy, x + dx]: J[y, x] = True
            else: J[y + dy, x + dx] = True
    # 石面底色
    gain = 418.0 / (raw[~Jr & ~viv].sum(1).mean()) * gmul
    def tone1(c):
        c = c * gain; g = c.mean(); c = g + (c - g) * 0.8 + np.array([-4, -8, 0]); return c
    gm = tone1(raw[~Jr & ~viv].mean(0)); pal = np.array(STONE, np.float32)
    out = np.zeros((H, W, 3), np.uint8); out[:] = PAL['S0']
    out[J & (jf < 0.9)] = PAL['S1']      # 石縫：只有完全落在縫裡的點陣用最深色，其餘用淺一階的深色
    ids = np.unique(tl[~J]); cidx = {}
    for i in ids:
        m = tone1(means[i]); m = gm + (m - gm) * CONTRAST.get(name, 3.0)
        cidx[i] = int(((pal - m) ** 2 * np.array([2, 4, 3])).sum(1).argmin())
    size = np.bincount(tl[~J].ravel(), minlength=len(comps) + 1)
    for y in range(H):
        for x in range(W):
            if J[y, x]: continue
            i = tl[y, x]; k = cidx[i]
            if size[i] >= 20:
                # 每塊石頭的形體明暗（不帶太陽方向，只是「鼓起來」的石面）：上緣一列亮一階；下緣一列用最暗的石面色（橫向石縫在 33° 俯角下只剩 1.5～2 px 高，加這一列才撐得住）；
                # 右緣一行暗一階（暗角）；左上角那一點再亮一階（亮面）
                up = y > 0 and J[y - 1, x]; dn = y + 1 < H and J[y + 1, x]; rt = x + 1 < W and J[y, x + 1]; lf = x > 0 and J[y, x - 1]
                if dn: k = 0
                elif up and lf: k = min(k + 2, len(STONE) - 1)
                elif up: k = min(k + 1, len(STONE) - 1)
                elif rt: k = max(k - 1, 0)
            out[y, x] = STONE[k]
    # 苔、落葉、鑄鐵：照取樣結果貼回
    q = to_palette(o, sub('G', 'L', 'X1', 'S1', 'S5'))[..., :3]
    orgb = o[..., :3].astype(np.float32)
    v2 = ((orgb[..., 1] > orgb[..., 2] + 12) & (orgb[..., 1] >= orgb[..., 0] - 10)) | (orgb[..., 0] > orgb[..., 2] + 60)
    out[v2] = to_palette(o, sub('G', 'L'))[..., :3][v2]
    iron = (orgb.sum(2) < 0.4 * L) & (np.abs(orgb[..., 0] - orgb[..., 2]) < 14) & J      # 鑄鐵（近黑、無色相）
    out[iron] = PAL['X1']
    print(f'{name}: {W}x{H} err={err:.1f} stones={len(ids)} mean={out.reshape(-1, 3).mean(0).round(0)}')
    return out

def is_joint(img):
    j = np.zeros(img.shape[:2], bool)
    for c in JOINT: j |= (img == np.array(c, np.uint8)).all(-1)
    return j

def seam_v(cost):
    """由上到下穿過 cost（h×w）的最短路徑（可往左右走，沿著橫向石縫繞），回傳每列的切點 x（取該列路徑上最右的點）"""
    h, w = cost.shape
    dist = np.full((h, w), 1e9); prev = {}
    pq = []
    for x in range(w): dist[0, x] = cost[0, x]; heapq.heappush(pq, (cost[0, x], 0, x))
    end = None
    while pq:
        d, y, x = heapq.heappop(pq)
        if d > dist[y, x]: continue
        if y == h - 1: end = (y, x); break
        for dy, dx in ((1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= xx < w and yy < h:
                nd = d + cost[yy, xx]
                if nd < dist[yy, xx]: dist[yy, xx] = nd; prev[(yy, xx)] = (y, x); heapq.heappush(pq, (nd, yy, xx))
    path = [end]
    while path[-1] in prev: path.append(prev[path[-1]])
    cut = np.zeros(h, int); onpath = np.zeros((h, w), bool)
    for y, x in path: onpath[y, x] = True
    return onpath

def paste_seam(canvas, filled, piece, ox, oy, log, ovw=18, src=None, sid=0):
    """把 piece 貼到 canvas 的 (ox, oy)。左緣／上緣若與已貼的分塊重疊：沿「已貼上那一側」的石縫找最短路徑切開，路徑的遠側才換成新塊。"""
    ph, pw = piece.shape[:2]
    x1, y1 = min(ox + pw, W), min(oy + ph, H)
    take = np.ones((y1 - oy, x1 - ox), bool)
    f = filled[oy:y1, ox:x1]; c = canvas[oy:y1, ox:x1]
    left = f[:, :ovw].mean() > 0.6; top = f[:ovw, :].mean() > 0.6
    if left:
        on = seam_v(np.where(is_joint(c[:, :ovw]), 0.05, 1.0))
        for y in range(on.shape[0]):
            take[y, :np.where(on[y])[0].max() + 1] = False
        log.append(('v', ox, oy, ox + ovw, y1))
    if top:
        tw = int(f[:ovw].any(0).sum())
        on = seam_v(np.where(is_joint(c[:ovw, :]), 0.05, 1.0).T).T
        for x in range(on.shape[1]):
            if f[:ovw, x].any(): take[:np.where(on[:, x])[0].max() + 1, x] = False
        log.append(('h', ox, oy, x1, oy + ovw))
    c[take] = piece[:y1 - oy, :x1 - ox][take]; f[:] = True
    if src is not None: src[oy:y1, ox:x1][take] = sid

def main():
    P = {n: load('ground_' + n, 7.0) for n in ['bl', 'bm', 'br', 'ml', 'mm', 'mr']}
    al = load('ground_alley', 6.5, 1.0); c0 = (al.shape[1] - 113) // 2; P['alley'] = al[:, c0:c0 + 113]
    P['bm'] = P['bm'][:, ::-1]      # 中央那塊左右翻轉：原圖的溝蓋剛好在主角腳邊，翻過去移到貓跑的那一側；磨亮的走道也因此接上左邊那塊的走向
    OFF.update({'ml': 0, 'mm': 0, 'mr': 0})      # 三塊的排水溝（各自在第 73、71、73 列）對齊到 z = −3.9（第 358 列）
    canvas = np.zeros((H, W, 3), np.uint8); filled = np.zeros((H, W), bool); log = []
    # 0. 底圖：鏡頭看不到或在畫面最邊角的區域，用現有分塊的水平翻轉填滿（不是新畫的；看得到的範圍全部會被下面的專屬分塊蓋掉）
    bg_rows = [(-8, 'ml'), (138, 'ml'), (284, 'ml'), (412, 'bl')]
    for oy, n in bg_rows:
        for k, ox in enumerate(range(-183, W, 219)):
            src = P[n][:, ::-1] if k % 2 == 0 else P['mr' if n == 'ml' else 'bm'][:, ::-1]
            if n == 'ml': src = np.roll(src, GUT['ml'] - (GUT['ml'] if k % 2 == 0 else GUT['mr']), axis=0) if False else src
            y0, y1 = max(oy, 0), min(oy + 146, H); x0, x1 = max(ox, 0), min(ox + 219, W)
            canvas[y0:y1, x0:x1] = src[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    np.save(os.path.join(A, 'work', 'ground_bg.npy'), canvas.copy())
    # 1. 專屬分塊（origin 由世界座標決定：主角 (464,483)、水井 (778,483)、排水溝 z≈−3.9、堤岸邊 = 第 558 列）
    order = [('ml', 235, 284), ('mm', 436, 284), ('mr', 637, 284), ('bl', 235, 414), ('bm', 436, 414), ('br', 637, 419)]
    filled[:] = False
    src = np.zeros((H, W), np.uint8)
    for i, (n, ox, oy) in enumerate(order):
        paste_seam(canvas, filled, P[n], ox, oy + OFF.get(n, 0), log, src=src, sid=i + 1)
    canvas[548:560, 637:856] = P['br'][134:146]      # 水井那一塊為了對準井位往下移了 5 列，堤岸壓頂石另外貼回第 548 列
    # 巷子：x −3.9..−0.4（386..499），z −9.2..−3.9
    al = P['alley']; canvas[186:186 + 170, 386:386 + al.shape[1]] = al[:170]; src[186:356, 386:499] = 9; src[548:560, 637:856] = 8
    np.save(os.path.join(A, 'work', 'ground_src.npy'), src)
    Image.fromarray(canvas).save(os.path.join(A, 'work', 'ground_restored.png'))
    open(os.path.join(A, 'work', 'ground_seams.txt'), 'w').write('\n'.join(map(str, log)))
    print('\n'.join(map(str, log)))

GUT = {}; OFF = {}; JT = {}
# 第二階段（評審：石板太大、橫排太直、平塗）：改用 codex 重生成的小塊圓角石分塊（bm v3、其餘 v2）；巷子沿用 v1
VER = {'ground_bm': '_v3', 'ground_bl': '_v2', 'ground_br': '_v2', 'ground_ml': '_v2', 'ground_mm': '_v2', 'ground_mr': '_v2'}
CONTRAST = {'ground_alley': 4.5}
if __name__ == '__main__':
    main()
