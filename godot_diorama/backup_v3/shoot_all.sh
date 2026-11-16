#!/bin/bash
# 一次重拍全部交付截圖並做量測。 OUT=r2 ./shoot_all.sh → ../shots/godot_diorama/r2/
cd "$(dirname "$0")"
O=${OUT:+--out=$OUT}
./shoot.sh $O
./shoot.sh $O --tag=no_dof --no-dof
./shoot.sh $O --tag=no_shadow --no-shadow
./shoot.sh $O --tag=no_fog --no-fog
./shoot.sh $O --tag=mask --mask
./shoot.sh --work --no-leaves | tee tools/work/shots.log      # 量測用（關落葉粒子），存到 tools/work/
python3 tools/report.py $(grep -o 'R:[a-z]*=[0-9,-]*' tools/work/shots.log | sed 's/R://')
