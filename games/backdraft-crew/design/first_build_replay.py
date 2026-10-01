"""첫 빌드 기획 검증(기획실). design/sim/sim.py 의 규칙으로

1. 첫 빌드의 고정 건물 3채(단계 1 건물 4, 단계 2 건물 7, 단계 3 건물 11)를 "도착 시점의 상태"로 내보내고
   (design/buildings/*.json — 빌드실이 그대로 싣는다), 그 JSON 을 다시 읽어 만든 상태가 원본과 똑같이 진행되는지 확인한다.
2. 건물마다 봇으로 실제로 풀어 정답 행동 순서(golden replay)와 끝 상태를 출력한다.
3. tests/smoke.gd 의 규칙 장면(박자, 발화, 숨죽음, 되살아남, 역류, 물, 업기, 연기, 문 버팀, 붕괴)의 기대값을 출력한다.
   장면도 같은 JSON 형식이다. `--emit` 을 주면 장면 JSON 을 한 줄씩 출력한다(smoke.gd 에 그대로 넣는다).

    python3 design/first_build_replay.py [--emit]

행동 문자열(게임 표기): 걷기 U R D L(닫힌 문 쪽이면 문 열기) / 물 SU SR SD SL / 문 닫기 CU CR CD CL / 업기 P / 내려놓기 X / 기다리기 W
"""
import copy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "sim"))
import sim  # noqa: E402

W, H, N = sim.W, sim.H, sim.N
DCH = "URDL"
MAT_OF = {(0, False): "_", (3, False): ".", (2, False): "~", (1, False): '"'}
MAT_DEF = {"_": (0, 0), ".": (3, 12), "~": (2, 8), '"': (1, 3), "F": (3, 20)}

BUILDINGS = [("A", 1, 4, "첫 출동"), ("B", 2, 7, "숨죽은 방"), ("C", 3, 11, "카펫 복도")]


# ---------------------------------------------------------------- 상태 <-> JSON
def to_json(s, name="", title=""):
    floor, room, state = [], [], []
    heat, fuel, doors = {}, {}, {}
    for y in range(H):
        fr, rr, sr = "", "", ""
        for x in range(W):
            c = y * W + x
            k = s.kind[c]
            if k == "D":
                d = s.door[c]
                fr += "x" if d[2] else ("/" if d[0] else "+")
                if d[1] != sim.DOOR_HP:
                    doors[str(c)] = d[1]
                rr += " "
                sr += " "
            elif k == ".":
                m = "F" if s.furn[c] else MAT_OF[(s.T[c], False)]
                fr += m
                rr += str(s.room[c])
                if s.rubble[c]:
                    sr += "r"
                elif s.ash[c]:
                    sr += ","
                elif s.fire[c] == 1:
                    sr += "f"
                elif s.fire[c] == 2:
                    sr += "o"
                else:
                    sr += " "
                if s.heat[c] != 0:
                    heat[str(c)] = s.heat[c]
                full = MAT_DEF[m][1]
                if s.fuel[c] != full and not s.ash[c] and not s.rubble[c]:
                    fuel[str(c)] = s.fuel[c]
            else:
                fr += k
                rr += " "
                sr += " "
        floor.append(fr)
        room.append(rr)
        state.append(sr)
    rooms = [dict(air=r.air, gas=r.gas, smolder=r.smolder, front=r.front, hp=r.hp, collapsed=r.collapsed) for r in s.rooms]
    return dict(name=name, title=title, water=s.water, floor=floor, room=room, state=state, heat=heat, fuel=fuel,
                doors=doors, rooms=rooms, victims=[[v[0], v[1]] for v in s.victims if v[2] == "in"])


