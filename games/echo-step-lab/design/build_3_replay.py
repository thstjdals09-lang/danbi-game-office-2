"""3차 빌드 기획 검증(프로덕션 기획실). design/sim/sim.py 의 규칙으로

1. 캠페인 10개 층의 정답 행동 순서(golden replay)를 구하고 (1~5층은 2차와 같아야 한다)
2. tests/smoke.gd 의 새 규칙 장면(폭탄병 의도·던지기·폭발·오사·쿨다운)의 기대값을 계산하고
3. 되감기 검사에 쓸 장면의 "한 턴 전 상태"를 출력한다(되감기 = 그 상태로 돌아감).

    python3 design/build_3_replay.py

출력의 행동 문자열은 게임 표기(U/R/D/L 이동, SU/SR/SD/SL 베기, W 대기)다.
"""
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


def solve(fl, hp, strat, seed=1):
    g, rng, acts = new_game(fl, hp), random.Random(seed), []
    while not g.won() and not g.lost() and g.turn < 60:
        a = strat(g, rng)
        acts.append(a)
        g.step(a)
    return g, acts


def show(tag, g):
    fp = [(g.hist[k][0], to_game_act(g.hist[k][1]), k + 3 - g.turn) for k in range(g.turn - 2, g.turn + 1) if k >= 1]
    en = [(e.id, e.kind, e.pos, "hp%d" % e.hp, "cool%d" % e.cool, e.intent) for e in g.enemies]
    print(f"{tag}: turn {g.turn} player {g.player} hp {g.hp} echo {g.echo_pos()} sword_wait {g.sword_wait()} "
          f"bombs {g.bombs} enemies {en} spawns {g.spawns} kills {g.kills} won {g.won()} lost {g.lost()} footprints {fp}")


def run(tag, fl, acts):
    g = new_game(fl)
    show(tag + " 시작", g)
    for a in acts:
        sa = to_sim_act(a)
        assert sa in g.legal_actions(), (tag, a, [to_game_act(x) for x in g.legal_actions()])
        g.step(sa)
        show(f"{tag} {a}", g)
    return g


def main():
    ok = True
    print("== 1. 캠페인 10개 층 정답 재생 (3수 앞) ==")
    hp, total = 5, {"stomp": 0, "swing": 0, "friendly": 0, "crush": 0}
    for name, fl in sim.CAMPAIGN:
        g, acts = solve(fl, hp, sim.make_planner(3))
        for k in total:
            total[k] += g.kills[k]
        print(f"{name}: {'클리어' if g.won() else '실패'} {g.turn}턴 hp {hp}->{g.hp} 피해 {g.dmg_taken} 처치 {g.kills}  누적 {total}")
        print("  " + " ".join(to_game_act(a) for a in acts))
        print(f"  층 데이터: {fl}")
        ok &= g.won() and g.dmg_taken == 0
        hp = min(5, g.hp + 1)

    print("\n== 2. 폭탄병 장면 ==")
    # M19·M20 던지기와 폭발: 폭탄병 (3,3), 나는 (3,6)에서 가만히 있는다
    b1 = dict(walls=[], start=(3, 6), enemies=[("B", (3, 3))])
    run("M19/20 가만히", b1, ["W", "W", "W", "W", "W", "W"])
    # M20 비키기: 범위(그 칸 + 상하좌우) 밖으로 두 칸
    run("M20 비킴", b1, ["L", "L", "W"])
    # M20 한 칸만 비키면 범위 안
    run("M20 한 칸", b1, ["W", "L"])
    # 거리 4면 던지지 않고 다가온다
    run("M19 거리 4", dict(walls=[], start=(3, 6), enemies=[("B", (3, 2))]), ["W", "W"])
    # M21 폭발의 오사: 졸개가 폭발 범위로 걸어 들어온다 / 방패병은 정면 무효 없이 체력 1
    run("M21 X", dict(walls=[], start=(3, 6), enemies=[("B", (3, 3)), ("W", (5, 5))]), ["L", "L"])
    run("M21 Y", dict(walls=[], start=(3, 6), enemies=[("B", (3, 3)), ("S", (5, 5))]), ["L", "L"])
    # M22 메아리는 폭발을 막지 않는다: 메아리가 내 칸에 겹쳐 있어도 맞는다
    run("M22 메아리", dict(walls=[(3, 4)], start=(3, 6), enemies=[("B", (6, 6))]), ["W", "W", "W", "W", "W", "W"])
    # 벽에 갇힌 폭탄병(길 없음): 쿨다운 흐름만 본다
    run("M19 쿨다운", dict(walls=[(2, 6), (3, 5), (5, 5), (6, 4), (4, 5)], start=(3, 6), enemies=[("B", (5, 6))]),
        ["W", "W", "W", "W", "W", "W", "W"])

    print("\n== 3. 되감기 장면(한 턴 전 상태가 곧 기대값) ==")
    trapped = dict(walls=[(1, 0), (0, 1)], start=(3, 6), enemies=[("W", (0, 0))])
    run("M23 칼", trapped, ["U", "SU", "W"])
    run("M23 처치", dict(walls=[(1, 0), (0, 1)], start=(3, 6), enemies=[("W", (3, 2)), ("W", (0, 0))]), ["U", "D", "R", "U"])
    run("M23 폭탄", b1, ["W", "L", "L"])
    run("M24 피해", dict(walls=[(1, 0), (0, 1)], start=(3, 6), enemies=[("W", (3, 5)), ("W", (0, 0))]), ["W"])

    print("\nOK" if ok else "\nFAIL: 풀리지 않거나 피해 없이 못 깨는 층이 있음")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
