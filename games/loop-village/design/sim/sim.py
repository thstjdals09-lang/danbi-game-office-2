"""같은 하루 — 규칙 시뮬레이션 (종이 프로토타입)

    python sim.py

GAME_DESIGN.md 6절의 규칙과 8절의 1장 콘텐츠(마을, 주민 6명, 사건 3개 + 완벽한 하루)를 그대로 옮겼다.
표준 라이브러리만 쓰고 난수는 시드 고정. 판정이 하나라도 실패하면 exit 1.

확인하는 것
  [1] 완벽한 하루가 있는가, 풀이가 몇 가지인가, 얼마나 빠듯한가
  [2] 매듭마다 빼면 안 풀리는가(필요성)
  [3] 아는 것 없이(수첩 없이) 풀리는가
  [4] 계획이 필요한가: 탐욕 순서가 통하는 길과 안 통하는 길, 시간까지 맞는 순서의 비율
  [5] 탐험 방식별로 몇 바퀴 만에 푸는가, 새 사실이 안 나오는 바퀴가 얼마나 이어지는가
  [6] 지켜보는 시간이 비어 있지 않은가(장소별 사건 밀도)
  [7] 걷는 시간이 조금만 늘어도 깨지는가(민감도)
"""
import itertools
import random
import sys

T = 90  # 하루 = 90틱 (1틱 = 2초 → 3분). 화면 시계: 06:00 + 8분 × 틱 (45틱 = 정오)

LOCS = ["inn", "bakery", "plaza", "post", "smithy", "tower", "dock"]
KO = {"inn": "여관", "bakery": "빵집", "plaza": "광장", "post": "우체국", "smithy": "대장간",
      "tower": "종탑", "dock": "나루터"}
EDGES = [("inn", "bakery", 1), ("inn", "plaza", 2), ("bakery", "plaza", 2), ("plaza", "post", 2),
         ("plaza", "smithy", 3), ("plaza", "tower", 3), ("post", "tower", 2), ("smithy", "dock", 2),
         ("plaza", "dock", 4)]
START = "inn"


def all_pairs():
    d = {a: {b: (0 if a == b else 999) for b in LOCS} for a in LOCS}
    for a, b, w in EDGES:
        d[a][b] = d[b][a] = w
    for k, i, j in itertools.product(LOCS, LOCS, LOCS):
        if d[i][k] + d[k][j] < d[i][j]:
            d[i][j] = d[i][k] + d[k][j]
    return d


DIST = all_pairs()


def ok(rule, flags):
    return all(f in flags for f in rule.get("need", ())) and not any(f in flags for f in rule.get("forbid", ()))


# ---- 주민 동선: (주민, 시작틱, 끝틱, 장소, 조건). 앞에서부터 처음 맞는 줄이 그 틱의 위치. 없으면 길 위 ----
ITIN = [
    ("bori", 0, 14, "bakery", {}),
    ("bori", 15, 26, "bakery", {"need": ["wood"]}),
    ("bori", 28, 30, "inn", {"need": ["wood", "order"]}),
    ("bori", 31, 89, "bakery", {"need": ["wood", "order"]}),
    ("bori", 27, 89, "bakery", {"need": ["wood"], "forbid": ["order"]}),
    ("bori", 20, 24, "smithy", {"forbid": ["wood"]}),
    ("bori", 29, 89, "bakery", {"forbid": ["wood"]}),
    ("darae", 0, 6, "inn", {}), ("darae", 7, 8, "bakery", {}), ("darae", 9, 89, "inn", {}),
    ("musoe", 0, 27, "smithy", {}),
    ("musoe", 28, 40, "smithy", {"need": ["told"]}),
    ("musoe", 42, 47, "dock", {"need": ["told"]}),
    ("musoe", 48, 89, "dock", {"need": ["told"], "forbid": ["ferry"]}),
    ("musoe", 30, 60, "dock", {"forbid": ["told"]}),
    ("musoe", 62, 68, "smithy", {"forbid": ["told"]}),
    ("musoe", 70, 89, "dock", {"forbid": ["told"]}),
    ("sori", 0, 18, "post", {}), ("sori", 22, 23, "bakery", {}), ("sori", 24, 25, "inn", {}),
    ("sori", 30, 31, "smithy", {}), ("sori", 37, 38, "tower", {}), ("sori", 40, 89, "post", {}),
    ("hanul", 0, 89, "tower", {}),
    ("naru", 0, 47, "dock", {}), ("naru", 48, 89, "dock", {"forbid": ["ferry"]}),
]

