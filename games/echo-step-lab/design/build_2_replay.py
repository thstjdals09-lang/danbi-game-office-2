"""2차 빌드 기획 검증(프로덕션 기획실). design/sim/sim.py 의 규칙(칼 하나 포함)으로

1. 기본 5개 층의 정답 행동 순서(golden replay)를 다시 구하고 (1차 정답은 베기를 연달아 써서 더는 쓸 수 없다)
2. tests/smoke.gd 의 새 규칙 장면(칼 하나, 방패 정면, 등 뒤 밟기와 밀치기, 으깨기)의 기대값을 계산하고
3. "제자리에서 베기와 대기만"으로 1층이 어떻게 끝나는지(대표 메모가 풀렸는지) 재생한다.

    python3 design/build_2_replay.py

출력의 행동 문자열은 게임 표기(U/R/D/L 이동, SU/SR/SD/SL 베기, W 대기)다.
"""
import itertools
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sim"))
import sim  # noqa: E402

E = sim.EXAMPLES
FLOORS = [
    ("F1 첫걸음", E["E1 첫걸음"]),
    ("F2 궁수의 복도", E["E2 궁수의 복도"]),
    ("F3 두 개의 사선", sim.F3),
    ("F4 등 뒤", E["E4 등 뒤"]),
    ("F5 협공", E["E5 협공"]),
]


def to_game_act(a):
    return a[1] if a[0] == "M" else a


def to_sim_act(a):
    return "M" + a if a in ("U", "R", "D", "L") else a


def new_game(fl, hp=5):
    return sim.Game(fl["walls"], fl["start"], fl["enemies"], fl["spawns"], delay=3, hp=hp)


def solve(fl, hp, strat, seed=1):
    g, rng, acts = new_game(fl, hp), random.Random(seed), []
    while not g.won() and not g.lost() and g.turn < 60:
        a = strat(g, rng)
        acts.append(a)
        g.step(a)
    return g, acts


def play(fl, acts, hp=5, strict=True):
    """행동을 차례로 넣는다. strict 가 아니면 불가능한 행동은 건너뛰고(턴을 쓰지 않음) 거절된 것을 돌려준다."""
    g, rejected = new_game(fl, hp), []
    for a in acts:
        sa = to_sim_act(a)
        if sa not in g.legal_actions():
            assert not strict, (a, [to_game_act(x) for x in g.legal_actions()])
            rejected.append((g.turn, a))
            continue
        g.step(sa)
    return (g, rejected) if not strict else g


def show(tag, g):
    fp = [(g.hist[k][0], to_game_act(g.hist[k][1]), k + 3 - g.turn) for k in range(g.turn - 2, g.turn + 1) if k >= 1]
    en = [(e.id, e.kind, e.pos, "hp%d" % e.hp, "face" + e.face, e.intent) for e in g.enemies]
    print(f"{tag}: turn {g.turn} player {g.player} hp {g.hp} echo {g.echo_pos()} sword_wait {g.sword_wait()} "
          f"enemies {en} kills {g.kills} won {g.won()} lost {g.lost()} footprints {fp}")


def find(fl, want, max_len=7, alphabet=("MU", "MR", "MD", "ML", "W")):
    """want(g_before, g_after) 가 참이 되는 가장 짧은 행동 순서를 찾는다(장면 만들기용)."""
    for n in range(1, max_len + 1):
        for seq in itertools.product(alphabet, repeat=n):
            g = new_game(fl)
            ok = True
            for i, a in enumerate(seq):
                if a not in g.legal_actions():
                    ok = False
                    break
                before = g.copy()
                g.step(a)
                if g.lost():
                    ok = False
                    break
                if i == n - 1 and want(before, g):
                    return [to_game_act(x) for x in seq]
            if not ok:
                continue
    return None


