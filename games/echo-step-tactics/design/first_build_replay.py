"""첫 빌드 기획 검증(기획실). design/sim/sim.py 의 규칙으로

1. 첫 빌드 3개 층이 풀리는지, 그 정답 행동 순서(golden replay)를 구하고
2. tests/smoke.gd 의 규칙 장면(밟기·베기·화살 막기·오사·증원·턴 제한)의 기대값을 계산한다.

    python3 design/first_build_replay.py

출력의 행동 문자열은 게임 표기(U/R/D/L 이동, SU/SR/SD/SL 베기, W 대기)다.
"""
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sim"))
import sim  # noqa: E402

FLOORS = [
    ("F1 첫걸음", dict(walls=[(1, 1), (5, 1), (1, 5), (5, 5)], start=(3, 6),
                    enemies=[("W", (3, 0)), ("W", (0, 2))], spawns=[(6, "W", (6, 0))])),
    ("F2 궁수의 복도", dict(walls=[(2, 2), (2, 3), (2, 4), (4, 2), (4, 3), (4, 4)], start=(3, 6),
                      enemies=[("A", (3, 0)), ("W", (0, 0)), ("W", (6, 0))], spawns=[(8, "W", (0, 6))])),
    ("F3 두 개의 사선", dict(walls=[(1, 2), (5, 2), (3, 3)], start=(3, 6),
                       enemies=[("A", (0, 0)), ("W", (3, 0)), ("A", (6, 1))],
                       spawns=[(5, "W", (0, 3)), (9, "W", (6, 4))])),
]


def to_game_act(a):
    return a[1] if a[0] == "M" else a


def to_sim_act(a):
    return "M" + a if a in ("U", "R", "D", "L") else a


def solve(fl, hp, depth=3, seed=1):
    g = sim.Game(fl["walls"], fl["start"], fl["enemies"], fl["spawns"], delay=3, hp=hp)
    strat, rng, acts = sim.make_planner(depth), random.Random(seed), []
    while not g.won() and not g.lost() and g.turn < 60:
        a = strat(g, rng)
        acts.append(a)
        g.step(a)
    return g, acts


def play(fl, acts, hp=5):
    g = sim.Game(fl["walls"], fl["start"], fl["enemies"], fl["spawns"], delay=3, hp=hp)
    for a in acts:
        sa = to_sim_act(a)
        assert sa in g.legal_actions(), (a, g.legal_actions())
        g.step(sa)
    return g


def main():
    ok = True
    print("== 1. 첫 빌드 3개 층 정답 재생 ==")
    hp = 5
    for name, fl in FLOORS:
        g, acts = solve(fl, hp)
        print(f"{name}: {'클리어' if g.won() else '실패'} {g.turn}턴 hp {hp}->{g.hp} 처치 {g.kills}")
        print("  " + " ".join(to_game_act(a) for a in acts))
        ok &= g.won()
        # 1수 앞(탐욕)으로는 얼마나 걸리나 — 계획이 필요한 층인지 참고
        g1, _ = solve(fl, 5, depth=1)
        print(f"  (참고) 1수 앞: {'클리어' if g1.won() else '실패'} {g1.turn}턴, 받은 피해 {g1.dmg_taken}")
        hp = min(5, g.hp + 1)

    print("\n== 2. 규칙 장면 기대값 (tests/smoke.gd 와 같은 장면) ==")
    empty = dict(walls=[], start=(3, 6))
    trapped = dict(walls=[(1, 0), (0, 1)], start=(3, 6), enemies=[("W", (0, 0))], spawns=[])

    def show(tag, g):
        fp = [(g.hist[k][0], to_game_act(g.hist[k][1]), k + 3 - g.turn) for k in range(g.turn - 2, g.turn + 1) if k >= 1]
        print(f"{tag}: turn {g.turn} player {g.player} hp {g.hp} echo {g.echo_pos()} "
              f"enemies {[(e.kind, e.pos, e.intent) for e in g.enemies]} kills {g.kills} won {g.won()} footprints {fp}")

    g = sim.Game([(3, 5)], (3, 6), [("A", (2, 6))], [])
    print("M2 불법 행동(가능한 행동만 표시):", [to_game_act(a) for a in g.legal_actions()])

    g = play(trapped, ["U", "U", "U"])
    show("M3 3턴 뒤", g)
    g.step("SL")
    show("M3 4턴 뒤", g)

    g = play(dict(empty, enemies=[("W", (3, 2))], spawns=[]), ["U", "D", "R"])
    show("M4 3턴 뒤", g)
    g.step("MU")
    show("M4 4턴 뒤(밟기)", g)

    g = play(dict(empty, enemies=[("A", (3, 5))], spawns=[]), ["SU", "W", "W"])
    show("M5 3턴 뒤", g)
    g.step("W")
    show("M5 4턴 뒤(베기)", g)

    g = sim.Game([], (3, 6), [("W", (3, 5))], [])
    show("M6 시작", g)
    g.step("W")
    show("M6 맞음", g)
    g.step("ML")
    show("M6 피함", g)

    g = sim.Game([], (3, 3), [("A", (3, 0))], [])
    show("M7 시작", g)
    for a in ["MD", "MD", "MD", "W", "W"]:
        g.step(a)
        show("M7 " + to_game_act(a), g)

    g = play(dict(empty, enemies=[("W", (2, 4)), ("A", (3, 0))], spawns=[]), ["W"])
    show("M8 오사", g)

    g = sim.Game([], (3, 6), [("W", (3, 5))], [])
    for _ in range(5):
        g.step("W")
    show("M10 5번 대기", g)

    fl = dict(walls=[(1, 0), (0, 1), (2, 0), (4, 0), (3, 1)], start=(3, 6), enemies=[("W", (0, 0))], spawns=[])
    g = sim.Game(fl["walls"], fl["start"], fl["enemies"], fl["spawns"])
    counts = {}
    for t in range(1, 61):
        g.step("W")
        if t in (30, 31, 34, 60):
            counts[t] = len(g.enemies)
    print("M11 증원·턴 제한: 턴별 적 수", counts, "hp", g.hp, "won", g.won())

    g = play(FLOORS[0][1], ["U", "SU", "W"])
    show("M12 입력(U, SU, W)", g)

    print("\nOK" if ok else "\nFAIL: 풀리지 않는 층이 있음")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
