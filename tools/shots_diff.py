"""스크린샷이 이전과 어디가 달라졌는지 본다(프로덕션 빌드의 회귀 확인용).

    python tools/shots_diff.py games/<slug>                    지금 폴더의 shots/ 를 마지막 커밋(HEAD)과 비교
    python tools/shots_diff.py games/<slug> --old <sha>         지금 폴더를 그 커밋과 비교
    python tools/shots_diff.py games/<slug> --old <sha> --new <sha>   두 커밋끼리 비교(검수실)

파일마다 달라진 픽셀 수와 달라진 영역(왼쪽, 위, 오른쪽, 아래)을 적는다. 판정은 하지 않는다 —
달라진 영역이 "이번 차수에 바꾸기로 한 것"인지는 사람이 그 파일을 열어 보고 판단한다.
특히 장면 스크립트(tests/shots.gd)는 그대로인데 규칙이 바뀌어 **이름과 다른 화면**이 찍히는 경우를 찾는 데 쓴다.
Pillow 가 필요하다(pip install pillow).
"""
import argparse
import io
import os
import subprocess
import sys


def git_files(ref, rel):
    out = subprocess.run(["git", "ls-tree", "--name-only", ref, rel + "/"], capture_output=True, text=True)
    return sorted(os.path.basename(p) for p in out.stdout.split("\n") if p.lower().endswith(".png"))


def git_bytes(ref, rel, name):
    p = subprocess.run(["git", "show", f"{ref}:{rel}/{name}"], capture_output=True)
    return p.stdout if p.returncode == 0 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("--old", default="HEAD")
    ap.add_argument("--new")
    a = ap.parse_args()
    try:
        from PIL import Image, ImageChops
    except ImportError:
        sys.exit("Pillow 가 없습니다: pip install pillow")

    rel = a.game.replace("\\", "/").rstrip("/") + "/shots"
    old_names = git_files(a.old, rel)
    if a.new:
        new_names = git_files(a.new, rel)
        load_new = lambda n: git_bytes(a.new, rel, n)
    else:
        new_names = sorted(f for f in os.listdir(rel) if f.lower().endswith(".png")) if os.path.isdir(rel) else []
        load_new = lambda n: open(os.path.join(rel, n), "rb").read()

    print(f"{rel}: {a.old} → {a.new or '작업 폴더'}")
    for n in sorted(set(old_names) | set(new_names)):
        if n not in old_names:
            print(f"  {n}: 새로 생김")
            continue
        if n not in new_names:
            print(f"  {n}: 사라짐")
            continue
        x = Image.open(io.BytesIO(git_bytes(a.old, rel, n))).convert("RGB")
        y = Image.open(io.BytesIO(load_new(n))).convert("RGB")
        if x.size != y.size:
            print(f"  {n}: 크기가 다름 {x.size} → {y.size}")
            continue
        d = ImageChops.difference(x, y)
        box = d.getbbox()
        if not box:
            print(f"  {n}: 같음")
            continue
        px = sum(1 for v in d.convert("L").tobytes() if v)
        print(f"  {n}: 달라진 픽셀 {px} ({100 * px / (x.size[0] * x.size[1]):.1f}%), 영역 {box}")


if __name__ == "__main__":
    main()
