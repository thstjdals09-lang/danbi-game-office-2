"""게임 한 개를 헤드리스로 검사한다.

    python tools/smoke.py games/<slug> [--godot PATH]

1. 리소스 import
2. 메인 씬을 5초 동안 실행 — 스크립트 오류가 한 줄이라도 나오면 실패
3. tests/smoke.gd 실행 — 기획서 must_work 항목 확인, 종료 코드 0이어야 통과

CI(.github/workflows/ci.yml)와 Builder/QA가 같은 명령을 쓴다.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

ERROR_PATTERNS = re.compile(r"SCRIPT ERROR|Parse Error|Invalid call|ERROR: .*(res://|Script)|Failed to load script")
# 첫 import 중에는 아직 변환되지 않은 리소스(폰트 등)를 읽지 못했다는 오류가 정상적으로 나온다.
# import 단계는 스크립트 오류만 보고, 리소스 문제는 다음 실행 단계에서 잡는다.
IMPORT_ERROR_PATTERNS = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script")


def find_godot(explicit):
    for cand in (explicit, os.environ.get("GODOT"), shutil.which("godot")):
        if cand and (os.path.exists(cand) or shutil.which(cand)):
            return cand
    sys.exit("Godot 실행 파일을 찾지 못했습니다. --godot 경로나 GODOT 환경변수를 지정하세요.")


def run(godot, game, args, timeout):
    cmd = [godot, "--headless", "--path", game, *args]
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("--godot")
    a = ap.parse_args()
    godot = find_godot(a.godot)
    game = os.path.abspath(a.game)
    if not os.path.exists(os.path.join(game, "project.godot")):
        sys.exit(f"{a.game}: project.godot 없음")

    failed = []

    _, out = run(godot, game, ["--import"], 300)
    if IMPORT_ERROR_PATTERNS.search(out):
        failed.append("import 중 스크립트 오류")
        print(out)

    _, out = run(godot, game, ["--quit-after", "300"], 120)
    errors = [l for l in out.splitlines() if ERROR_PATTERNS.search(l)]
    if errors:
        failed.append("메인 씬 실행 중 오류")
        print("\n".join(errors[:20]))

    test = os.path.join(game, "tests", "smoke.gd")
    if not os.path.exists(test):
        failed.append("tests/smoke.gd 없음")
    else:
        code, out = run(godot, game, ["--script", "res://tests/smoke.gd"], 120)
        print(out.strip())
        if code != 0 or ERROR_PATTERNS.search(out) or "SMOKE PASS" not in out:
            failed.append("tests/smoke.gd 실패")

    name = os.path.basename(game)
    if failed:
        print(f"\n{name}: FAIL — " + ", ".join(failed))
        sys.exit(1)
    print(f"\n{name}: PASS")


if __name__ == "__main__":
    main()