def from_json(b):
    """JSON → sim 상태. 게임(빌드실)이 건물을 읽는 방법과 같은 절차다(FIRST_BUILD.md "콘텐츠")."""
    s = sim.S()
    nrooms = len(b["rooms"])
    s.rooms = [sim.Room(i) for i in range(nrooms)]
    for y in range(H):
        for x in range(W):
            c = y * W + x
            ch = b["floor"][y][x]
            if ch in "#VE":
                s.kind[c] = ch
            elif ch in "+/x":
                s.kind[c] = "D"
            else:
                s.kind[c] = "."
                rid = int(b["room"][y][x])
                s.room[c] = rid
                s.rooms[rid].cells.append(c)
                s.T[c], s.fuel[c] = MAT_DEF[ch]
                s.furn[c] = ch == "F"
                st = b["state"][y][x]
                if st == "f":
                    s.fire[c] = 1
                elif st == "o":
                    s.fire[c] = 2
                elif st == ",":
                    s.ash[c] = True
                    s.fuel[c] = 0
                    s.furn[c] = False
                elif st == "r":
                    s.rubble[c] = True
                    s.fuel[c] = 0
                    s.furn[c] = False
    for k, v in b["heat"].items():
        s.heat[int(k)] = v
    for k, v in b["fuel"].items():
        s.fuel[int(k)] = v
    # 문: 문 칸의 마주 보는 두 이웃이 속한 방(없으면 -1). 낮은 번호가 먼저
    for y in range(H):
        for x in range(W):
            c = y * W + x
            ch = b["floor"][y][x]
            if ch not in "+/x":
                continue
            near = []
            for d in range(4):
                n = sim.step(c, d)
                if n >= 0 and s.room[n] >= 0 and s.room[n] not in near:
                    near.append(s.room[n])
            near.sort()
            a, bb = (near + [-1, -1])[:2]
            s.door[c] = [ch in "/x", b["doors"].get(str(c), sim.DOOR_HP), ch == "x", a, bb]
            for rid in near:
                s.rooms[rid].doors.append(c)
    for i, r in enumerate(s.rooms):
        rb = b["rooms"][i]
        r.full = len(r.cells) * sim.AIR_PER_CELL
        r.air, r.gas, r.smolder, r.front, r.hp, r.collapsed = rb["air"], rb["gas"], rb["smolder"], rb["front"], rb["hp"], rb["collapsed"]
        r.vent = any(sim.step(c, d) >= 0 and s.kind[sim.step(c, d)] == "V" for c in r.cells for d in range(4))
    s.victims = [[v[0], v[1], "in"] for v in b["victims"]]
    s.water = b["water"]
    s.pos = b.get("start", sim.EXIT)      # 장면용(건물에는 없다 = 출구)
    s.hp = b.get("hp", sim.P_HP)
    s.air = b.get("air", sim.TANK_AIR)
    s.preburn = False
    s.t = 0
    return s


def sig(s):
    """비교용 상태 서명."""
    return (s.pos, s.hp, s.air, s.water, s.carry, s.clock, s.t, tuple(s.fire), tuple(s.heat), tuple(s.fuel), tuple(s.ash),
            tuple(s.rubble), tuple((k, tuple(v[:3])) for k, v in sorted(s.door.items())),
            tuple((r.air, r.gas, r.smolder, r.front, r.hp, r.collapsed) for r in s.rooms), tuple(tuple(v) for v in s.victims))


# ---------------------------------------------------------------- 행동
def to_game(a):
    k = a[0]
    if k == "m":
        return DCH[a[1]]
    if k == "s":
        return "S" + DCH[a[1]]
    if k == "c":
        return "C" + DCH[a[1]]
    return {"p": "P", "d": "X", "w": "W"}[k]


def to_sim(g):
    if g in DCH:
        return ("m", DCH.index(g))
    if g[0] == "S":
        return ("s", DCH.index(g[1]))
    if g[0] == "C":
        return ("c", DCH.index(g[1]))
    return {"P": ("p",), "X": ("d",), "W": ("w",)}[g]


def legal(s, g):
    """게임이 받아들이는 행동인가(FIRST_BUILD.md "행동 가능 여부"). sim 은 불가능한 행동도 한 번의 행동으로 치지만
    게임은 거절하고 행동 수를 쓰지 않는다. 정답 순서에는 불가능한 행동이 없어야 한다."""
    a = to_sim(g)
    k = a[0]
    if k == "m":
        return s.passable(sim.step(s.pos, a[1]))
    if k == "s":
        if s.water <= 0 or s.carry is not None:
            return False
        c = sim.step(s.pos, a[1])
        return not (c < 0 or s.kind[c] in "#VE" or (c in s.door and not s.door[c][0]))
    if k == "c":
        n = sim.step(s.pos, a[1])
        return n in s.door and s.door[n][0] and not s.door[n][2] and not any(v[2] == "in" and v[0] == n for v in s.victims)
    if k == "p":
        return s.carry is None and any(v[2] == "in" and v[0] == s.pos for v in s.victims)
    if k == "d":
        return s.carry is not None and s.kind[s.pos] == "."
    return True