# ---- 세계 사건: 그 틱에 조건이 맞으면 플래그가 선다 (플레이어가 보든 말든) ----
EVENTS = [
    dict(t=8, set=["slip_on_counter"]),
    dict(t=9, set=["slip_fallen"]),
    dict(t=24, forbid=["wood"], set=["burnt"]),
    dict(t=24, need=["wood"], set=["bread"]),
    dict(t=28, need=["bread", "order"], set=["inn_bread"]),
    dict(t=30, need=["told"], set=["musoe_letter"]),
    dict(t=30, forbid=["told"], set=["letter_door"]),
    dict(t=30, need=["told", "sori_chime"], set=["chime_given"]),
    dict(t=45, need=["rope_new"], set=["bell"]),
    dict(t=48, need=["bell", "fed"], set=["ferry"]),
    dict(t=48, need=["ferry", "musoe_letter"], set=["reunion"]),
    dict(t=50, need=["inn_bread"], set=["lunch"]),
]

# ---- 목격: 그 장소에 그 시간에 서 있으면 수첩에 적힌다 ----
OBS = [
    dict(note="N_slip", loc="bakery", t0=8, t1=8, text="다래가 빵 주문 쪽지를 계산대에 두고 간다"),
    dict(note="N_slipfall", loc="bakery", t0=9, t1=9, text="문바람에 쪽지가 계산대 밑으로 날아간다"),
    dict(note="N_dough", loc="bakery", t0=10, t1=10, text="보리가 반죽을 화덕에 넣는다(14틱 굽는다)"),
    dict(note="N_nowood", loc="bakery", t0=12, t1=14, forbid=["wood"], text="보리: 장작이 다 떨어졌네, 무쇠네서 얻어 와야지"),
    dict(note="N_son", loc="smithy", t0=20, t1=24, forbid=["wood"], text="무쇠: 강 건너 아들 솔이는 소식도 없고"),
    dict(note="N_burnt", loc="bakery", t0=24, t1=29, need=["burnt"], text="빈 빵집에서 빵이 탄다"),
    dict(note="N_door", loc="smithy", t0=30, t1=31, forbid=["told"], text="소리가 빈 대장간 문 밑에 편지를 밀어 넣는다"),
    dict(note="N_snap", loc="tower", t0=44, t1=46, forbid=["rope_new"], text="한울이 당기자 종 줄이 끊어진다"),
    dict(note="N_ferryrule", loc="dock", t0=48, t1=52, forbid=["ferry"], text="나루: 종이 울려야 배를 띄우지"),
    dict(note="N_nolunch", loc="inn", t0=50, t1=55, forbid=["inn_bread"], text="다래: 빵이 안 왔네, 오늘 점심 장사는 접자"),
    dict(note="N_late", loc="smithy", t0=62, t1=66, forbid=["told"], text="무쇠가 편지를 읽고 주저앉는다"),
    dict(note="N_pawn", loc="dock", t0=70, t1=80, forbid=["told"], text="무쇠: 다래한테 맡긴 풍경이라도 들려 보낼걸"),
    # 먼 신호와 지나가는 모습: 풀이에 꼭 필요하지는 않지만 어디를 봐야 할지 알려 준다
    dict(note="C_run", loc="plaza", t0=16, t1=18, forbid=["wood"], text="보리가 앞치마 바람으로 대장간 쪽으로 뛰어간다"),
    dict(note="C_sori", loc="plaza", t0=19, t1=21, text="소리가 우편 가방을 메고 빵집 쪽으로 간다"),
    dict(note="C_smoke", loc=("plaza", "inn", "post"), t0=24, t1=29, need=["burnt"], text="빵집 굴뚝에서 검은 연기가 오른다"),
    dict(note="C_fish", loc="smithy", t0=27, t1=28, forbid=["told"], text="무쇠가 낚싯대를 챙겨 나루터로 나선다"),
    dict(note="C_sori2", loc="plaza", t0=33, t1=35, text="소리가 종탑 쪽으로 걸어간다"),
    dict(note="C_nobell", loc=tuple(LOCS), t0=45, t1=46, forbid=["bell"], text="정오인데 종이 울리지 않는다"),
    dict(note="C_fishing", loc="dock", t0=55, t1=60, forbid=["told"], text="무쇠가 말없이 낚시한다. 한 마리도 못 잡았다"),
    dict(note="C_evening", loc="inn", t0=76, t1=82, forbid=["inn_bread"], text="다래: 아침에 주문 쪽지 두고 왔는데 못 봤어? 보리: 쪽지요?"),
    dict(note="C_dusk", loc="tower", t0=84, t1=88, forbid=["rope_new"], text="한울이 끊어진 줄을 들고 한숨을 쉰다"),
]

