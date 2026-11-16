# HD-2D 小鎮（Godot 4.7.1 / Forward+）

啟動（一行）：

    godot --path ./godot --resolution 1920x1080 -f

- Esc 離開。`-f` 是全螢幕（畫面固定以 1920×1080 算繪）。專案已關閉 vsync 並把上限設為 120 fps。
- 截圖：`./shoot.sh` → `../shots/godot/r7/full_1..3.png`（間隔 2 秒）＋ 2 張 1:1 特寫。加 `--out=資料夾名` 可換輸出資料夾。
- 開關對照：`./shoot.sh --tag=no_fog --no-fog` → `compare_no_fog.png`。
  - `--no-fog`：關體積霧與光束片（所有「霧裡的光」）
  - `--no-beams`：只關光束片與主光束聚光燈的霧，留下太陽的體積霧
  - `--no-dof`：關景深；`--no-refl`：關運河與積水的平面反射；`--top`：從正上方看受光範圍（除錯）
- 貼圖在 `tex/`（執行時直接讀 PNG，不經 Godot 匯入，所以一定是 nearest、無壓縮）。
- 重做素材：`python3 tools/gen.py <名稱>`（codex 生圖）→ `python3 tools/post.py`（還原成真實點陣）→ `python3 tools/pixgen.py`（程式畫的小元件）。
- 鏡頭：`main.gd` 開頭的 `FOV / PITCH / YAW / K_PX`；`K_PX` 是主角所在深度上 1 點陣佔幾個螢幕像素（現在是 4），鏡頭距離由它反推。
