"""스크린샷을 여러 장씩 한 장에 모은다(전부 열어 봐야 할 때).

    python tools/shots_sheet.py games/<slug> [--out DIR] [--per 10]

games/<slug>/shots/*.png 을 이름순으로 --per 장씩(가로 5장) 모아 DIR/sheet-<n>.png 으로 저장한다.
칸마다 왼쪽 위에 파일 이름이 붙는다. DIR 기본값은 시스템 임시 폴더(저장소에 넣지 않는다).
화면 전체가 바뀌는 차수(질감·아트 교체)에는 shots_diff 의 "달라진 영역"이 쓸모없으므로,
이 모음으로 "파일 이름이 말하는 화면이 그대로 찍혀 있는가"를 한 장도 빼지 않고 본다.
Pillow 가 필요하다(pip install pillow).
"""
import argparse
import glob
import os
import sys
import tempfile


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("--out")
    ap.add_argument("--per", type=int, default=10)
    a = ap.parse_args()
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        sys.exit("Pillow 가 없습니다: pip install pillow")
    files = sorted(glob.glob(os.path.join(a.game, "shots", "*.png")))
    if not files:
        sys.exit("shots/*.png 없음")
    out = a.out or os.path.join(tempfile.gettempdir(), "shots-" + os.path.basename(os.path.abspath(a.game)))
    os.makedirs(out, exist_ok=True)
    cols, tw = 5, 300
    for n, s in enumerate(range(0, len(files), a.per)):
        chunk = files[s:s + a.per]
        first = Image.open(chunk[0])
        th = int(tw * first.size[1] / first.size[0])
        rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * tw, rows * (th + 22)), (0, 0, 0))
        d = ImageDraw.Draw(sheet)
        for i, f in enumerate(chunk):
            x, y = (i % cols) * tw, (i // cols) * (th + 22)
            sheet.paste(Image.open(f).convert("RGB").resize((tw, th)), (x, y + 22))
            d.text((x + 4, y + 5), os.path.basename(f)[:-4], fill=(255, 255, 0))
        path = os.path.join(out, f"sheet-{n}.png")
        sheet.save(path)
        print(path, f"({len(chunk)}장: {os.path.basename(chunk[0])[:-4]} ~ {os.path.basename(chunk[-1])[:-4]})")


if __name__ == "__main__":
    main()