# ---- 플레이어 행동 ----
#  info=True: 알아내기(수첩에 적힘). 그 밖은 끼어들기(세계를 바꿈).
#  know: 수첩에 있어야 선택지가 보인다. npc: 그 주민이 그 자리에 있어야 한다.
ACTIONS = [
    dict(id="read_letter", info=True, loc="smithy", t0=31, t1=61, need=["letter_door"], dur=1, notes=["N_letter"],
         text="문 밑의 편지를 읽는다: 아버지, 오늘 정오 배로 오세요. 오늘만 기다립니다 — 솔"),
    dict(id="ask_hanul", info=True, loc="tower", t0=45, t1=89, know=["N_snap"], forbid=["bell"], npc="hanul", dur=1,
         notes=["N_spare"], text="한울: 나루 영감 배에 여분 밧줄이 있을 텐데"),
    dict(id="board", info=True, loc="plaza", t0=0, t1=89, dur=1, notes=["C_board"],
         text="광장 게시판: 나룻배는 하루 한 번, 정오 종이 울리면 뜹니다"),
    dict(id="ask_naru", info=True, loc="dock", t0=0, t1=89, npc="naru", dur=1, notes=["N_hungry"],
         text="나루: 아침을 굶어서 노 저을 힘도 없어. 빵 한 덩이면 뭐든 내주지"),
    dict(id="wood_take", loc="smithy", t0=0, t1=89, dur=1, give=["wood"], text="대장간 뒷마당에서 장작을 든다"),
    dict(id="wood_give", loc="bakery", t0=0, t1=14, items=["wood"], npc="bori", dur=1, set=["wood"],
         text="보리에게 장작을 준다 → 보리가 빵집을 비우지 않는다"),
    dict(id="slip", loc="bakery", t0=9, t1=89, know=["N_slipfall"], need=["slip_fallen"], npc="bori", dur=1,
         set=["order"], text="계산대 밑의 쪽지를 주워 보리에게 준다"),
    dict(id="tell", loc="smithy", t0=0, t1=27, know=["N_letter"], npc="musoe", dur=1, set=["told"],
         text="무쇠에게: 솔이한테서 오늘 편지가 와요. 기다리세요"),
    dict(id="loaf", loc="bakery", t0=24, t1=89, need=["bread"], npc="bori", dur=1, give=["loaf"],
         text="보리에게서 빵 한 덩이를 받는다"),
    dict(id="trade", loc="dock", t0=0, t1=47, items=["loaf"], know=["N_hungry", "N_spare"], npc="naru", dur=1,
         take=["loaf"], give=["rope"], set=["fed"], text="나루에게 빵을 주고 여분 밧줄을 받는다"),
    dict(id="install", loc="tower", t0=0, t1=41, items=["rope"], know=["N_snap"], npc="hanul", dur=3,
         take=["rope"], set=["rope_new"], text="한울과 종 줄을 새 밧줄로 간다(3틱)"),
    dict(id="chime_ask", loc="inn", t0=0, t1=89, know=["N_pawn", "N_letter"], npc="darae", dur=1, give=["chime"],
         text="다래에게: 무쇠 아저씨가 오늘 아들을 만나러 가요 → 맡아 둔 풍경을 내준다"),
    dict(id="chime_give", loc="smithy", t0=0, t1=40, items=["chime"], need=["told"], npc="musoe", dur=1,
         take=["chime"], set=["chime_given"], text="대장간에서 무쇠에게 풍경을 건넨다"),
    dict(id="chime_dock", loc="dock", t0=42, t1=47, items=["chime"], npc="musoe", dur=1, take=["chime"],
         set=["chime_given"], text="나루터에서 무쇠에게 풍경을 건넨다"),
    dict(id="chime_sori", loc=None, t0=22, t1=25, items=["chime"], know=["N_door"], npc="sori", dur=1,
         take=["chime"], set=["sori_chime"], text="소리에게 풍경을 맡긴다 → 대장간에 편지와 함께 전한다"),
]
ACT = {a["id"]: a for a in ACTIONS}
GOALS = {
    "사건1 식은 화덕(점심)": ["lunch"],
    "사건2 울리지 않는 종": ["bell"],
    "사건3 정오의 배(재회)": ["reunion"],
    "완벽한 하루": ["lunch", "bell", "reunion", "chime_given"],
}
ALL_NOTES = sorted({o["note"] for o in OBS} | {n for a in ACTIONS for n in a.get("notes", ())})
MAX_ITEMS = 2


