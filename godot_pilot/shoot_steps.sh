#!/bin/bash
# pilot：逐件換入的四步截圖（每步：full_1..3、crop.png、compare.png、compare_nodof.png）。輸出到 ../shots/godot_pilot/0N_xxx/
# 截圖失敗（視窗被遮住時 Wayland 不送畫格）就不裁切、整個中止，避免用舊圖產生新的裁切。
cd "$(dirname "$0")"
shot() {  # shoot.sh 預設在虛擬螢幕執行（內含限時 40 秒、重試 4 次）；失敗就中止，不用舊圖產生新的裁切
  out=$(./shoot.sh "$@"); echo "$out" | grep -E "SPEC"
  if echo "$out" | grep -q "^done"; then echo "ok: $*"; return 0; fi
  echo "SHOT FAILED: $*"; exit 1
}
step() {  # 資料夾 表面 仍用舊素材的清單
  shot --out=$1 --old=$3
  shot --out=$1 --old=$3 --tag=nodof --no-dof
  python3 art/crops.py $1 $2
}
for a in "$@"; do
  case "$a" in
    1) step 01_ground ground roof,wall,hero ;;
    2) step 02_roof roof wall,hero ;;
    3) step 03_wall wall hero ;;
    4) step 04_hero hero none ;;
    # 第二階段：step2 資料夾 表面 前一步資料夾 其餘參數…
    5) shot --out=05_roofFix --p1=ground,wall --old=baker,child,fisher,cat; python3 art/crops.py 05_roofFix roof final ;;
    5old) shot --out=05_roofFix --p1=ground,wall --old=roof,baker,child,fisher,cat --tag=oldroof ;;
    6) shot --out=06_wallFix --p1=ground --old=baker,child,fisher,cat; python3 art/crops.py 06_wallFix wall 05_roofFix ;;
    7) shot --out=07_ground --old=baker,child,fisher,cat; python3 art/crops.py 07_ground ground 06_wallFix ;;
    7old) shot --out=07_ground --old=ground,baker,child,fisher,cat --tag=oldground ;;
    8) shot --out=08_baker --old=child,fisher,cat; python3 art/crops.py 08_baker baker 07_ground ;;
    9) shot --out=09_child --old=fisher,cat; python3 art/crops.py 09_child child 08_baker ;;
    10) shot --out=10_fisher --old=cat --new-fisher; python3 art/crops.py 10_fisher fisher 09_child ;;
    11) shot --out=11_cat; python3 art/crops.py 11_cat cat 10_fisher ;;
    final2)
      shot --out=final2
      shot --out=final2 --tag=nodof --no-dof --spec
      python3 art/crops.py final2 all ;;
    final)       # 最終交付：四件全開
      shot --out=final
      shot --out=final --tag=nodof --no-dof --spec
      shot --out=final --tag=noglow --no-glow
      shot --out=final --tag=probe --probe --no-leaves
      python3 art/crops.py final all ;;
  esac
done
