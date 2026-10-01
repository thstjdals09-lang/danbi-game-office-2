"""4차 빌드 기획 검증(프로덕션 기획실). 규칙은 바뀌지 않았다. design/sim/sim.py 로

1. 캠페인 10개 층의 정답이 3차와 같은지 다시 확인하고(같아야 한다),
2. 연출 검사(M26~M32)가 쓰는 장면에서 "그 턴에 무슨 일이 일어나는가"(처치 수와 출처, 피해, 클리어)를 출력한다.
   연출 이름은 규칙의 사건에서 정해지므로(BUILD_4.md "연출 배선표"), 이 출력이 곧 기대값의 근거다.
3. 한 턴에 처치가 둘 나는 가장 작은 장면(연속 처치)을 탐색으로 찾는다.

    python3 design/build_4_replay.py
"""
import itertools
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sim"))
import sim  # noqa: E402


def to_game_act(a):
    return a[1] if a[0] == "M" else a


def to_sim_act(a):
    return "M" + a if a in ("U", "R", "D", "L") else a


def new_game(fl, hp=5):
    return sim.Game(fl["walls"], fl["start"], fl["enemies"], fl.get("spawns", []), delay=3, hp=hp)


def turn_log(tag, fl, acts):
    """행동마다 그 턴에 생긴 일(처치 출처별 증가, 피해, 폭탄, 클리어)을 한 줄씩."""
    g = new_game(fl)
    for a in acts:
        k0, hp0, n0 = dict(g.kills), g.hp, len(g.enemies)
        hps0 = {e.id: e.hp for e in g.enemies}
        pos0 = {e.id: e.pos for e in g.enemies}
        g.step(to_sim_act(a))
        dk = {k: g.kills[k] - k0[k] for k in g.kills if g.kills[k] != k0[k]}
        hurt_e = [i for i, h in hps0.items() if any(e.id == i and e.hp < h for e in g.enemies)]
        print(f"{tag} {a}: turn {g.turn} 처치 {dk or '-'} (합 {sum(dk.values())}) 피해 {hp0 - g.hp} "
              f"다친 적 {hurt_e or '-'} 폭탄 {g.bombs} 적 {[(e.id, e.kind, e.pos, e.hp) for e in g.enemies]} 클리어 {g.won()}")
    return g


def find_combo():
    """폭탄병 (3,3) + 졸개 둘: 한 턴에 처치 2가 나고 내가 다치지 않는 가장 짧은 장면."""
    cells = [(x, y) for x in range(7) for y in range(3, 7) if (x, y) not in ((3, 3), (3, 6))]
    for n in (2, 3):
        for w1, w2 in itertools.combinations(cells, 2):
            if abs(w1[0] - 3) + abs(w1[1] - 6) <= 2 or abs(w2[0] - 3) + abs(w2[1] - 6) <= 2:
                continue
            fl = dict(walls=[], start=(3, 6), enemies=[("B", (3, 3)), ("W", w1), ("W", w2)])
            for seq in itertools.product(("MU", "MR", "MD", "ML", "W"), repeat=n):
                g = new_game(fl)
                ok = True
                for i, a in enumerate(seq):
                    if a not in g.legal_actions():
                        ok = False
                        break
                    before = sum(g.kills.values())
                    g.step(a)
                    if g.dmg_taken:
                        ok = False
                        break
                    if i == n - 1 and sum(g.kills.values()) - before >= 2 and any(e.kind == "B" for e in g.enemies):
                        return fl, [to_game_act(x) for x in seq]
                if not ok:
                    continue
    return None, None


def main():
    ok = True
    print("== 1. 캠페인 10개 층 정답(3수 앞) — 3차와 같아야 한다 ==")
    hp = 5
    for name, fl in sim.CAMPAIGN:
        g, rng, acts = new_game(fl, hp), random.Random(1), []
        strat = sim.make_planner(3)
        while not g.won() and not g.lost() and g.turn < 60:
            a = strat(g, rng)
            acts.append(a)
            g.step(a)
        print(f"{name}: {'클리어' if g.won() else '실패'} {g.turn}턴 피해 {g.dmg_taken}  " + " ".join(to_game_act(a) for a in acts))
        ok &= g.won() and g.dmg_taken == 0
        hp = min(5, g.hp + 1)

    print("\n== 2. 연출 검사 장면: 턴마다 일어나는 일 ==")
    E = sim.EXAMPLES
    turn_log("M26 1층 정답", E["E1 첫걸음"], "U SU L R R U U SR W D D".split())
    turn_log("M27 밟기", dict(walls=[(1, 0), (0, 1)], start=(3, 6), enemies=[("W", (3, 2)), ("W", (0, 0))]), "U D R U W".split())
    turn_log("M27 베기", dict(walls=[(1, 0), (0, 1)], start=(3, 6), enemies=[("A", (3, 5)), ("W", (0, 0))]), "SU W W W".split())
    turn_log("M29 튕김", dict(walls=[], start=(3, 6), enemies=[("S", (3, 3))]), "SU W L W".split())
    turn_log("M29 밀치기", dict(walls=[], start=(3, 3), enemies=[("S", (3, 6))]), "D R W U".split())
    turn_log("M29 으깨기", dict(walls=[(2, 3)], start=(3, 3), enemies=[("S", (3, 6)), ("W", (6, 0))]), "R L U U U".split())
    turn_log("M30 폭발", dict(walls=[], start=(3, 6), enemies=[("B", (3, 3))]), "W W".split())
    turn_log("M30 폭발 비킴", dict(walls=[], start=(3, 6), enemies=[("B", (3, 3))]), "L L".split())
    turn_log("M30 치기 피격", dict(walls=[(1, 0), (0, 1)], start=(3, 6), enemies=[("W", (3, 5)), ("W", (0, 0))]), "W".split())
    turn_log("M31 층 클리어", dict(walls=[], start=(3, 6), enemies=[("W", (3, 2))]), "U D R U".split())

    print("\n== 3. 연속 처치 장면 탐색 ==")
    fl, seq = find_combo()
    print("찾은 층:", fl, "행동:", seq)
    if fl:
        turn_log("M28 연속", fl, seq)
    ok &= fl is not None

    print("\nOK" if ok else "\nFAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