def npc_loc(npc, t, flags):
    for n, t0, t1, loc, cond in ITIN:
        if n == npc and t0 <= t <= t1 and ok(cond, flags):
            return loc
    return None


class Day:
    """하루 한 번. 플레이어의 위치·시간·소지품·세계 플래그와, 이 바퀴에 본 것."""

    def __init__(self, notes):
        self.t = 0
        self.loc = START
        self.items = []
        self.flags = set()
        self.notes = set(notes)   # 수첩(이전 바퀴 것 포함)
        self.new = []             # 이 바퀴에 새로 적힌 것
        self.done = []            # 이 바퀴에 한 끼어들기
        self.busy = 0             # 행동/이동에 쓴 틱
        self.pending = []         # (끝나는 틱, 행동)
        self._world(0)
        self._observe()

    def copy(self):
        d = Day.__new__(Day)
        d.t, d.loc, d.items, d.flags = self.t, self.loc, list(self.items), set(self.flags)
        d.notes, d.new, d.done, d.busy, d.pending = set(self.notes), list(self.new), list(self.done), self.busy, \
            list(self.pending)
        return d

    def _world(self, t):
        for end, a in [p for p in self.pending if p[0] == t]:
            self.pending.remove((end, a))
            for it in a.get("take", ()):
                self.items.remove(it)
            self.items += a.get("give", [])
            self.flags |= set(a.get("set", ()))
            for n in a.get("notes", ()):
                self._note(n)
        for e in EVENTS:
            if e["t"] == t and ok(e, self.flags):
                self.flags |= set(e["set"])

    def _note(self, n):
        if n not in self.notes:
            self.notes.add(n)
            self.new.append(n)

    def _observe(self):
        for o in OBS:
            here = o["loc"] == self.loc or (isinstance(o["loc"], tuple) and self.loc in o["loc"])
            if here and o["t0"] <= self.t <= o["t1"] and ok(o, self.flags):
                self._note(o["note"])

    def _tick(self, observing):
        self.t += 1
        self._world(self.t)
        if observing:
            self._observe()

    def wait_until(self, t):
        while self.t < min(t, T - 1):
            self._tick(True)

    def go(self, loc):
        """이동. 길 위에서는 아무것도 보지 못한다. 하루가 끝나기 전에 못 닿으면 False."""
        d = DIST[self.loc][loc]
        if self.t + d > T - 1:
            return False
        for i in range(d):
            self._tick(i == d - 1 and False)
        self.busy += d
        self.loc = loc
        self._observe()
        return True

    def can(self, a):
        if a["loc"] is not None and a["loc"] != self.loc:
            return False
        if not (a["t0"] <= self.t <= a["t1"]) or self.t + a["dur"] > T - 1:
            return False
        if not ok(a, self.flags):
            return False
        if any(k not in self.notes for k in a.get("know", ())):
            return False
        if any(self.items.count(i) < 1 for i in a.get("items", ())):
            return False
        if "npc" in a and npc_loc(a["npc"], self.t, self.flags) != self.loc:
            return False
        if len(self.items) - len(a.get("take", ())) + len(a.get("give", ())) > MAX_ITEMS:
            return False
        if a.get("info") and all(n in self.notes for n in a["notes"]):
            return False
        return True

    def do(self, aid):
        a = ACT[aid]
        if not self.can(a):
            return False
        self.pending.append((self.t + a["dur"], a))
        for _ in range(a["dur"]):
            self._tick(True)
        self.busy += a["dur"]
        if not a.get("info"):
            self.done.append(aid)
        return True

    def info_here(self):
        """지금 여기서 할 수 있는 알아내기 행동을 전부 한다."""
        again = True
        while again:
            again = False
            for a in ACTIONS:
                if a.get("info") and self.can(a):
                    self.do(a["id"])
                    again = True

    def finish(self):
        while self.t < T - 1:
            self.info_here()
            self._tick(True)

    def goals(self):
        return {g for g, fs in GOALS.items() if all(f in self.flags for f in fs)}


