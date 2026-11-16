#!/bin/bash
# 一次重拍全部交付截圖並做量測：full_1..3、特寫、compare_no_dof / no_shadow / no_fog / mask、compare_target、tone_three_level
cd "$(dirname "$0")"
./shoot.sh
./shoot.sh --tag=no_dof --no-dof
./shoot.sh --tag=no_shadow --no-shadow
./shoot.sh --tag=no_fog --no-fog
./shoot.sh --tag=mask --mask
./shoot.sh --work --no-leaves | tee tools/work/shots.log      # 量測用（關落葉粒子），存到 tools/work/
python3 tools/report.py $(grep -o 'R:[a-z]*=[0-9,-]*' tools/work/shots.log | sed 's/R://')
