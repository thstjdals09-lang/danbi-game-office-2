"""첫 빌드 기획 검증(기획실). design/sim/sim.py 의 규칙(Day 클래스)을 그대로 쓰되, 콘텐츠를 사건 1 "식은 화덕"으로 줄인다.

1. 첫 빌드의 콘텐츠를 sim.py 의 표에서 골라 design/chapter_first.json 으로 내보낸다(빌드실은 이 파일을 그대로 게임에 싣는다).
2. 내보낸 JSON 을 다시 읽어 sim 의 표에 끼우고(규칙 코드는 그대로), tests/smoke.gd 가 쓰는 장면의 틱별 기대값을 출력한다.
3. 수첩이 비었을 때는 풀 수 없고, 쪽지를 본 뒤에는 풀린다는 것을 풀이 탐색기로 확인한다.
4. 규칙 장면 "mini"(3틱짜리 행동, 소지품 상한, 처리 순서)의 데이터와 기대값을 출력한다.

    python3 design/first_build_replay.py

sim.py 의 표와 다르게 한 것은 FIRST_BUILD.md "sim 과 다르게 한 것"에 적었다(전부 데이터이고 규칙 코드는 같다).
"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "sim"))
import sim  # noqa: E402

NPCS = ["bori", "darae", "musoe", "sori"]
NPC_KO = {"bori": "보리", "darae": "다래", "musoe": "무쇠", "sori": "소리"}
FLAGS = {"slip_on_counter", "slip_fallen", "burnt", "bread", "inn_bread", "lunch", "wood", "order", "took"}
# 사건 1의 장면 9개 + 지나가는 모습 4개(지도가 비어 보이지 않게. 풀이와 무관)
WHO = {"N_slip": "darae", "N_slipfall": "bori", "N_dough": "bori", "N_nowood": "bori", "N_burnt": "bori",
       "C_smoke": "bori", "C_run": "bori", "N_nolunch": "darae", "C_evening": "darae",
       "C_sori": "sori", "C_sori2": "sori", "C_fish": "musoe", "C_fishing": "musoe"}
ACTION_IDS = ["wood_take", "wood_give", "slip"]
LABEL = {"wood_take": "장작을 든다", "wood_give": "장작을 준다", "slip": "쪽지를 주워 준다"}
# 같은 끼어들기를 한 바퀴에 두 번 할 수 없게 하는 표지 조건(sim.py 에는 없다)
ONCE = {"wood_take": dict(set=["took"], forbid=["took"]), "wood_give": dict(take=["wood"], forbid=["wood"]),
        "slip": dict(forbid=["order"])}


def rule(d):
    return {"need": [f for f in d.get("need", ())], "forbid": [f for f in d.get("forbid", ()) if f in FLAGS]}


def in_scope(d):
    return all(f in FLAGS for f in d.get("need", ()))


def first_build_data():
    """sim.py 의 표에서 첫 빌드에 쓰는 줄만 고른다. 줄의 순서는 sim.py 그대로(동선은 위에서부터 처음 맞는 줄)."""
    itin = [r for r in sim.ITIN if r[0] in NPCS and in_scope(r[4])]
    events = [e for e in sim.EVENTS if in_scope(e) and all(f in FLAGS for f in e.get("forbid", ())) and all(f in FLAGS for f in e["set"])]
    obs = [o for o in sim.OBS if o["note"] in WHO]
    actions = []
    for a in sim.ACTIONS:
        if a["id"] in ACTION_IDS:
            a = dict(a)
            for k, v in ONCE[a["id"]].items():
                a[k] = list(a.get(k, ())) + v
            actions.append(a)
    return {
        "ticks": sim.T, "tick_seconds": 2.0, "fast_seconds": 0.5, "start": sim.START, "max_items": sim.MAX_ITEMS, "max_queue": 3,
        "places": [{"id": p, "name": sim.KO[p]} for p in sim.LOCS],
        "edges": [[a, b, w] for a, b, w in sim.EDGES],
        "npcs": [{"id": n, "name": NPC_KO[n]} for n in NPCS],
        "itinerary": [dict(npc=n, t0=t0, t1=t1, loc=loc, **rule(c)) for n, t0, t1, loc, c in itin],
        "events": [dict(t=e["t"], set=list(e["set"]), **rule(e)) for e in events],
        "scenes": [dict(note=o["note"], who=WHO[o["note"]], loc=list(o["loc"]) if isinstance(o["loc"], tuple) else [o["loc"]],
                        t0=o["t0"], t1=o["t1"], text=o["text"], **rule(o)) for o in obs],
        "actions": [dict(id=a["id"], label=LABEL[a["id"]], loc=a["loc"], t0=a["t0"], t1=a["t1"], know=list(a.get("know", ())),
                         items=list(a.get("items", ())), npc=a.get("npc", ""), dur=a["dur"], take=list(a.get("take", ())),
                         give=list(a.get("give", ())), set=list(a.get("set", ())), text=a["text"], **rule(a)) for a in actions],
        "goal": ["lunch"],
        "goal_name": "식은 화덕 — 여관의 점심",
        "item_names": {"wood": "장작"},
    }


MINI = {
    "ticks": 90, "tick_seconds": 2.0, "fast_seconds": 0.5, "start": "a", "max_items": 2, "max_queue": 3,
    "places": [{"id": "a", "name": "가"}, {"id": "b", "name": "나"}],
    "edges": [["a", "b", 2]],
    "npcs": [{"id": "n1", "name": "하나"}],
    "itinerary": [dict(npc="n1", t0=0, t1=89, loc="b", need=[], forbid=[])],
    "events": [dict(t=10, set=["late"], need=[], forbid=["fixed"])],
    "scenes": [dict(note="S_ok", who="n1", loc=["b"], t0=10, t1=12, text="고쳐졌다", need=["fixed"], forbid=[]),
               dict(note="S_late", who="n1", loc=["b"], t0=10, t1=12, text="늦었다", need=["late"], forbid=[])],
    "actions": [dict(id="pick", label="돌을 줍는다", loc="a", t0=0, t1=89, know=[], items=[], npc="", dur=1, take=[], give=["stone"],
                     set=[], text="돌을 줍는다", need=[], forbid=[]),
                dict(id="fix", label="고친다", loc="b", t0=0, t1=9, know=[], items=["stone"], npc="n1", dur=3, take=["stone"], give=[],
                     set=["fixed"], text="3틱 걸려 고친다", need=[], forbid=[])],
    "goal": ["fixed"], "goal_name": "작은 장면", "item_names": {"stone": "돌"},
}


def install(data):
    """장 데이터(chapter_first.json 형식)를 sim 모듈의 표에 끼운다. 규칙 코드(Day)는 그대로."""
    sim.T = data["ticks"]
    sim.LOCS = [p["id"] for p in data["places"]]
    sim.KO = {p["id"]: p["name"] for p in data["places"]}
    sim.EDGES = [tuple(e) for e in data["edges"]]
    sim.START = data["start"]
    sim.MAX_ITEMS = data["max_items"]
    sim.DIST = sim.all_pairs()
    sim.ITIN = [(r["npc"], r["t0"], r["t1"], r["loc"], dict(need=r["need"], forbid=r["forbid"])) for r in data["itinerary"]]
    sim.EVENTS = [dict(e) for e in data["events"]]
    sim.OBS = [dict(o, loc=tuple(o["loc"])) for o in data["scenes"]]
    acts = []
    for a in data["actions"]:
        a = dict(a)
        if not a["npc"]:
            del a["npc"]
        acts.append(a)
    sim.ACTIONS = acts
    sim.ACT = {a["id"]: a for a in acts}
    sim.EFFECT = [a["id"] for a in acts]
    sim.GOALS = {data["goal_name"]: data["goal"]}
    sim.ALL_NOTES = sorted({o["note"] for o in sim.OBS})
    return [n["id"] for n in data["npcs"]]


class G:
    """sim.Day 에 '늦은 선택지'와 '본 적 있는 위치'만 덧붙인 것(둘 다 표시용이고 규칙을 바꾸지 않는다. FIRST_BUILD.md 5.8, 5.9)."""

    def __init__(self, npcs, notes=(), seen=None):
        self.npcs = npcs
        self.d = sim.Day(set(notes))
        self.late = []
        self.seen = seen if seen is not None else {}
        self._stand()

    def late_now(self):
        d = self.d
        out = []
        for a in sim.ACTIONS:
            if a["loc"] == d.loc and d.t > a["t1"] and a["id"] not in d.done and sim.ok(a, d.flags) and all(k in d.notes for k in a.get("know", ())) \
                    and all(i in d.items for i in a.get("items", ())):
                out.append(a["id"])
        return out

    def _stand(self):
        d = self.d
        for n in self.npcs:
            if sim.npc_loc(n, d.t, d.flags) == d.loc:
                self.seen[(n, d.t)] = d.loc
        for a in self.late_now():
            if a not in self.late:
                self.late.append(a)

    def tick(self, n=1):
        for _ in range(n):
            self.d._tick(True)
            self._stand()

    def until(self, t):
        self.tick(t - self.d.t)

    def go(self, loc):
        r = self.d.go(loc)
        if r:
            self._stand()
        return r

    def do(self, aid):
        d = self.d
        a = sim.ACT[aid]
        if not d.can(a):
            return False
        d.pending.append((d.t + a["dur"], a))
        self.tick(a["dur"])
        d.done.append(aid)
        return True

    def choices(self):
        return [a["id"] for a in sim.ACTIONS if self.d.can(a)]

    def where(self):
        return " ".join(f"{n}={sim.npc_loc(n, self.d.t, self.d.flags) or '길'}" for n in self.npcs)

    def show(self, tag):
        d = self.d
        print(f"{tag}: t{d.t} 나={d.loc} 물건 {d.items} 표지 {sorted(d.flags)} 새로 {d.new} 한 일 {d.done} "
              f"선택지 {self.choices()} 늦은 {self.late_now()} | {self.where()}")


def main():
    ok = True
    data = first_build_data()
    with io.open(os.path.join(HERE, "chapter_first.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    with io.open(os.path.join(HERE, "chapter_first.json"), encoding="utf-8") as f:
        data = json.load(f)
    npcs = install(data)

    print("== 0. 첫 빌드 콘텐츠 ==")
    print(f"장소 {len(data['places'])} 길 {len(data['edges'])} 주민 {len(data['npcs'])} 동선 줄 {len(data['itinerary'])} 세계 사건 {len(data['events'])} "
          f"장면 {len(data['scenes'])} 행동 {len(data['actions'])}")
    for a in sim.LOCS:
        print("  " + a.ljust(7) + " ".join(f"{b}={sim.DIST[a][b]}" for b in sim.LOCS))
    for o in data["scenes"]:
        print(f"  장면 {o['note']} {o['who']} {o['loc']} {o['t0']}~{o['t1']} need {o['need']} forbid {o['forbid']} — {o['text']}")

    print("\n== 1. 기본 하루: 여관에서 아무것도 안 한다 ==")
    g = G(npcs)
    g.show("idle t0")
    for t in (6, 7, 8, 9, 14, 15, 19, 20, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 36, 37, 39, 40, 49, 50, 75, 76, 89):
        g.until(t)
        g.show(f"idle t{t}")
    print("  수첩:", g.d.new, " 목표:", bool(g.d.goals()))
    ok &= not g.d.goals()

    print("\n== 2. 탐험 바퀴: 빵집에 가서 30틱까지 지켜본다 ==")
    g = G(npcs)
    print("  go bakery:", g.go("bakery"))
    g.show("explore 도착")
    for t in (7, 8, 9, 10, 11, 12, 14, 15, 23, 24, 28, 29, 30):
        g.until(t)
        g.show(f"explore t{t}")
    notes1 = list(g.d.new)
    seen1 = dict(g.seen)
    print("  수첩:", notes1)
    print("  본 위치(보리):", sorted((t, p) for (n, t), p in seen1.items() if n == "bori"))
    print("  본 위치(다래):", sorted((t, p) for (n, t), p in seen1.items() if n == "darae"))
    print("  본 위치(소리):", sorted((t, p) for (n, t), p in seen1.items() if n == "sori"))
    print("  본 위치(무쇠):", sorted((t, p) for (n, t), p in seen1.items() if n == "musoe"))

    print("\n== 3. 길 위에서는 적히지 않는다 ==")
    g = G(npcs)
    g.until(20)
    g.show("road t20 여관(출발 전)")
    print("  go smithy:", g.go("smithy"))
    g.show("road 도착")
    g = G(npcs)
    print("  0틱에 광장으로:", g.go("plaza"))
    g.until(15)
    g.show("plaza t15")
    for t in (16, 18, 19, 21, 24, 33):
        g.until(t)
        g.show(f"plaza t{t}")

    print("\n== 4. 실행 바퀴: 탐험 바퀴의 수첩으로 ==")
    g = G(npcs, notes1, dict(seen1))
    g.show("solve t0")
    print("  go smithy:", g.go("smithy"))
    g.show("solve 대장간")
    print("  wood_take:", g.do("wood_take"))
    g.show("solve 장작")
    print("  wood_take 다시:", g.do("wood_take"))
    print("  go bakery:", g.go("bakery"))
    g.show("solve 빵집")
    print("  wood_give:", g.do("wood_give"))
    g.show("solve 줬다")
    print("  slip:", g.do("slip"))
    g.show("solve 쪽지")
    print("  slip 다시:", g.do("slip"))
    for t in (14, 15, 20, 23, 24, 26, 27, 28, 30, 31, 49, 50, 89):
        g.until(t)
        g.show(f"solve t{t}")
    print("  목표:", bool(g.d.goals()), " 늦은 매듭:", g.late)
    ok &= bool(g.d.goals())

    print("\n== 5. 수첩이 비었을 때: 같은 길로 가도 쪽지 선택지가 없다(장작만 준다) ==")
    g = G(npcs)
    g.go("smithy")
    g.do("wood_take")
    g.go("bakery")
    g.show("woodonly 빵집")
    print("  slip:", g.do("slip"), " wood_give:", g.do("wood_give"))
    g.show("woodonly 줬다")
    for t in (13, 24, 27, 28, 50, 51, 76, 89):
        g.until(t)
        g.show(f"woodonly t{t}")
    print("  목표:", bool(g.d.goals()), " 수첩:", g.d.new, " 늦은 매듭:", g.late)
    ok &= not g.d.goals()

    print("\n== 6. 늦은 장작(여관에서 4틱 기다렸다 출발 → 빵집 15틱) / 턱걸이(3틱 기다림 → 14틱) ==")
    g = G(npcs, notes1)
    g.until(4)
    g.go("smithy")
    g.do("wood_take")
    g.go("bakery")
    g.show("late 빵집")
    print("  wood_give:", g.do("wood_give"))
    for t in (23, 24, 29, 50, 89):
        g.until(t)
        g.show(f"late t{t}")
    print("  목표:", bool(g.d.goals()), " 늦은 매듭:", g.late)
    g = G(npcs, notes1)
    g.until(3)
    g.go("smithy")
    g.do("wood_take")
    g.go("bakery")
    g.show("edge 빵집")
    print("  wood_give:", g.do("wood_give"), " slip:", g.do("slip"))
    g.until(50)
    g.show("edge t50")

    print("\n== 7. 하루의 끝 ==")
    g = G(npcs, notes1)
    g.until(88)
    print("  88틱 여관 → 광장(2틱):", g.go("plaza"), " → 빵집(1틱):", g.go("bakery"))
    g.show("end 빵집")
    print("  89틱 slip:", g.do("slip"))
    g = G(npcs, notes1)
    g.go("bakery")
    g.until(88)
    g.show("end88 빵집")
    print("  88틱 slip:", g.do("slip"))
    g.show("end89")

    print("\n== 8. 풀이 탐색 ==")
    print("  수첩이 비었을 때:", sim.search(set(), ["lunch"]))
    sols = sim.search({"N_slipfall"}, ["lunch"])
    print("  쪽지를 본 뒤:", [(s[0], f"여유 {s[1]}틱") for s in sols])
    ok &= not sim.search(set(), ["lunch"]) and bool(sols)
    # 단순한 전략: 수첩 없이 한 장소에 종일 서 있기 / 수첩을 가진 뒤 출발을 늦추기
    for wait in range(0, 6):
        g = G(npcs, notes1)
        g.until(wait)
        g.go("smithy")
        g.do("wood_take")
        g.go("bakery")
        a = g.do("wood_give")
        b = g.do("slip")
        g.until(50)
        print(f"  {wait}틱 늦게 출발: 빵집 도착 {wait + 11}틱, 장작 {a}, 쪽지 {b}, 점심 {bool(g.d.goals())}")
    for p in sim.LOCS:
        g = G(npcs)
        if p != sim.START:
            g.go(p)
        g.until(89)
        print(f"  {p}에 종일 서 있기: 새로 안 것 {len(g.d.new)}개 {g.d.new}")

    print("\n== 9. 규칙 장면 mini ==")
    print("MINI_JSON " + json.dumps(MINI, ensure_ascii=False, separators=(",", ":")))
    n2 = install(MINI)
    g = G(n2)
    g.show("mini t0")
    print("  pick:", g.do("pick"))
    g.show("mini pick1")
    print("  pick:", g.do("pick"))
    g.show("mini pick2")
    print("  pick(상한):", g.do("pick"))
    print("  go b:", g.go("b"))
    g.show("mini b")
    g.until(7)
    # 7틱에 시작 → 10틱에 끝: 결과(①)가 세계 사건(②)보다 먼저라 late 가 서지 않는다
    d = g.d
    d.pending.append((d.t + 3, sim.ACT["fix"]))
    for _ in range(3):
        g.tick()
        g.show("mini fix@7")
    g = G(n2)
    g.do("pick")
    g.go("b")
    g.until(8)
    d = g.d
    d.pending.append((d.t + 3, sim.ACT["fix"]))
    for _ in range(3):
        g.tick()
        g.show("mini fix@8")
    g = G(n2)
    g.do("pick")
    g.go("b")
    g.until(10)
    g.show("mini 10틱(창 9틱까지)")
    print("  fix:", g.do("fix"))

    print("\nOK" if ok else "\nFAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