# ---------- [1] 풀이 찾기: 끼어들기 행동의 순서를 전부 뒤진다 ----------
EFFECT = [a["id"] for a in ACTIONS if not a.get("info")]


def try_action(day, aid):
    """그 행동을 할 수 있는 가장 이른 때까지 가서(이동 + 기다림) 한다. 안 되면 None."""
    a = ACT[aid]
    locs = [a["loc"]] if a["loc"] else ["bakery", "inn"]
    best = None
    for loc in locs:
        d = day.copy()
        if d.loc != loc and not d.go(loc):
            continue
        while d.t <= a["t1"] and d.t < T - 1 and not d.can(a):
            d._tick(True)
        if d.can(a):
            start = d.t
            d.do(aid)
            if best is None or start < best[1]:
                best = (d, start)
    return best


def search(notes, goal_flags, banned=(), limit=200000):
    """목표 플래그를 전부 세우는 행동 순서를 모은다. (순서, 가장 빠듯한 여유, 끝난 틱)의 목록."""
    out = []
    count = [0]
    seen = set()

    def rec(day, order, slack):
        count[0] += 1
        if count[0] > limit:
            return
        probe = day.copy()
        probe.wait_until(T - 1)
        if all(f in probe.flags for f in goal_flags):
            key = tuple(order)
            if key not in seen:
                seen.add(key)
                out.append((list(order), slack, day.t))
            return
        for aid in EFFECT:
            if aid in order or aid in banned:
                continue
            r = try_action(day, aid)
            if r is None:
                continue
            d2, start = r
            rec(d2, order + [aid], min(slack, ACT[aid]["t1"] - start))

    rec(Day(notes), [], 99)
    return out


def minimal(solutions):
    """군더더기 행동이 없는 풀이만(다른 풀이의 행동 집합을 포함하는 것은 뺀다)."""
    sets = [frozenset(s[0]) for s in solutions]
    keep = []
    for s, fs in zip(solutions, sets):
        if not any(o < fs for o in sets):
            keep.append(s)
    return keep


# ---------- [5] 탐험 봇 ----------
def reachable_goals(notes):
    got = {}
    for g, fs in GOALS.items():
        sols = search(notes, fs, limit=30000)
        if sols:
            got[g] = min(sols, key=lambda s: (len(s[0]), -s[1]))[0]
    return got


def execute(order, notes):
    d = Day(notes)
    for aid in order:
        r = try_action(d, aid)
        if r is None:
            break
        d = r[0]
    d.finish()
    return d


