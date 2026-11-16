"""手修共用的小工具：直接改指定座標的像素，並統計每一輪實際改了幾個像素。"""
import os, sys
import numpy as np
from PIL import Image
A = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, A)
from palette import PAL

def col(c):
    if isinstance(c, str):
        if c.startswith('#'): return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
        return PAL[c]
    return tuple(c)

class Canvas:
    def __init__(self, path):
        self.a = np.array(Image.open(path).convert('RGBA')); self.base = self.a.copy(); self.mark = self.a.copy(); self.log = []
    def px(self, x, y, c, alpha=255):
        if 0 <= y < self.a.shape[0] and 0 <= x < self.a.shape[1]:
            self.a[y, x] = col(c) + (alpha,) if c is not None else (0, 0, 0, 0)
    def pts(self, pts, c):
        for x, y in pts: self.px(x, y, c)
    def rect(self, x0, y0, x1, y1, c):      # 含端點
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): self.px(x, y, c)
    def hline(self, x0, x1, y, c): self.rect(x0, y, x1, y, c)
    def vline(self, x, y0, y1, c): self.rect(x, y0, x, y1, c)
    def rows(self, x, y, rows, key):
        """小範圍重畫：rows 是字串清單，每個字元查 key（'.' = 不動）"""
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch != '.': self.px(x + i, y + j, key[ch])
    def get(self, x, y): return tuple(self.a[y, x][:3])
    def swap(self, x0, y0, x1, y1, table):
        """小範圍換色：矩形（含端點）內把色名 A 的像素改成 B（table = {'A': 'B', ...}），透明像素不動"""
        t = {col(k): v for k, v in table.items()}
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= y < self.a.shape[0] and 0 <= x < self.a.shape[1] and self.a[y, x, 3] > 0 and tuple(self.a[y, x][:3]) in t: self.px(x, y, t[tuple(self.a[y, x][:3])])
    def move(self, x0, y0, x1, y1, dx, dy):
        """把矩形（含端點）內的像素整塊搬移 (dx, dy)，原位置清成透明（之後再用 rows 補畫露出來的部分）"""
        blk = self.a[y0:y1 + 1, x0:x1 + 1].copy(); self.a[y0:y1 + 1, x0:x1 + 1] = 0
        for j in range(blk.shape[0]):
            for i in range(blk.shape[1]):
                if blk[j, i, 3] > 0 and 0 <= y0 + j + dy < self.a.shape[0] and 0 <= x0 + i + dx < self.a.shape[1]: self.a[y0 + j + dy, x0 + i + dx] = blk[j, i]
    def clone(self):
        o = Canvas.__new__(Canvas); o.a = self.a.copy(); o.base = self.base; o.mark = self.a.copy(); o.log = []; return o
    def end_round(self, name):
        n = int((self.a != self.mark).any(-1).sum()); self.log.append((name, n)); self.mark = self.a.copy(); print(f'  {name}: {n} px'); return n
    def total(self): return int((self.a != self.base).any(-1).sum())
    def save(self, path, rgb=False):
        Image.fromarray(self.a[..., :3] if rgb else self.a).save(path)

def sheet(before, after, boxes, path, k=8, gap=8):
    """左：還原後未修｜右：手修後，k 倍放大並排；boxes = [(x0,y0,x1,y1), ...] 每個區域一列"""
    b = Image.open(before).convert('RGBA'); a = Image.open(after).convert('RGBA')
    bg = Image.new('RGBA', b.size, (60, 60, 70, 255))
    rows = []
    for box in boxes:
        l = Image.alpha_composite(bg.crop(box), b.crop(box)).convert('RGB'); r = Image.alpha_composite(bg.crop(box), a.crop(box).convert('RGBA')).convert('RGB')
        w, h = l.size
        row = Image.new('RGB', (w * k * 2 + gap, h * k), (255, 0, 255))
        row.paste(l.resize((w * k, h * k), Image.NEAREST), (0, 0)); row.paste(r.resize((w * k, h * k), Image.NEAREST), (w * k + gap, 0)); rows.append(row)
    W = max(r.width for r in rows); Ht = sum(r.height for r in rows) + gap * (len(rows) - 1)
    out = Image.new('RGB', (W, Ht), (255, 0, 255)); y = 0
    for r in rows: out.paste(r, (0, y)); y += r.height + gap
    out.save(path)

def zoom(path, box, out, k=8, grid=True):
    """放大檢視用：每 8 個點陣畫一條淡格線並標座標，方便對出像素座標"""
    from PIL import ImageDraw
    im = Image.open(path).convert('RGBA'); bg = Image.new('RGBA', im.size, (60, 60, 70, 255)); im = Image.alpha_composite(bg, im).convert('RGB').crop(box)
    w, h = im.size; z = im.resize((w * k, h * k), Image.NEAREST); d = ImageDraw.Draw(z)
    if grid:
        for x in range(box[0] - box[0] % 8 + 8, box[2], 8):
            d.line([((x - box[0]) * k, 0), ((x - box[0]) * k, h * k)], fill=(255, 255, 255) if x % 16 == 0 else (150, 150, 150)); 
            if x % 16 == 0: d.text(((x - box[0]) * k + 2, 1), str(x), fill=(255, 255, 0))
        for y in range(box[1] - box[1] % 8 + 8, box[3], 8):
            d.line([(0, (y - box[1]) * k), (w * k, (y - box[1]) * k)], fill=(255, 255, 255) if y % 16 == 0 else (150, 150, 150))
            if y % 16 == 0: d.text((1, (y - box[1]) * k + 1), str(y), fill=(255, 255, 0))
    z.save(out)