def do(s, seq):
    for g in seq.split():
        assert legal(s, g), (g, xy(s.pos))
        s.act(to_sim(g))
    return s


def xy(c):
    return (c % W, c // W)


def solve(s, botname):
    bot = sim.BOTS[botname](0)
    acts = []
    while s.clock < sim.MAX_ACTIONS and s.hp > 0 and not bot.done:
        a = bot.choose(s)
        g = to_game(a)
        if bot.done:
            break        # 출구에서 "끝"을 정한 뒤의 기다리기는 행동이 아니다(게임에서는 철수 버튼)
        if not legal(s, g):
            # sim 은 불가능한 행동도 행동 하나로 친다(아무 일 없이 시간만 간다) = 기다리기와 같다
            g, a = "W", ("w",)
        acts.append(g)
        s.act(a)
    return acts


def summary(s):
    st = {"in": 0, "carried": 0, "saved": 0, "dead": 0}
    for v in s.victims:
        st[v[2]] += 1
    return (f"행동 {s.clock} 박자 {s.t} 위치 {xy(s.pos)} 체력 {s.hp} 공기 {s.air} 물 {s.water} 업음 {s.carry is not None} "
            f"사람 구조 {st['saved']} 안 {st['in']} 사망 {st['dead']} 숨 {[v[1] for v in s.victims]}")


def show(tag, s, cells=(), rooms=(), doors=()):
    """한 줄 요약. 칸: 불(0 없음 1 불 2 숨죽은 불)/열/탈 것(+a 재, +r 잔해). 방: 공기·가스·front·버팀(+S 숨죽음 +X 무너짐 +밀 밀폐 +연 연기)."""
    st = "".join({"in": "i", "carried": "c", "saved": "s", "dead": "d"}[v[2]] + str(v[1]) + " " for v in s.victims).strip()
    out = f"{tag}: a{s.clock} b{s.t} {xy(s.pos)} hp{s.hp} air{s.air} w{s.water}{' 업음' if s.carry is not None else ''}"
    if st:
        out += f" | 사람 {st}"
    for c in cells:
        out += f" | {xy(c)} {s.fire[c]}/{s.heat[c]}/{s.fuel[c]}{'a' if s.ash[c] else ''}{'r' if s.rubble[c] else ''}"
    for r in rooms:
        rr = s.rooms[r]
        out += (f" | 방{r} 공기{rr.air} 가스{rr.gas} f{rr.front} 버팀{rr.hp}{'S' if rr.smolder else ''}{'X' if rr.collapsed else ''}"
                f"{'밀' if s.sealed(rr) else ''}{'연' if s.smoky(rr) else ''}")
    for d in doors:
        out += f" | 문{xy(d)} {'열림' if s.door[d][0] else '닫힘'} {s.door[d][1]}{' 탐' if s.door[d][2] else ''} 징후 {door_sign(s, d)}"
    fc = forecast(s)
    if fc:
        out += f" | 예보 {[xy(c) for c in fc]}"
    print(out)


def forecast(s):
    """다음 불 박자에 새로 불이 붙을 칸(화면의 "!" 예보). 규칙을 한 박자 그대로 돌려 본 결과다.
    되살아나는 불씨(숨죽은 불 → 불)는 넣지 않는다 — 새로 붙는 칸만."""
    t = copy.deepcopy(s)
    before = list(t.fire)
    t.fire_step()
    return [c for c in range(N) if t.fire[c] == 1 and before[c] == 0]


def door_sign(s, d):
    """닫힌 문의 징후(GAME_DESIGN 6.7). 문에 붙은 방(복도 제외) 가운데 가장 위험한 것 하나.
    backdraft: 숨죽음·가스 5 이상 / smolder: 숨죽음·가스 4 이하 / burning: 밀폐된 채 불타는 중 / none"""
    if s.door[d][0]:
        return "none"
    best = "none"
    rank = {"none": 0, "burning": 1, "smolder": 2, "backdraft": 3}
    for rid in s.door[d][3:5]:
        if rid <= 0:
            continue
        r = s.rooms[rid]
        if r.collapsed:
            continue
        if r.smolder and r.gas >= sim.GAS_BURST:
            sign = "backdraft"
        elif r.smolder:
            sign = "smolder"
        elif any(s.fire[c] == 1 for c in r.cells):
            sign = "burning"
        else:
            sign = "none"
        if rank[sign] > rank[best]:
            best = sign
    return best


def ascii_map(s):
    b = to_json(s)
    out = []
    for y in range(H):
        row = ""
        for x in range(W):
            c = y * W + x
            ch = b["floor"][y][x]
            st = b["state"][y][x]
            if any(v[0] == c and v[2] == "in" for v in s.victims):
                ch = "P"
            elif st == "f":
                ch = "*"
            elif st in "o,r":
                ch = st
            row += ch
        out.append(row)
    return "\n".join(out)


# ---------------------------------------------------------------- 장면(작은 검사용 건물)
def scene(floor, room, state=None, victims=(), water=8, heat=None, fuel=None, doors=None, rooms=None, start=None, hp=None, air=None):
    """글자 지도에서 장면 JSON 을 만든다. rooms 를 안 주면 방마다 공기 가득, 가스 0, 버팀 30."""
    nr = 1 + max(int(ch) for row in room for ch in row if ch != " ")
    count = [sum(row.count(str(i)) for row in room) for i in range(nr)]
    rs = [dict(air=count[i], gas=0, smolder=False, front=-1, hp=sim.ROOM_HP, collapsed=False) for i in range(nr)]
    for i, over in (rooms or {}).items():
        rs[i].update(over)
    b = dict(name="scene", title="", water=water, floor=floor, room=room, state=state or [" " * W] * H,
             heat={str(k): v for k, v in (heat or {}).items()}, fuel={str(k): v for k, v in (fuel or {}).items()},
             doors={str(k): v for k, v in (doors or {}).items()}, rooms=rs, victims=[list(v) for v in victims])
    if start is not None:
        b["start"] = start
    if hp is not None:
        b["hp"] = hp
    if air is not None:
        b["air"] = air
    return b


def cell(x, y):
    return y * W + x


def base(door="+", cor=".", roomch=".", cor_over=None):
    """장면 뼈대: 세로 복도(x=5, 방 0) + 오른쪽 3x3 방(x 7~9, y 4~6, 방 1), 문은 (6,5)."""
    fl, rm = ["###########"], [" " * W]
    for y in range(1, 12):
        c = (cor_over or {}).get(y, cor)
        if 4 <= y <= 6:
            fl.append("#####" + c + (door if y == 5 else "#") + roomch * 3 + "#")
            rm.append("     0 111 ")
        else:
            fl.append("#####" + c + "#####")
            rm.append("     0     ")
    fl.append("#####E#####")
    rm.append(" " * W)
    return fl, rm


def marks(m):
    g = [[" "] * W for _ in range(H)]
    for (x, y), ch in m.items():
        g[y][x] = ch
    return ["".join(r) for r in g]


def make_scenes():
    """key -> (장면 JSON, 행동 순서, 보여 줄 칸, 방, 문)"""
    out = {}
    fl, rm = base()
    # 열과 발화: 복도 (5,3)에 불. 나무(T 3)는 3박자 뒤에 붙는다
    out["heat"] = (scene(fl, rm, marks({(5, 3): "f"})), "W W W W W W W W",
                   [cell(5, 2), cell(5, 3), cell(5, 4), cell(5, 5)], [], [])
    # 소방관이 서 있는 칸은 붙지 않는다
    out["stand"] = (scene(fl, rm, marks({(5, 3): "f"}), start=cell(5, 4)), "W W W W W W W W D W W",
                    [cell(5, 4), cell(5, 5)], [], [])
    # 재와 식음: 타일 복도, 방 안 (7,5) 불 탈 것 2. 문은 열림(밀폐 아님)
    fl2, rm2 = base(door="/", cor="_")
    out["ash"] = (scene(fl2, rm2, marks({(7, 5): "f"}), fuel={cell(7, 5): 2}, heat={cell(8, 5): 1}), "W W W W W W W W",
                  [cell(7, 5), cell(8, 5), cell(7, 4)], [1], [])
    # 밀폐된 9칸 방: 공기 9를 다 쓰면 숨죽고 가스가 찬다
    fl3, rm3 = base(door="+", cor="_")
    out["seal"] = (scene(fl3, rm3, marks({(8, 5): "f"})), " ".join(["W"] * 24), [cell(8, 5), cell(7, 5)], [1], [cell(6, 5)])
    # 되살아남: 숨죽은 방(가스 2), 불씨 (7,5)(8,5)(9,5). (5,5)에서 문을 연다 → 흡입 1박자 → 한 칸씩
    sm = marks({(7, 5): "o", (8, 5): "o", (9, 5): "o"})
    smr = {1: dict(air=0, smolder=True, gas=2)}
    out["revive"] = (scene(fl3, rm3, sm, rooms=smr, start=cell(5, 5)), "R W W W W W W W", [cell(7, 5), cell(8, 5), cell(9, 5)], [1], [cell(6, 5)])
    # 다시 닫으면 멈춘다
    out["reclose"] = (scene(fl3, rm3, sm, rooms=smr, start=cell(5, 5)), "R W W W CR W W W", [cell(7, 5), cell(8, 5), cell(9, 5)], [1], [cell(6, 5)])
    # 역류: 가스 5. 문 앞 (5,5)에 그대로 서 있으면 맞는다
    bdr = {1: dict(air=0, smolder=True, gas=5)}
    out["backdraft"] = (scene(fl3, rm3, sm, rooms=bdr, start=cell(5, 5)), "R W W W W", [cell(5, 5), cell(7, 5), cell(8, 5), cell(9, 5)], [1], [cell(6, 5)])
    # 역류를 비켜선다: 문을 열고 위로 한 칸
    out["dodge"] = (scene(fl3, rm3, sm, rooms=bdr, start=cell(5, 5)), "R U W W W", [cell(5, 5), cell(7, 5), cell(8, 5)], [1], [cell(6, 5)])
    # 흡입 박자 안에 다시 닫으면 폭발하지 않는다(가스는 그대로)
    out["bd_close"] = (scene(fl3, rm3, sm, rooms=bdr, start=cell(5, 5)), "R CR W W W W", [cell(5, 5), cell(7, 5)], [1], [cell(6, 5)])
    # 물: (5,6)에서 위로. (5,5)(5,4)(5,3) 불
    out["water"] = (scene(fl3, rm3, marks({(5, 3): "f", (5, 4): "f", (5, 5): "f"}), fuel={cell(5, 3): 9, cell(5, 4): 9, cell(5, 5): 9},
                          start=cell(5, 6), water=2), "SU W W W W SR SU SU", [cell(5, 3), cell(5, 4), cell(5, 5)], [], [cell(6, 5)])
    # 업기와 구조: 복도 (5,9)의 사람. 업고 걷기는 2행동
    out["carry"] = (scene(fl3, rm3, victims=[(cell(5, 9), 12)], start=cell(5, 10), air=100), "SU P U SU P X P D D D D", [], [], [])
    # 불 위를 걷는다: 타일 복도에 불 한 칸(나무 한 칸), 업은 채 밟으면 사람 숨 -2
    fl4, rm4 = base(door="+", cor="_", cor_over={8: "."})
    out["firewalk"] = (scene(fl4, rm4, marks({(5, 8): "f"}), victims=[(cell(5, 6), 12)], start=cell(5, 6)), "P D D D D D D", [cell(5, 8)], [], [])
    # 사람의 숨: 방 (8,5)에 사람, 문 열림, 복도 타일 + (5,2) 나무 불. 연기는 5박자마다 -1
    fl5, rm5 = base(door="/", cor="_", cor_over={2: "."})
    out["smoke"] = (scene(fl5, rm5, marks({(5, 2): "f"}), victims=[(cell(8, 5), 12)]), " ".join(["W"] * 22), [], [0, 1], [])
    # 문을 닫으면 연기가 끊긴다
    out["smoke_cut"] = (scene(fl5, rm5, marks({(5, 2): "f"}), victims=[(cell(8, 5), 12)], start=cell(5, 5)), "CR " + " ".join(["W"] * 21), [], [0, 1], [cell(6, 5)])
    # 옆 칸 불 -1, 자기 칸 불 -2, 0이면 사망: 방 안 (8,5) 사람 숨 3, (7,5) 불(탈 것 넉넉)
    out["burn"] = (scene(fl2, rm2, marks({(7, 5): "f"}), victims=[(cell(8, 5), 3)]), "W W W W W W W W", [cell(7, 5), cell(8, 5)], [1], [])
    # 문 버팀: 닫힌 문 (6,5) 버팀 2, 복도 (5,5) 불(탈 것 넉넉). 2박자 뒤 타서 열린다
    fl6, rm6 = base(door="+", cor="_", cor_over={5: "."})
    out["doorburn"] = (scene(fl6, rm6, marks({(5, 5): "f"}), doors={cell(6, 5): 2}, start=cell(5, 7)), "W W W W W W U U CR", [cell(7, 5)], [1], [cell(6, 5)])
    # 붕괴: 방 버팀 2, 안에 불. 2박자 뒤 무너진다. 안의 사람 사망, 안에 선 소방관 -2
    out["collapse"] = (scene(fl2, rm2, marks({(9, 4): "f"}), rooms={1: dict(hp=2)}, victims=[(cell(9, 6), 12)], start=cell(7, 5)),
                       "W W W W L L R R R", [cell(7, 5), cell(9, 4)], [1], [])
    # 공기통: 공기 2에서 시작. 0 아래로 내려가면 6행동마다 체력 -1, 출구에서 다시 찬다
    out["air"] = (scene(fl3, rm3, start=cell(5, 3), air=2), " ".join(["W"] * 15), [], [], [])
    # 순직: 체력 1로 불 위에
    out["death"] = (scene(fl4, rm4, marks({(5, 8): "f"}), start=cell(5, 7), hp=1), "D W", [cell(5, 8)], [], [])
    return out


def main():
    emit = "--emit" in sys.argv
    ok = True
    os.makedirs(os.path.join(HERE, "buildings"), exist_ok=True)

    print("== 1. 고정 건물 3채: 내보내기와 되읽기 ==")
    built = {}
    for name, tier, seed, title in BUILDINGS:
        s0 = sim.gen(seed, tier)
        b = to_json(s0, name, title)
        path = os.path.join(HERE, "buildings", name + ".json")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(b, f, ensure_ascii=False, indent=1)
            f.write("\n")
        built[name] = b
        print(f"\n건물 {name} (단계 {tier}, 시드 {seed}) 「{title}」 물 {b['water']} 사람 {[(xy(v[0]), v[1]) for v in b['victims']]}")
        print(ascii_map(s0))
        for i, r in enumerate(s0.rooms):
            print(f"  방{i}: 칸 {len(r.cells)} 공기 {r.air} 숨죽음 {r.smolder} 가스 {r.gas} 버팀 {r.hp} 깨진 창 {r.vent} 문 {[xy(d) for d in r.doors]}")
        # 되읽기: 같은 봇으로 원본과 JSON 판을 끝까지 돌려 매 행동 뒤 상태가 같은지
        for bot in ("doorman(문+징후)", "soaker(물만)"):
            a, c = sim.gen(seed, tier), from_json(json.loads(json.dumps(b)))
            ba, bc = sim.BOTS[bot](0), sim.BOTS[bot](0)
            same = sig(a) == sig(c)
            while same and a.clock < sim.MAX_ACTIONS and a.hp > 0 and not ba.done:
                a.act(ba.choose(a))
                c.act(bc.choose(c))
                same = sig(a) == sig(c)
            print(f"  되읽기({bot}): {'같음' if same else '다름!'}")
            ok &= same

    print("\n== 2. 정답 재생(봇) ==")
    for name, tier, seed, title in BUILDINGS:
        for bot in sim.BOTS:
            if bot == "random":
                continue
            s = from_json(built[name])
            acts = solve(s, bot)
            print(f"건물 {name} [{bot}] {len(acts)}번 입력: {summary(s)} | 문닫기 {s.stat['closes']} 물 {s.stat['sprays']} 역류 {s.stat['bursts']} 역류피격 {s.stat['burst_hit']} 붕괴 {s.stat['collapses']}")
            print("   " + " ".join(acts))

    print("\n== 3. 규칙 장면 (tests/smoke.gd 와 같은 장면) ==")
    scenes = make_scenes()
    for key, (b, seq, cells, rooms, doors) in scenes.items():
        s = from_json(json.loads(json.dumps(b)))
        show(key + " 시작", s, cells, rooms, doors)
        for g in seq.split():
            if not legal(s, g):
                print(f"{key} {g}: 거절(행동 수 그대로 {s.clock})")
                continue
            s.act(to_sim(g))
            show(f"{key} {g}", s, cells, rooms, doors)
    if emit:
        print("\n== 장면 JSON (smoke.gd 의 SCENES) ==")
        for key, (b, *_r) in scenes.items():
            print(key + "\t" + json.dumps(b, ensure_ascii=False, separators=(",", ":")))
    print("\nOK" if ok else "\nFAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
