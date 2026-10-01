"""게임 화면을 PNG로 찍는다. 빌드실이 자기 화면을 직접 보고 SCREENS.md와 대조하기 위한 도구.

    python tools/screenshot.py games/<slug> [--godot PATH]

games/<slug>/tests/shots.gd 를 창이 있는 Godot로 실행한다(헤드리스는 그림이 안 그려진다).
shots.gd 는 원하는 장면을 만든 뒤 res://shots/<이름>.png 로 저장하고 "SHOT <이름>"을 출력한다
(작성법은 games/_template/tests/shots.gd). 결과: games/<slug>/shots/*.png

리눅스에서 화면(DISPLAY)이 없으면 xvfb-run 으로 감싸 실행한다. xvfb 가 없으면 실패한다
(그 경우 BUILD.md 에 "스크린샷 못 찍음"이라고 적는다).
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys


def find_godot(explicit):
    for cand in (explicit, os.environ.get("GODOT"), shutil.which("godot")):
        if cand and (os.path.exists(cand) or shutil.which(cand)):
            return cand
    sys.exit("Godot 실행 파일을 찾지 못했습니다. --godot 경로나 GODOT 환경변수를 지정하세요.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("--godot")
    a = ap.parse_args()
    game = os.path.abspath(a.game)
    if not os.path.exists(os.path.join(game, "tests", "shots.gd")):
        sys.exit(f"{a.game}: tests/shots.gd 없음")
    godot = find_godot(a.godot)

    out = os.path.join(game, "shots")
    os.makedirs(out, exist_ok=True)
    # Godot가 캡처 이미지를 게임 리소스로 가져오지 않게 한다
    with open(os.path.join(out, ".gdignore"), "w") as f:
        f.write("")
    for f in glob.glob(os.path.join(out, "*.png")):
        os.remove(f)

    cmd = [godot, "--path", game, "--rendering-driver", "opengl3", "--script", "res://tests/shots.gd"]
    if sys.platform.startswith("linux") and not os.environ.get("DISPLAY"):
        if not shutil.which("xvfb-run"):
            sys.exit("화면(DISPLAY)이 없고 xvfb-run 도 없습니다. 스크린샷을 찍을 수 없습니다.")
        cmd = ["xvfb-run", "-a"] + cmd
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
    except subprocess.TimeoutExpired:
        sys.exit("shots.gd 가 3분 안에 끝나지 않았습니다(quit() 호출을 확인하세요).")
    log = (p.stdout or "") + (p.stderr or "")
    errors = [l for l in log.splitlines() if re.search(r"SCRIPT ERROR|Parse Error", l)]
    shots = sorted(glob.glob(os.path.join(out, "*.png")))
    for s in shots:
        print(os.path.relpath(s, os.path.dirname(game)).replace("\\", "/"))
    if errors:
        print("\n".join(errors[:20]))
    if errors or not shots or p.returncode != 0:
        print(f"\n{os.path.basename(game)}: 스크린샷 실패 (png {len(shots)}개, exit {p.returncode})")
        sys.exit(1)
    print(f"\n{os.path.basename(game)}: 스크린샷 {len(shots)}개")


if __name__ == "__main__":
    main()
