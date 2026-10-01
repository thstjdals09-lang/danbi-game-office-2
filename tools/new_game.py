"""템플릿에서 새 Godot 게임 폴더를 만든다.

    python tools/new_game.py <slug> --title "제목" --pitch "한 줄 설명" [--orientation portrait|landscape]

games/_template를 games/<slug>로 복사하고 이름과 화면 크기를 채운다.
화면 크기는 스튜디오 기본값: 세로 540×960, 가로 960×540.
"""
import argparse
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZES = {"portrait": (540, 960, 405, 720, 1), "landscape": (960, 540, 720, 405, 0)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("slug")
    ap.add_argument("--title", required=True)
    ap.add_argument("--pitch", default="")
    ap.add_argument("--orientation", choices=SIZES, default="portrait")
    a = ap.parse_args()

    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", a.slug):
        sys.exit("slug는 소문자-하이픈 형식이어야 합니다 (예: night-bus)")
    dst = os.path.join(ROOT, "games", a.slug)
    if os.path.exists(dst):
        sys.exit(f"이미 있습니다: games/{a.slug}")

    w, h, wo, ho, orient = SIZES[a.orientation]
    values = {
        "__TITLE__": a.title.replace('"', "'"),
        "__PITCH__": a.pitch.replace('"', "'"),
        "__W__": str(w), "__H__": str(h), "__WO__": str(wo), "__HO__": str(ho),
        "__ORIENT__": str(orient),
    }
    shutil.copytree(os.path.join(ROOT, "games", "_template"), dst)
    for base, _, files in os.walk(dst):
        for name in files:
            if not name.endswith((".godot", ".gd", ".tscn", ".cfg", ".md")):
                continue
            path = os.path.join(base, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            for k, v in values.items():
                text = text.replace(k, v)
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
    print(f"games/{a.slug} 생성 ({a.orientation} {w}x{h})")


if __name__ == "__main__":
    main()
