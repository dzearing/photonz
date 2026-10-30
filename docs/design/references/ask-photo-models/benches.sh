#!/bin/bash
D=~/Library/Caches/photonz-measure-photo; Q=~/Library/Caches/photonz-measure-qwen21
cd $D
echo "== zimage"; PYTHONNOUSERSITE=1 HF_HUB_OFFLINE=1 "$HOME/Library/Application Support/Photonz/Models/picture-tools/env/bin/python" photo_bench.py zimage photos.json out
echo "== qwen"; HF_HOME=$Q/hf HF_HUB_OFFLINE=1 MFLUX_CACHE_DIR=$Q/mflux-cache $Q/envA/bin/python photo_bench.py qwen photos-32.json out
echo "== moss"; HF_HOME=$D/hf HF_HUB_OFFLINE=1 $Q/envB/bin/python photo_bench.py moss photos.json out
echo "== done"
