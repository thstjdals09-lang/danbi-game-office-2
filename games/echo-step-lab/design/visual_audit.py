"""화면이 얼마나 "심심한가"를 숫자로 본다(4차, 프로덕션 디자인실).

    python3 design/visual_audit.py            games/<slug>/shots/*.png 을 읽는다 (Pillow 필요)

스크린샷마다
- 평평한 정도: 가장 많이 쓰인 두 색이 화면에서 차지하는 비율(%)
- 색 수: 서로 다른 색의 수(참고)
그리고 이름이 `idle-a` / `idle-b` 로 끝나는 두 장(같은 장면을 0.5초 간격으로 찍은 것)이 있으면
- 대기 중 움직임: 두 장에서 달라진 픽셀 비율(%)

GAME_DESIGN 14절 "보는 맛 기준"의 목표값과 비교해 달성 여부를 적는다. 판정은 참고용이고 exit 0 이다.
"""
import glob
import os
import sys
from collections import Counter

TARGET_FLAT_PLAY = 75.0     # 플레이 화면: 가장 많은 두 색 ≤ 75%
TARGET_FLAT_MENU = 85.0     # 타이틀·결과: 가장 많은 두 색 ≤ 85%
TARGET_IDLE_MOTION = 0.5    # 대기 중 0.5초 사이에 달라지는 픽셀 ≥ 0.5%


def main():
    try:
        from PIL import Image, ImageChops
    except ImportError:
        print("Pillow 가 없습니다: pip install pillow")
        return 0
    shots = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shots")
    files = sorted(glob.glob(os.path.join(shots, "*.png")))
    if not files:
        print("shots/*.png 없음")
        return 0
    print(f"{'파일':38s} 두 색 비율  색 수  목표")
    for f in files:
        im = Image.open(f).convert("RGB")
        n = im.size[0] * im.size[1]
        c = Counter(im.getdata())
        flat = 100.0 * sum(v for _, v in c.most_common(2)) / n
        name = os.path.basename(f)[:-4]
        menu = "title" in name or "result" in name or name.endswith("-win")
        target = TARGET_FLAT_MENU if menu else TARGET_FLAT_PLAY
        print(f"{name:38s} {flat:6.1f}%  {len(c):5d}  {'달성' if flat <= target else '미달'} (≤ {target:.0f}%)")
    a = [f for f in files if f.endswith("idle-a.png")]
    b = [f for f in files if f.endswith("idle-b.png")]
    if a and b:
        x, y = Image.open(a[0]).convert("RGB"), Image.open(b[0]).convert("RGB")
        d = ImageChops.difference(x, y).convert("L")
        moved = 100.0 * sum(1 for v in d.tobytes() if v) / (x.size[0] * x.size[1])
        print(f"대기 중 움직임(0.5초): {moved:.2f}%  {'달성' if moved >= TARGET_IDLE_MOTION else '미달'} (≥ {TARGET_IDLE_MOTION}%)")
    else:
        print("대기 중 움직임: idle-a / idle-b 스크린샷이 없어 재지 못함")
    return 0


if __name__ == "__main__":
    sys.exit(main())
