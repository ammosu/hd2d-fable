"""紅屋頂的單片瓦樣板（8×8 點陣），build_roof2.py 與 fix_roof2.py 共用。
第一次換入後（05_roofFix 初版）方形平塗的瓦看起來像磚牆 → 改成有弧面的陶瓦：最上列是上一排瓦壓下來的暗邊、中段底色、下半亮一階（鼓起的瓦面）、下緣亮線兩端收圓成扇形，最下列是瓦縫。"""
RR = ['R2', 'R3', 'R4', 'R5']
DK = ['R1', 'R2', 'R3', 'R4']
def tile_px(dx, dy, i):
    """i：0 深紅 1 磚紅 2 亮紅 3 橘褐；回傳調色盤色名"""
    hi = RR[i + 1] if i < 3 else 'R6'
    if dy == 7: return 'R0'
    if dx == 7: return 'R0' if dy >= 5 else 'R1'
    if dy == 0: return DK[i]
    if dy == 6: return 'R0' if dx in (0, 6) else (DK[i] if dx in (1, 5) else hi)
    if dy == 5: return DK[i] if dx == 0 or dx == 6 else hi
    if dy == 4: return RR[i] if dx in (0, 6) else hi
    return RR[i]