def main():
    ok = True
    print("== 1. 기본 5개 층 정답 재생 (칼 하나 규칙, 3수 앞) ==")
    hp, total = 5, {"stomp": 0, "swing": 0, "friendly": 0, "crush": 0}
    for name, fl in FLOORS:
        g, acts = solve(fl, hp, sim.make_planner(3))
        for k in total:
            total[k] += g.kills[k]
        print(f"{name}: {'클리어' if g.won() else '실패'} {g.turn}턴 hp {hp}->{g.hp} 처치 {g.kills}  누적 {total}")
        print("  " + " ".join(to_game_act(a) for a in acts))
        ok &= g.won()
        g1, _ = solve(fl, 5, sim.make_planner(1))
        print(f"  (참고) 1수 앞: {'클리어' if g1.won() else '실패'} {g1.turn}턴, 받은 피해 {g1.dmg_taken}, 처치 {g1.kills}")
        hp = min(5, g.hp + 1)

    print("\n== 2. 대표 메모: 제자리에서 베기와 대기만으로 1층 ==")
    g, acts = solve(FLOORS[0][1], 5, sim.make_planner(2, allow_move=False))
    print(f"제자리 베기만(2수 앞): {'클리어' if g.won() else '패배'} {g.turn}턴 hp {g.hp} 처치 {g.kills}")
    print("  " + " ".join(to_game_act(a) for a in acts))
    show("  끝 상태", g)
    g = sim.Game(FLOORS[0][1]["walls"], FLOORS[0][1]["start"], FLOORS[0][1]["enemies"], FLOORS[0][1]["spawns"], sword_cd=0)
    for a in acts:
        if g.won() or g.lost():
            break
        g.step(a)
    print(f"  (참고) 같은 행동을 1차 규칙에서: hp {g.hp}, 적 {len(g.enemies)}")

    print("\n== 3. 규칙 장면 기대값 (tests/smoke.gd 와 같은 장면) ==")
    trapped = dict(walls=[(1, 0), (0, 1)], start=(3, 6), enemies=[("W", (0, 0))], spawns=[])

    # M13 칼 하나의 경계
    g, rej = play(trapped, ["SU", "SU", "SL", "W", "SU", "W", "SR", "W", "SU"], strict=False)
    print("M13 행동 SU SU SL W SU W SR W SU 중 거절된 것(그때의 turn, 행동):", rej)
    g = new_game(trapped)
    for a in ["SU", "W", "W", "W", "SU"]:
        g.step(a)
        show("M13 " + a, g)

    # M14 층이 바뀌면 칼이 돌아온다: 1층에서 U D R 뒤 SU(4턴째)로 밟기 처치와 동시에 칼을 쓴다
    fa = dict(walls=[], start=(3, 6), enemies=[("W", (3, 2))], spawns=[])
    g = play(fa, ["U", "D", "R"])
    show("M14 1층 3턴 뒤", g)
    g.step("SU")
    show("M14 1층 SU(4턴째)", g)

    # M15 방패 정면
    fs = dict(walls=[], start=(3, 6), enemies=[("S", (3, 3))], spawns=[])
    g = new_game(fs)
    show("M15 시작", g)
    for a in ["SU", "W", "ML", "W", "W"]:
        g.step(a)
        show("M15 " + to_game_act(a), g)

    # M16 등 뒤 밟기와 밀치기: 방패병이 내 발자국을 따라오게 한다
    fb = dict(walls=[], start=(3, 3), enemies=[("S", (3, 6))], spawns=[])
    seq = find(fb, lambda b, a: a.kills["stomp"] == 0 and a.enemies and a.enemies[0].hp == 1 and a.dmg_taken == 0)
    print("M16 찾은 순서(방패병 체력 1이 되는 가장 짧은 이동·대기):", seq)
    g = new_game(fb)
    show("M16 시작", g)
    for a in seq:
        g.step(to_sim_act(a))
        show("M16 " + a, g)

    # M17 으깨기: 밀려날 칸이 막혀 있으면 피해 1 추가
    # (가) 벽에 막힘: 벽 (2,3). 메아리가 (3,3)을 왼쪽으로 밟아 방패병을 벽으로 민다
    fc = dict(walls=[(2, 3)], start=(3, 3), enemies=[("S", (3, 6))], spawns=[])
    g = new_game(fc)
    for a in ["R", "L", "U", "U", "U"]:
        g.step(to_sim_act(a))
        show("M17 벽 " + a, g)
    # (나) 플레이어에 막힘: 메아리가 (4,4)를 아래로 밟을 때 내가 (4,5)에 서 있다
    fd = dict(walls=[(3, 2)], start=(3, 3), enemies=[("S", (3, 6))], spawns=[])
    g = new_game(fd)
    for a in ["R", "D", "R", "D", "L"]:
        g.step(to_sim_act(a))
        show("M17 플레이어 " + a, g)

    print("\nOK" if ok else "\nFAIL: 풀리지 않는 층이 있음")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
