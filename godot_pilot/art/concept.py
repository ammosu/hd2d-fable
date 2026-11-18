#!/usr/bin/env python3
"""搭船路線的場景示意圖（只當構圖與氣氛參考，不直接當素材）。 python3 art/concept.py [名稱...]
輸出 art/concept/<name>_vN.png；附圖是目前遊戲截圖，用來對齊畫風。"""
import os, subprocess, sys, shutil, time, glob
from concurrent.futures import ThreadPoolExecutor
A = os.path.dirname(os.path.abspath(__file__)); C = os.path.join(A, 'concept')
REF = os.path.join(C, 'ref_style.png')
BASE = ('請用你的圖片生成功能產生一張圖片：一款 HD-2D 風格遊戲的「場景示意圖」（遊戲畫面截圖的樣子）。'
 '附圖是這款遊戲目前的實機畫面：請完全沿用它的畫風——3D 場景裡放著像素畫的貼圖與角色、像素點陣清楚、'
 '秋天黃昏的暖橘逆光與紫色陰影、景深模糊、柔和的光暈與光束、從斜上方約 33 度往下看的鏡頭、同樣的建築與人物比例。'
 '橫式 16:9。畫面中要有主角（紅橘色頭髮、綠圍巾的 2 頭身小女孩）坐在一艘小木船上，船頭掛一盞小油燈，船在水面上留下波紋。'
 '不要畫任何文字、介面、對話框、浮水印。場景內容：')
P = {
 'c_valley': '船出了小鎮，運河變成兩岸是岩石與紅楓林的溪谷。溪水較窄、有幾塊露出水面的石頭和小漩渦；兩側斜坡長滿紅、橘、黃色楓樹，落葉漂在水上。'
             '畫面上方遠處是一道從岩壁峽谷落下的細長白色瀑布，底部有水霧與夕陽照出的薄霧光。岸邊有一座小石燈籠與一條木頭步道。',
 'c_tunnel': '船正要穿過一座古老石拱橋下方的長涵洞：涵洞內很暗，只有牆上兩三盞鐵製壁燈與船頭的油燈照亮，暖光倒映在黑色的水面上；'
             '石牆潮濕、長青苔與垂下的藤蔓，牆上有水滴。涵洞出口在畫面後方，透出明亮的橘色夕陽光。橋上方有路人與欄杆的剪影。',
 'c_mill': '運河旁的田園水車磨坊：一座大型木造水車在轉動，濺起水花；磨坊是石砌一樓加木造二樓、茅草或木瓦屋頂、煙囪冒煙；'
           '岸邊有木棧道、堆著麵粉袋與木桶、一位搬袋子的磨坊工人；後方是金黃色的麥田與稻草堆，遠處有一排秋天的白楊樹。',
 'c_lighthouse': '運河的出海口：石堤一路延伸到海上，盡頭是一座白色石砌燈塔，燈剛亮起、光束掃過；天色從黃昏轉成藍紫色的魔幻時刻，海面泛著最後的橘光；'
                 '岸邊有幾艘停泊的漁船、捕魚網、木箱與海鷗，碼頭小屋的窗戶透出暖光。',
}
def gen(name):
    d = os.path.join(C, 'work', f'{name}_{time.time_ns()}'); os.makedirs(d)
    p = BASE + P[name] + f'\n完成後把圖片存成目前目錄下的 ./{name}.png（只要這一個檔案，不要做其他事）。'
    t0 = time.time()
    try:
        rc = subprocess.run(['codex', 'exec', '-s', 'workspace-write', '--skip-git-repo-check', '-C', d, '-i', REF], input=p.encode(),
                            stdout=open(os.path.join(d, 'out.log'), 'wb'), stderr=subprocess.STDOUT, timeout=600).returncode
    except subprocess.TimeoutExpired: rc = 'timeout'
    out = os.path.join(d, name + '.png')
    if os.path.exists(out):
        k = len(glob.glob(os.path.join(C, name + '_v*.png'))) + 1; shutil.copy(out, os.path.join(C, f'{name}_v{k}.png'))
        print(f'ok   {name} v{k} {time.time()-t0:.0f}s', flush=True)
    else: print(f'FAIL {name} rc={rc} {time.time()-t0:.0f}s', flush=True)
with ThreadPoolExecutor(4) as ex: list(ex.map(gen, sys.argv[1:] or list(P)))
