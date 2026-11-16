# ================================================================ 中央屋正面第 3 輪（換進場景、原尺寸看過 03_wall 之後；由 fix_wall.py 載入執行）
# --- 磚牆在門燈與夕陽下過曝（算繪後比基準亮 11%，白勾縫發白）：磚色整體降一階、勾縫由白改成淺灰（改的是貼圖本身的明度，燈光沒動）
for y in range(101, 131):
    for x in range(139):
        col_ = c.get(x, y)
        for k in BR[1:]:
            if PAL[k] == col_: c.px(x, y, BR[BR.index(k) - 1]); break
        else:
            if col_ == PAL['M2']: c.px(x, y, 'M1')
            elif col_ == PAL['M1']: c.px(x, y, 'M0')
# --- 灰泥剝落露出木板條的四處：還原後是褐、灰、米色糊成一團（顏色髒的過渡）→ 逐點重畫：一圈深色輪廓、裡面是一條一條的橫木板條（木色／灰泥色交替）、板條上有 1 點陣的釘孔
KL = {'o': 'P0', 'p': 'P1', 'w': 'D4', 'W': 'D5', 'g': 'P2', 'n': 'D2'}
def clear(x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if c.get(x, y) in {PAL[k] for k in ('R1', 'R2', 'R3', 'R4', 'D1', 'D2', 'D3', 'D4', 'D5', 'M1', 'P0')}: c.px(x, y, 'P3')
clear(49, 76, 66, 93)
c.rows(50, 80, [
    '....ppoooop....',
    '..poowwWwwoop..',
    '.poggggggggggop',
    'powwnwwWwwwnwwo',
    'pogggggggggggop',
    '.powWwwwnwwwwop',
    '..pogggggggop..',
    '...poowWwoop...',
    '.....pooop.....'], KL)
clear(4, 76, 24, 90)
c.rows(8, 78, [
    '...ppooop....',
    '.poowwWwoop..',
    'poggggggggop.',
    'powwnwwWwwwop',
    '.pogggggggop.',
    '..poowwWoop..',
    '....pooop....'], KL)
clear(108, 8, 132, 26)
c.rows(112, 11, [
    '.....ppooop......',
    '..ppoowWwwoop....',
    '.poogggggggggop..',
    'powwwnwwWwwwnwop.',
    'poggggggggggggop.',
    '.powWwwwwnwwWwwop',
    '..pogggggggggggop',
    '...poowwWwwnwoop.',
    '.....ppoooooop...'], KL)
clear(6, 36, 20, 50)
c.rows(8, 39, [
    '..ppooop...',
    '.poowWwop..',
    'pogggggggop',
    'powwnwwWwop',
    '.pogggggop.',
    '..ppooop...'], KL)
# 山牆正中那一處剝落（大半被窗戶擋住，露出來的左緣是一團褐色）：斜撐以外的褐紅雜點清成灰泥色（斜撐只用 D0–D3，這裡清的是 D4/D5/紅/灰）
for y in range(33, 51):
    for x in range(44, 68):
        if c.get(x, y) in {PAL[k] for k in ('R1', 'R2', 'R3', 'R4', 'D4', 'D5', 'M1', 'P0')}: c.px(x, y, 'P3')
        elif c.get(x, y) in {PAL['D2'], PAL['D3']} and not any(c.get(x + dx, y + dy) == PAL['D0'] for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)): c.px(x, y, 'P2')
c.end_round('round3 brick tone, lath patches redraw')
