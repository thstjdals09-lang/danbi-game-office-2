#!/usr/bin/env bash
# 리눅스 환경(클라우드 작업, CI 밖)에서 Godot 4.7.2를 받아 둔다. 이미 있으면 건너뛴다.
#   bash tools/install_godot.sh && export GODOT="$HOME/.local/godot/godot"
#   python3 tools/smoke.py games/<slug>
set -euo pipefail
VER=4.7.2
DIR="$HOME/.local/godot"
BIN="$DIR/godot"
if [ -x "$BIN" ]; then
  echo "$BIN"; exit 0
fi
mkdir -p "$DIR"
cd "$DIR"
curl -fsSL -o godot.zip "https://github.com/godotengine/godot/releases/download/${VER}-stable/Godot_v${VER}-stable_linux.x86_64.zip"
unzip -q -o godot.zip
mv "Godot_v${VER}-stable_linux.x86_64" godot
rm godot.zip
chmod +x godot
"$BIN" --version >&2
echo "$BIN"
