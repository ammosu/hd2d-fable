# ================================================================ 紅屋頂第 2 輪（9 倍放大看第 1 輪結果後；由 fix_roof.py 載入執行）
def patch(x0, y0, x1, y1, base, rim=None):
    """瓦縫有缺口、沒辦法用種子填的瓦：在指定矩形內把非瓦縫的點陣塗成 base，貼著下緣瓦縫的一列塗成 rim"""
    rim = rim or RAMP[min(RAMP.index(base) + 1, 5)]
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if c.get(x, y) in DARK or c.get(x, y) in {PAL['G0'], PAL['G1'], PAL['G2'], PAL['G3']}: continue
            c.px(x, y, rim if (y + 1 < 89 and c.get(x, y + 1) in DARK) else base)
# --- 還有斑駁亂點的幾片（瓦縫斷開，第 1 輪的種子填色漏出去所以跳過了）
patch(125, 20, 136, 28, 'R2'); patch(177, 50, 190, 57, 'R3'); patch(103, 69, 116, 77, 'R2'); patch(130, 33, 139, 43, 'R3')
patch(184, 20, 197, 27, 'R2'); patch(22, 70, 32, 77, 'R3'); patch(146, 70, 156, 77, 'R4')
# --- 斷開的瓦縫補上（直的瓦縫中間缺 1～2 個點陣）
c.vline(123, 20, 27, 'R0'); c.vline(137, 22, 27, 'R0'); c.vline(129, 31, 37, 'R0'); c.vline(176, 50, 56, 'R0'); c.vline(117, 69, 76, 'R0'); c.vline(102, 70, 76, 'R0')
# --- 缺瓦的洞（露出底下的掛瓦條）：原本是一團深色亂點，重畫成乾淨的洞——深色底、兩條橫木條、上緣有上一排瓦投下的暗邊
KR = {'q': 'D0', 'n': 'D1', 'w': 'D3', 'W': 'D4', 'o': 'R0'}
c.rows(25, 39, [
    'oooooooooooo',
    'qqqqqqqqqqqq',
    'qnnnnnnnnnnq',
    'qwWwwWwwwWwq',
    'qnnnnnnnnnnq',
    'qqqqqqqqqqqq',
    'qwwWwwwWwwwq',
    'qnnnnnnnnnnq',
    'oqqqqqqqqqqo',
], KR)
c.rows(187, 59, ['ooooooooooo', 'qqqqqqqqqqq', 'qnnnnnnnnnn', 'qwWwwWwwwWw', 'qnnnnnnnnnn', 'qqqqqqqqqqq', 'qwwWwwwWwww', 'qnnnnnnnnnn', 'oqqqqqqqqqq'], KR)
# --- 裂瓦：兩片瓦上各畫一道 1 點陣寬的斜裂縫
c.pts([(66, 21), (66, 22), (67, 23), (67, 24), (68, 25), (68, 26), (69, 27)], 'R0')
c.pts([(92, 62), (91, 63), (91, 64), (90, 65), (90, 66), (89, 67)], 'R0')
# --- 青苔：沿瓦片下緣的陰影長（左下角一叢、右上原有的兩叢補上暗部），都是幾個點陣的小群
KG = {'a': 'G0', 'b': 'G1', 'c': 'G2', 'd': 'G3'}
c.rows(2, 67, ['.bc..', 'bccb.', '.bcdb', '..bb.'], KG); c.rows(12, 77, ['bc.', 'cdb', '.bb'], KG); c.rows(0, 57, ['cb', 'bcb', '.b'], KG)
c.rows(166, 17, ['..bcb....', '.bccdcb..', '..bb.bccb', '......bb.'], KG); c.rows(188, 35, ['.bcb..', 'bcdcb.', '.bbccb', '...bb.'], KG)
c.rows(52, 78, ['bcb', '.bcb'], KG)
# --- 屋脊瓦：每一節之間的接縫統一成 1 點陣寬的直線，節的上緣加亮邊
for x in (18, 37, 55, 75, 95, 113, 131, 150, 168, 187): c.vline(x, 2, 8, 'R0')
c.end_round('round2 leaky tiles/holes/cracks/moss/ridge')
