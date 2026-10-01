"""화면 시안(SVG)을 PNG로 그린다. 디자인실이 주 화면을 그려 놓고 **눈으로 보면서** 고치기 위한 도구.

    python tools/render_mock.py games/<slug>/design/mock/main.svg            # → 같은 자리에 main.png
    python tools/render_mock.py a.svg b.svg --out compare.png               # 나란히(앞의 것이 왼쪽)

SVG는 viewBox 가 게임 기준 크기(세로 0 0 540 960 / 가로 0 0 960 540)여야 한다.
크롬·엣지·크로미움 중 하나를 찾아 창 없이 실행한다. 없으면 실패한다(그 경우 SVG를 그대로 두고 문서에 "그려 보지 못함"이라고 적는다).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

CANDIDATES = [
    os.environ.get("CHROME"),
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    shutil.which("google-chrome"), shutil.which("chromium"), shutil.which("chromium-browser"), shutil.which("chrome"),
]


def find_browser():
    for c in CANDIDATES:
        if c and os.path.exists(c):
            return c
    sys.exit("크롬/엣지/크로미움을 찾지 못했습니다. CHROME 환경변수에 실행 파일 경로를 지정하세요.")


def size_of(svg_text):
    m = re.search(r'viewBox="\s*0\s+0\s+([0-9.]+)\s+([0-9.]+)"', svg_text)
    if not m:
        sys.exit('SVG에 viewBox="0 0 <너비> <높이>" 가 필요합니다.')
    return int(float(m.group(1))), int(float(m.group(2)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("svg", nargs="+")
    ap.add_argument("--out")
    a = ap.parse_args()
    texts = [open(p, encoding="utf-8").read() for p in a.svg]
    sizes = [size_of(t) for t in texts]
    gap = 24
    width = sum(w for w, _ in sizes) + gap * (len(sizes) + 1)
    height = max(h for _, h in sizes) + gap * 2
    cells = "".join(f'<div style="width:{w}px;height:{h}px">{t}</div>' for t, (w, h) in zip(texts, sizes))
    html = ('<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#11161d;overflow:hidden}'
            f'.r{{display:flex;gap:{gap}px;padding:{gap}px}}svg{{display:block;width:100%;height:100%}}</style><div class="r">{cells}</div>')
    out = os.path.abspath(a.out or os.path.splitext(a.svg[0])[0] + ".png")
    with tempfile.TemporaryDirectory() as d:
        page = os.path.join(d, "mock.html")
        with open(page, "w", encoding="utf-8") as f:
            f.write(html)
        cmd = [find_browser(), "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={os.path.join(d, 'profile')}",
               f"--window-size={width},{height}", f"--screenshot={out}", "file:///" + page.replace("\\", "/")]
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if not os.path.exists(out):
        sys.exit("그리기 실패:\n" + (p.stderr or p.stdout)[-600:])
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
