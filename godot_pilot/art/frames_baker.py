# ================================================================ 店員動畫格（由 fix_baker.py 載入）：全部從手修後的基底直接搬像素、補畫，不重新生成
# 格 0：雙手在胸前捧著麵包（基底）。格 1：麵包與雙手整塊往左（朝小孩）移 3 點陣。格 2：再往左共 6 點陣、抬高 1 點陣（手臂伸直）。
# 搬走之後露出來的地方逐列補畫：伸出去的袖子（上下各一列深色外框、中間橘紅兩階）、袖子上方的胸口、下方的裙子。
PADX = 8      # 左右各多留 8 點陣（麵包往左伸出去要有空間；左右對稱，角色位置不變）
def padded(a):
    o = np.zeros((a.shape[0], a.shape[1] + PADX * 2, 4), np.uint8); o[:, PADX:-PADX] = a; return o
base = c.a.copy()
big = c.clone(); big.a = padded(base)
def reach2(dx, dy):
    f = Canvas.__new__(Canvas); f.a = padded(base).copy(); X = PADX
    f.move(4 + X, 33, 17 + X, 43, -dx, dy)
    for x in range(18 - dx + X, 18 + X):
        for y, k in [(33, 'R0'), (34, 'R4'), (35, 'R4'), (36, 'R5'), (37, 'R5'), (38, 'R4'), (39, 'R0'), (40, 'R3'), (41, 'R3'), (42, 'R3'), (43, 'R0')]:
            f.px(x, y + (dy if 35 <= y <= 39 else 0), k)
        if dy: f.px(x, 39, 'R3')
    return f.a
frames = [padded(base), reach2(3, 0), reach2(6, -1)]
strip = np.concatenate(frames, axis=1)
Image.fromarray(strip).save(os.path.join(A, '..', 'tex', 'pilot_baker_anim.png'))
mp = os.path.join(A, '..', 'tex', 'meta.json'); m = json.load(open(mp)); m['pilot_baker_anim'] = [strip.shape[1], strip.shape[0]]; m['pilot_baker_anim_frames'] = 3; json.dump(m, open(mp, 'w'), indent=1)
Image.fromarray(strip).resize((strip.shape[1] * 6, strip.shape[0] * 6), Image.NEAREST).save(os.path.join(A, 'work', 'baker_frames_x6.png'))
print('baker frames', strip.shape)
