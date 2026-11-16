# HD-2D 俯角箱庭：黃昏的運河小鎮廣場（Godot 4.7.1 / Forward+）

啟動（一行，全螢幕，Esc 離開）：

    godot --path ./godot_diorama -f

- 畫面固定以 1920×1080 算繪；專案已關 vsync、上限 120 fps。加 `-- --fps` 會每秒在終端機印出 fps。
- 第四版（v4，目前狀態）：第三版備份在 `backup_v3/`；截圖在 `../shots/godot_diorama/r4/`。新工具 `tools/roofgen.py`（屋頂瓦片變體與貼花）、`tools/cmp.py`（與第三版並排）。
- 第三版（v3）：第二版備份在 `backup_v2/`；截圖在 `../shots/godot_diorama/r3/`（`OUT=r3 ./shoot_all.sh`）。新工具 `tools/skyline.py`（遠景屋頂剪影）、`tools/quaywall.py`（堤岸牆貼圖）。
- 第二版（v2）：第一版的完整備份在 `backup_v1/`；v2 截圖在 `../shots/godot_diorama/r2/`（`OUT=r2 ./shoot_all.sh`）。部分素材（`tex/w_*.png`）取自網頁版 `web/public/tex/`。
- 截圖：`./shoot_all.sh` 一次重拍全部交付圖並量測（輸出到 `../shots/godot_diorama/`）；單拍用 `./shoot.sh`（full_1..3＋3 張特寫）或 `./shoot.sh --tag=x --no-dof`（存成 compare_x.png）。
- 開關：`--no-dof`（景深）、`--no-fog`（體積霧與光束片）、`--no-shadow`（太陽陰影）、`--no-refl`（運河倒影）、`--no-leaves`（落葉粒子）、`--no-frame`（前景楓葉框景）、`--mask`（地面白、其餘黑，量地面佔比）、`--top`（正上方看受光範圍）。
- 可調參數（除錯用）：`--az=28`（光在地面的方位）、`--el=22`（夕陽仰角）、`--sun= --amb= --fill= --exp=`。
- 場景全部在 `main.gd` 以程式組出來；貼圖在 `tex/`（執行時直接讀 PNG，nearest、不經匯入壓縮），全場 32 點陣 / 公尺。
- 素材工具（`tools/`）：`gen.py`（codex 生圖）→ `post.py`（還原成真點陣）→ `sheet.py`（動畫格以腳底對齊）；`plaza.py`（程序化產生不重複的廣場石板）；`pixgen2.py`（遮雨棚、桌布、木箱、木桶、木板、燈籠、失焦楓葉框景）；`report.py`（並排、三階明度、變動像素）。