def explore_day(kind, loop, notes, rng, cover):
    d = Day(notes)
    if kind == "stalker":       # 한 바퀴에 주민 한 명을 따라다닌다
        npc = ["bori", "darae", "musoe", "sori", "hanul", "naru"][loop % 6]
        t = 0
        while t < T - 1:
            loc = npc_loc(npc, t, d.flags)
            if loc and loc != d.loc:
                if not d.go(loc):
                    break
                t = d.t
            d.info_here()
            if d.t < T - 1:
                d._tick(True)
            t = d.t
    elif kind == "camper":      # 한 바퀴에 한 곳을 지킨다
        d.go(LOCS[loop % 7])
        d.finish()
    elif kind == "coverage":    # 아직 안 본 (장소, 시간대)를 골라 다닌다. 시간대 = 10틱
        while d.t < T - 1:
            best = None
            for loc in LOCS:
                arrive = d.t + DIST[d.loc][loc]
                b = arrive // 10
                if arrive < T - 1 and (loc, b) not in cover:
                    key = (arrive, LOCS.index(loc))
                    if best is None or key < best[0]:
                        best = (key, loc, b)
            if best is None:
                d.finish()
                break
            d.go(best[1])
            end = min((best[2] + 1) * 10 - 1, T - 1)
            while d.t < end:
                d.info_here()
                if d.t < end:
                    d._tick(True)
            for b in range(best[2], d.t // 10 + 1):
                if d.t >= (b + 1) * 10 - 1 or b == best[2]:
                    cover.add((best[1], b))
    elif kind == "wanderer":    # 아무 데나 가서 아무 때나 머문다. 할 수 있는 끼어들기는 반반으로 한다
        while d.t < T - 1:
            d.info_here()
            for a in ACTIONS:
                if not a.get("info") and a["id"] not in d.done and d.can(a) and rng.random() < 0.5:
                    d.do(a["id"])
            stay = rng.randint(2, 10)
            d.wait_until(d.t + stay)
            if d.t >= T - 1 or not d.go(rng.choice([l for l in LOCS if l != d.loc])):
                d.finish()
    return d


def campaign(kind, seed, max_loops=60, plan=True):
    """바퀴를 거듭하며 수첩을 채우고, 풀 수 있게 된 목표가 생기면 다음 바퀴에 실행한다."""
    rng = random.Random(seed)
    notes = set()
    solved = {}
    cover = set()
    new_per_loop = []
    for loop in range(1, max_loops + 1):
        todo = None
        if plan:
            reach = reachable_goals(notes)
            for g in GOALS:                      # 쉬운 것부터
                if g in reach and g not in solved:
                    todo = (g, reach[g])
                    break
        if todo:
            d = execute(todo[1], notes)
        else:
            d = explore_day(kind, loop - 1, notes, rng, cover)
        gained = len(d.notes - notes)
        notes |= d.notes
        newly = [g for g in d.goals() if g not in solved]
        for g in newly:
            solved[g] = loop
        new_per_loop.append(gained + len(newly))
        if len(solved) == len(GOALS):
            break
    drought = cur = 0
    for x in new_per_loop:
        cur = cur + 1 if x == 0 else 0
        drought = max(drought, cur)
    return solved, len(new_per_loop), drought, new_per_loop, len(notes)


def main():
    checks = []
    full = set(ALL_NOTES)
    print("같은 하루 규칙 시뮬레이션 — 1장: 장소 7곳, 주민 6명, 하루 90틱(3분), 수첩 항목", len(ALL_NOTES), "개\n")

    print("[1] 풀 수 있는가 (수첩이 다 찼을 때)")
    sols = {}
    for g, fs in GOALS.items():
        s = minimal(search(full, fs))
        sols[g] = s
        if not s:
            print(f"    {g}: 풀이 없음")
            continue
        best = max(s, key=lambda x: x[1])
        sets = {frozenset(x[0]) for x in s}
        print(f"    {g}: 행동 조합 {len(sets)}가지, 순서까지 세면 {len(s)}가지, 끼어들기 {len(best[0])}번, "
              f"가장 넉넉한 풀이의 최소 여유 {best[1]}틱, 가장 빠듯한 풀이의 여유 {min(x[1] for x in s)}틱")
    perfect = sols["완벽한 하루"]
    best = max(perfect, key=lambda x: x[1]) if perfect else None
    if best:
        d = Day(full)
        print("\n    가장 넉넉한 완벽한 하루:")
        for aid in best[0]:
            d = try_action(d, aid)[0]
            a = ACT[aid]
            print(f"      {d.t - a['dur']:>2}틱 {KO[d.loc]:<4} {a['text']}")
        idle = (44 - d.busy) / 44 if d.t <= 44 else 0
        d.finish()
        print(f"      → 45틱 종, 48틱 배, 50틱 점심. 마지막 끼어들기까지 이동·행동 {d.busy}틱, 기다림 {max(0, 44 - d.busy)}틱")
        checks.append(("완벽한 하루가 있다", True))
        checks.append(("완벽한 하루의 행동 조합이 2가지 이상이다(외길이 아니다)", len({frozenset(x[0]) for x in perfect}) >= 2))
        checks.append(("가장 넉넉한 풀이에 2틱(4초) 이상 여유가 있다", best[1] >= 2))
        checks.append(("마지막 끼어들기 전까지 기다림이 40% 이하다", idle <= 0.40))
    else:
        checks.append(("완벽한 하루가 있다", False))

    print("\n[2] 매듭의 필요성: 그 행동을 금지하면 완벽한 하루가 되는가")
    alt = {"chime_give", "chime_dock", "chime_sori"}
    need_ok = True
    for aid in EFFECT:
        s = search(full, GOALS["완벽한 하루"], banned=(aid,))
        tag = "된다" if s else "안 된다"
        if aid in alt:
            tag += " (풍경을 전하는 세 길 중 하나)"
        elif s:
            need_ok = False
        print(f"    {aid:<11} 없이: {tag}")
    s = search(full, GOALS["완벽한 하루"], banned=tuple(alt))
    print(f"    풍경을 전하는 세 길 전부 없이: {'된다' if s else '안 된다'}")
    checks.append(("대체 길이 없는 매듭은 전부 필요하다", need_ok and not s))

    print("\n[3] 아는 것 없이(수첩이 비었을 때) 풀리는 목표")
    r0 = reachable_goals(set())
    print("   ", "없음" if not r0 else ", ".join(r0))
    checks.append(("수첩이 비면 어떤 사건도 풀 수 없다", not r0))
    gated = [a["id"] for a in ACTIONS if not a.get("info") and a.get("know")]
    print(f"    수첩이 있어야 보이는 끼어들기: {len(gated)}/{len(EFFECT)}개 ({', '.join(gated)})")

    print("\n[4] 계획이 필요한가: 풍경을 전하는 길마다 — 가장 넉넉한 여유, '지금 가장 빨리 할 수 있는 것부터' 하는 탐욕 순서의 결과,")
    print("    논리적으로 가능한 순서(물건·조건의 앞뒤만 맞는 순서) 가운데 시간까지 맞는 순서의 비율")
    prec = [("wood_take", "wood_give"), ("wood_give", "loaf"), ("loaf", "trade"), ("trade", "install"),
            ("chime_ask", "chime_give"), ("chime_ask", "chime_sori"), ("chime_ask", "chime_dock"),
            ("tell", "chime_give"), ("wood_give", "slip")]
    greedy_fail = 0
    roomy = 0
    for combo in sorted({frozenset(x[0]) for x in perfect}, key=sorted):
        mine = [x for x in perfect if frozenset(x[0]) == combo]
        via = [x for x in combo if x.startswith("chime_") and x != "chime_ask"][0]
        d = Day(full)
        order = []
        while True:
            cands = []
            for aid in combo - set(order):
                r = try_action(d, aid)
                if r:
                    cands.append((r[1], aid, r[0]))
            if not cands:
                break
            cands.sort(key=lambda c: (c[0], c[1]))
            d = cands[0][2]
            order.append(cands[0][1])
        d.finish()
        g_ok = "완벽한 하루" in d.goals()
        logical = 0
        for perm in itertools.permutations(sorted(combo)):
            pos = {x: i for i, x in enumerate(perm)}
            if all(pos[x] < pos[y] for x, y in prec if x in pos and y in pos):
                logical += 1
        slack = max(x[1] for x in mine)
        greedy_fail += 0 if g_ok else 1
        roomy += 1 if slack >= 2 else 0
        print(f"    {via:<11} 여유 {slack}틱, 탐욕 {'성공' if g_ok else '실패'}({' → '.join(order)}), "
              f"시간까지 맞는 순서 {len(mine)}/{logical} = {len(mine) / logical:.1%}")
    s3 = search(full, GOALS["완벽한 하루"], banned=("chime_give", "chime_sori"))
    print(f"    chime_dock  (배 앞에서 직접 건네기만 허용): {'된다' if s3 else '안 된다 — 종 줄을 갈고 나면 나루터에 못 닿는다'}")
    checks.append(("풍경을 직접 들고 가는 길은 탐욕 순서로 실패한다(계획이 필요하다)", greedy_fail >= 1))
    checks.append(("소리의 동선을 알면 여유 2틱 이상인 길이 열린다(아는 것이 여유가 된다)", roomy >= 1))
    checks.append(("배 앞에서 건네는 가장 직관적인 길은 막혀 있다", not s3))

    print("\n[5] 탐험 방식별 진행 (수첩으로 풀 수 있게 되면 다음 바퀴에 실행)")
    res = {}
    for kind in ("coverage", "stalker", "camper"):
        solved, loops, drought, curve, nn = campaign(kind, 0)
        res[kind] = (solved, loops, drought)
        marks = ", ".join(f"{g.split()[0]} {solved[g]}바퀴" for g in GOALS if g in solved)
        print(f"    {kind:<9} 끝까지 {loops}바퀴({loops * 3}분), 수첩 {nn}/{len(ALL_NOTES)}, 새 것 없는 바퀴 연속 최대 {drought}, "
              f"{marks}")
        print(f"              바퀴별 새 사실+해결: {curve}")
    wl = []
    for seed in range(30):
        solved, loops, drought, curve, nn = campaign("wanderer", seed, max_loops=40, plan=False)
        wl.append(solved)
    p1 = sum(1 for s in wl if "사건1 식은 화덕(점심)" in s) / len(wl)
    pp = sum(1 for s in wl if "완벽한 하루" in s) / len(wl)
    print(f"    wanderer(계획 없이 40바퀴, 30번): 사건1 해결 {p1:.0%}, 완벽한 하루 {pp:.0%}")
    cov = res["coverage"]
    checks.append(("꼼꼼한 탐험가는 6~25바퀴에 끝까지 간다", len(cov[0]) == len(GOALS) and 6 <= cov[1] <= 25))
    checks.append(("꼼꼼한 탐험가에게 새 것 없는 바퀴가 3번 넘게 이어지지 않는다", cov[2] <= 3))
    checks.append(("첫 사건은 5바퀴 안에 풀린다(첫 15분)", cov[0].get("사건1 식은 화덕(점심)", 99) <= 5))
    checks.append(("계획 없이 돌아다녀서는 완벽한 하루가 5% 미만", pp < 0.05))

    print("\n[6] 지켜볼 것의 밀도 (아무것도 안 한 기본 하루)")
    d = Day(set())
    flags_at = []
    for t in range(T):
        flags_at.append(set(d.flags))
        if t < T - 1:
            d._tick(False)
    total = 0
    starts = set()
    dead = []
    for loc in LOCS:
        present, scenes = set(), set()
        for t in range(T):
            for npc in ("bori", "darae", "musoe", "sori", "hanul", "naru"):
                if npc_loc(npc, t, flags_at[t]) == loc:
                    present.add(t)
            for o in OBS:
                here = o["loc"] == loc or (isinstance(o["loc"], tuple) and loc in o["loc"])
                if here and o["t0"] <= t <= o["t1"] and ok(o, flags_at[t]):
                    scenes.add(t)
                    starts.add(o["t0"])
        total += len(scenes)
        if not scenes:
            dead.append(loc)
        print(f"    {KO[loc]:<4} 주민이 있는 틱 {len(present):>2}/90, 수첩에 적히는 장면이 있는 틱 {len(scenes):>2}")
    stamps = sorted(starts | {0, T})
    gaps = [b - a for a, b in zip(stamps, stamps[1:])]
    print(f"    장면이 있는 (장소, 틱): {total}/{len(LOCS) * T} = {total / (len(LOCS) * T):.0%}")
    print(f"    새 장면이 시작되는 틱: {stamps[1:-1]} → 가장 긴 공백 {max(gaps)}틱({max(gaps) * 2}초)")
    checks.append(("마을 어디에도 새 장면이 없는 공백이 24초(12틱)를 넘지 않는다", max(gaps) <= 12))
    checks.append(("모든 장소에 장면이 하나 이상 있다(죽은 장소 없음)", not dead))

    print("\n[7] 민감도: 모든 길이 1틱씩 길어지면(비 오는 날) 풀리는 목표")
    saved = list(EDGES)
    EDGES[:] = [(x, y, w + 1) for x, y, w in saved]
    for k, v in all_pairs().items():
        DIST[k] = v
    still = [g for g, fs in GOALS.items() if search(full, fs)]
    EDGES[:] = saved
    for k, v in all_pairs().items():
        DIST[k] = v
    print("   ", ", ".join(still) if still else "없음 — 마감 시각을 같이 옮기지 않으면 변주 하루는 성립하지 않는다")

    print("\n[8] 판정")
    bad = 0
    for text, good in checks:
        print(f"    {'PASS' if good else 'FAIL'}  {text}")
        bad += 0 if good else 1
    print("\n결론:", "전부 통과" if bad == 0 else f"{bad}개 실패")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
