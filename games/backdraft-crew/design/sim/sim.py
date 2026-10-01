"""불길 속으로 — 규칙 시뮬레이션 (종이 프로토타입)

    python sim.py            # 전체 실험, 마지막에 판정. 실패하면 exit 1
    python sim.py --quick    # 판 수를 줄여 빠르게

GAME_DESIGN.md 6절의 규칙을 그대로 구현한다. 표준 라이브러리만 쓰고 난수는 시드 고정.
봇은 건물 전체를 본다(실제 게임의 안개는 없다) — 결과는 "정보가 완전할 때의 상한"이다.
"""
import heapq
import random
import sys

W, H = 11, 13
N = W * H
DIRS = [(0, -1), (1, 0), (0, 1), (-1, 0)]

# ---- 수치 (GAME_DESIGN.md 6.9 표와 같아야 한다) ----
MATS = {  # 재질: (발화 열 T, 타는 틱 F)
    "tile": (0, 0), "wood": (3, 12), "carpet": (2, 8), "paper": (1, 3), "furn": (3, 20),
}
DOOR_HP = 10          # 닫힌 문이 버티는 불-박자
AIR_PER_CELL = 1     # 밀폐된 방의 공기 = 칸 수 × 1 (불붙은 칸 하나가 박자마다 1 소모)
GAS_BURST = 5        # 숨죽은 지 5틱 이상이면 문을 열 때 역류 폭발
BURST_LEN = 3        # 폭발 화염이 문 밖으로 나가는 칸 수
BURST_IN = 2         # 폭발하면 문 안쪽 이 거리까지의 불씨가 한꺼번에 되살아난다
AIR_IN = 2           # 열려 있는 동안 틱마다 들어오는 공기
ROOM_HP = 30         # 방이 버티는 불-틱: 방 안에 불이 하나라도 있는 틱마다 1 줄고 0이면 무너진다
COLLAPSE_WARN = 5    # 이 값 이하로 남으면 붕괴 예고
P_HP = 4
TANK_AIR = 140       # 행동 수
FIRE_EVERY = 2       # 불의 한 박자 = 플레이어 행동 2번
SPRAY_LEN = 3
WET = -2             # 물 맞은 칸의 열
V_HP = 12
SMOKE_EVERY = 5      # 연기 속에서 이 박자마다 구조 대상 체력 -1
CARRY_COST = 2       # 업고 한 칸 = 2행동
RUBBLE_COST = 3      # 잔해 한 칸 = 3행동
MAX_ACTIONS = 600

TIERS = {  # 단계: 불씨 수, 도착 전 연소 틱, 구조 대상, 복도 재질, 처음 열린 문 비율, 깨진 창 비율
    1: dict(origins=2, preburn=(8, 16), victims=2, corridor="wood", open_p=0.15, vent_p=0.05, water=8, apart=True),
    2: dict(origins=2, preburn=(8, 16), victims=3, corridor="wood", open_p=0.20, vent_p=0.10, water=9),
    3: dict(origins=3, preburn=(8, 16), victims=3, corridor="carpet", open_p=0.30, vent_p=0.15, water=10),
    4: dict(origins=4, preburn=(8, 16), victims=4, corridor="carpet", open_p=0.35, vent_p=0.20, water=12),
}
PARTS = [[3, 3, 3], [3, 3, 3], [5, 5], [3, 7], [7, 3]]
EXIT = 12 * W + 5


def xy(i):
    return i % W, i // W


def step(i, d):
    x, y = xy(i)
    x += DIRS[d][0]
    y += DIRS[d][1]
    if 0 <= x < W and 0 <= y < H:
        return y * W + x
    return -1


class Room:
    def __init__(self, rid):
        self.id = rid
        self.cells = []
        self.doors = []
        self.vent = False
        self.full = 0
        self.air = 0
        self.smolder = False
        self.gas = 0
        self.front = -1
        self.hp = ROOM_HP
        self.collapsed = False
        self.burnable = 0
        self.ash = 0


class S:
    """게임 상태 한 벌."""

    def __init__(self):
        self.kind = ["#"] * N
        self.room = [-1] * N
        self.T = [0] * N
        self.fuel = [0] * N
        self.furn = [False] * N
        self.fire = [0] * N      # 0 없음, 1 불, 2 숨죽은 불(불씨)
        self.heat = [0] * N
        self.ash = [False] * N
        self.rubble = [False] * N
        self.door = {}           # 칸 -> [열림, hp, 탔음, 방A, 방B]
        self.rooms = []
        self.pos = EXIT
        self.hp = P_HP
        self.air = TANK_AIR
        self.water = 0
        self.carry = None
        self.victims = []        # [칸, hp, 상태 in|carried|saved|dead]
        self.t = 0
        self.clock = 0
        self.preburn = True
        self.stat = dict(bursts=0, burst_hit=0, closes=0, sprays=0, near=0, ticks=0, collapses=0,
                         ign_exact=0, ign_early=0, ign_total=0, backdraft_opens=0, fire_dmg=0)
        self.first_heat = {}
        self.single = {}

    # ---------- 불 ----------
    def sealed(self, r):
        if r.vent or r.id == 0:
            return False
        return all((not self.door[d][0]) for d in r.doors)

    def smoke_map(self):
        """연기: 열린 문으로 이어진 공간 어디든 불(숨죽은 불 포함)이 있으면 그 공간 전체가 연기다."""
        comp = list(range(len(self.rooms)))

        def find(a):
            while comp[a] != a:
                comp[a] = comp[comp[a]]
                a = comp[a]
            return a
        for d, dr in self.door.items():
            if dr[0]:
                comp[find(dr[3])] = find(dr[4])
        hot = set()
        for r in self.rooms:
            if any(self.fire[q] for q in r.cells):
                hot.add(find(r.id))
        return [find(r.id) in hot for r in self.rooms]

    def smoky(self, r):
        return self.smoke_map()[r.id]

    def door_dist(self, r):
        """방 안 각 칸이 열린 문(깨진 창)에서 몇 칸 떨어져 있는가. 문 바로 안쪽 칸이 1."""
        dist = {}
        q = []
        if r.vent:
            for c in r.cells:
                if any(step(c, d) >= 0 and self.kind[step(c, d)] == "V" for d in range(4)):
                    dist[c] = 1
                    q.append(c)
        for d in r.doors:
            if self.door[d][0]:
                for k in range(4):
                    c = step(d, k)
                    if c >= 0 and self.room[c] == r.id and c not in dist:
                        dist[c] = 1
                        q.append(c)
        while q:
            c = q.pop(0)
            for k in range(4):
                n = step(c, k)
                if n >= 0 and self.room[n] == r.id and n not in dist:
                    dist[n] = dist[c] + 1
                    q.append(n)
        return dist

    def jet_cells(self, r):
        """역류 폭발이 나면 화염이 지나갈 칸: 방의 열린 문마다 문 칸부터 바깥으로 BURST_LEN칸."""
        out_cells = []
        for d in r.doors:
            if not self.door[d][0]:
                continue
            for k in range(4):
                inside = step(d, k)
                if inside >= 0 and self.room[inside] == r.id:
                    out = (k + 2) % 4
                    c, n = d, 0
                    while c >= 0 and n <= BURST_LEN:
                        if self.kind[c] in "#VE" or (c in self.door and not self.door[c][0]):
                            break
                        out_cells.append(c)
                        c = step(c, out)
                        n += 1
                    break
        return out_cells

    def burst(self, r):
        self.stat["bursts"] += 1
        for c in self.jet_cells(r):
            self.hit(c, 2, 4)
            if self.kind[c] == "." and self.fuel[c] > 0 and not self.ash[c] and self.fire[c] == 0                     and not self.rubble[c]:
                self.fire[c] = 1
                self.heat[c] = self.T[c]

    def hit(self, c, pdmg, vdmg):
        if self.preburn:
            return
        if self.pos == c:
            self.hp -= pdmg
            self.stat["burst_hit"] += 1
            if self.carry is not None:
                self.victims[self.carry][1] -= vdmg
        for v in self.victims:
            if v[2] == "in" and v[0] == c:
                v[1] -= vdmg

    def fire_step(self):
        self.t += 1
        fire, heat, kind = self.fire, self.heat, self.kind
        # 1. 방의 공기
        for r in self.rooms:
            if r.collapsed:
                continue
            burning = [c for c in r.cells if fire[c] == 1]
            embers = [c for c in r.cells if fire[c] == 2]
            if self.sealed(r):
                r.front = -1
                if burning:
                    r.air -= len(burning)
                    if r.air <= 0:
                        r.air, r.smolder = 0, True
                        for c in burning:
                            fire[c] = 2
                elif embers:
                    r.smolder = True
                    r.gas += 1
                else:
                    r.smolder, r.gas = False, 0
            else:
                r.air = min(r.full, r.air + AIR_IN)
                if embers:
                    # 공기는 열린 문에서부터 한 틱에 한 칸씩 들어온다
                    r.front += 1
                    if r.front >= 1:
                        if r.gas >= GAS_BURST:
                            self.burst(r)
                            r.front = max(r.front, BURST_IN)
                        r.gas = 0
                        r.smolder = False
                        dist = self.door_dist(r)
                        for c in embers:
                            if dist.get(c, 99) <= r.front and (c != self.pos or self.preburn):
                                fire[c] = 1
                else:
                    r.smolder, r.gas, r.front = False, 0, -1
        # 2. 열 전달
        add = {}
        was_burning = [c for c in range(N) if fire[c] == 1]
        for c in was_burning:
            for d in range(4):
                n = step(c, d)
                if n < 0:
                    continue
                k = kind[n]
                if k == "D":
                    dr = self.door[n]
                    if dr[0]:
                        n2 = step(n, d)
                        if n2 >= 0 and kind[n2] == ".":
                            add[n2] = add.get(n2, 0) + 1
                    else:
                        dr[1] -= 1
                        if dr[1] <= 0:
                            dr[0], dr[2] = True, True
                elif k == ".":
                    add[n] = add.get(n, 0) + 1
        for c in range(N):
            if kind[c] != "." or fire[c]:
                continue
            a = add.get(c, 0)
            if a:
                if heat[c] <= 0 and c not in self.first_heat:
                    self.first_heat[c] = self.t
                    self.single[c] = True
                if a > 1:
                    self.single[c] = False
                heat[c] += a
            else:
                self.first_heat.pop(c, None)
                if heat[c] > 0:
                    heat[c] -= 1
                elif heat[c] < 0:
                    heat[c] += 1
        # 3. 발화
        for c in add:
            if fire[c] or self.ash[c] or self.fuel[c] <= 0 or self.rubble[c]:
                continue
            if heat[c] >= self.T[c]:
                r = self.rooms[self.room[c]]
                if r.smolder or (c == self.pos and not self.preburn):
                    heat[c] = self.T[c]
                    continue
                fire[c] = 1
                if not self.preburn and c in self.first_heat:
                    # 화면 규칙 "불 옆 칸은 재질 숫자만큼 틱 뒤에 붙는다"가 맞았는가
                    self.stat["ign_total"] += 1
                    dt = self.t - self.first_heat[c] + 1
                    if dt == self.T[c]:
                        self.stat["ign_exact"] += 1
                    elif dt < self.T[c]:
                        self.stat["ign_early"] += 1
                self.first_heat.pop(c, None)
        # 4. 연소
        for c in was_burning:
            if fire[c] != 1:
                continue
            self.fuel[c] -= 1
            if self.fuel[c] <= 0:
                fire[c], heat[c] = 0, 0
                self.ash[c] = True
                self.furn[c] = False
                self.rooms[self.room[c]].ash += 1
        # 5. 붕괴 (복도는 무너지지 않는다)
        for r in self.rooms[1:]:
            if r.collapsed:
                continue
            if any(fire[c] == 1 for c in r.cells):
                r.hp -= 1
            if r.hp <= 0:
                r.collapsed = True
                self.stat["collapses"] += 1
                for c in r.cells:
                    self.rubble[c] = True
                    fire[c], heat[c], self.fuel[c] = 0, 0, 0
                    self.furn[c] = False
                if not self.preburn:
                    if self.room[self.pos] == r.id:
                        self.hp -= 2
                        if self.carry is not None:
                            self.victims[self.carry][2] = "dead"
                            self.carry = None
                    for v in self.victims:
                        if v[2] == "in" and self.room[v[0]] == r.id:
                            v[2] = "dead"
        if self.preburn:
            return
        # 6. 구조 대상 피해
        smoke = self.smoke_map() if self.t % SMOKE_EVERY == 0 else None
        for v in self.victims:
            if v[2] != "in":
                continue
            c = v[0]
            if fire[c] == 1:
                v[1] -= 2
            elif any(step(c, d) >= 0 and fire[step(c, d)] == 1 for d in range(4)):
                v[1] -= 1
            elif smoke is not None and smoke[self.room[c]]:
                v[1] -= 1
            if v[1] <= 0:
                v[2] = "dead"

    def player_step(self):
        """행동 하나마다: 불 위에 서 있으면 다치고, 공기가 줄고, 출구에서는 내려놓고 공기를 채운다."""
        self.clock += 1
        fire = self.fire
        p = self.pos
        if fire[p] == 1:
            self.hp -= 1
            self.stat["fire_dmg"] += 1
            if self.carry is not None:
                self.victims[self.carry][1] -= 2
        self.air -= 1
        if self.air < 0 and (-self.air) % 6 == 0:
            self.hp -= 1
        if p == EXIT:
            self.air = TANK_AIR
            if self.carry is not None:
                self.victims[self.carry][2] = "saved"
                self.carry = None
        if self.carry is not None and self.victims[self.carry][1] <= 0:
            self.victims[self.carry][2] = "dead"
            self.carry = None
        self.stat["ticks"] += 1
        px, py = xy(p)
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                if abs(dx) + abs(dy) <= 2 and 0 <= px + dx < W and 0 <= py + dy < H:
                    if fire[(py + dy) * W + px + dx] == 1:
                        self.stat["near"] += 1
                        return

    # ---------- 플레이어 행동 ----------
    def passable(self, c):
        return c >= 0 and self.kind[c] in ".DE" and not self.furn[c]

    def act(self, a):
        """행동 하나를 하고 걸린 틱만큼 불을 진행한다."""
        cost = 1
        k = a[0]
        if k == "m":
            n = step(self.pos, a[1])
            if self.passable(n):
                if n in self.door and not self.door[n][0]:
                    self.door[n][0] = True
                    r = [self.rooms[q] for q in self.door[n][3:5] if q >= 0]
                    if any(x.smolder and x.gas >= GAS_BURST for x in r):
                        self.stat["backdraft_opens"] += 1
                else:
                    self.pos = n
                    if self.carry is not None:
                        cost = CARRY_COST
                    if self.rubble[n]:
                        cost += RUBBLE_COST - 1
        elif k == "s":
            if self.water > 0 and self.carry is None:
                self.water -= 1
                self.stat["sprays"] += 1
                c = self.pos
                for _ in range(SPRAY_LEN):
                    c = step(c, a[1])
                    if c < 0 or self.kind[c] in "#VE" or (c in self.door and not self.door[c][0]):
                        break
                    if self.kind[c] == ".":
                        self.fire[c] = 0
                        self.heat[c] = WET
                        if self.furn[c]:
                            break
        elif k == "c":
            n = step(self.pos, a[1])
            if n in self.door and self.door[n][0] and not self.door[n][2]:
                if not any(v[2] == "in" and v[0] == n for v in self.victims):
                    self.door[n][0] = False
                    self.stat["closes"] += 1
        elif k == "p":
            if self.carry is None:
                for i, v in enumerate(self.victims):
                    if v[2] == "in" and v[0] == self.pos:
                        v[2] = "carried"
                        self.carry = i
                        break
        elif k == "d":
            if self.carry is not None and self.kind[self.pos] == ".":
                v = self.victims[self.carry]
                v[0], v[2] = self.pos, "in"
                self.carry = None
        for _ in range(cost):
            self.player_step()
            if self.clock % FIRE_EVERY == 0:
                self.fire_step()
            if self.hp <= 0:
                break

    # ---------- 길 찾기 (봇용) ----------
    def path(self, goal, fire_pen=12):
        src = self.pos
        base = CARRY_COST if self.carry is not None else 1
        dist = {src: 0}
        prev = {}
        pq = [(0, src)]
        while pq:
            dcur, c = heapq.heappop(pq)
            if c == goal:
                break
            if dcur > dist.get(c, 1e9):
                continue
            for d in range(4):
                n = step(c, d)
                if not self.passable(n):
                    continue
                w = base
                if self.rubble[n]:
                    w += RUBBLE_COST - 1
                if n in self.door and not self.door[n][0]:
                    w += 1
                    for q in self.door[n][3:5]:
                        if q >= 0 and self.rooms[q].smolder:
                            w += 3
                if self.fire[n] == 1:
                    w += fire_pen
                nd = dcur + w
                if nd < dist.get(n, 1e9):
                    dist[n] = nd
                    prev[n] = c
                    heapq.heappush(pq, (nd, n))
        if goal not in dist:
            return None, 1e9
        out = [goal]
        while out[-1] != src:
            out.append(prev[out[-1]])
        out.reverse()
        return out, dist[goal]


def mine_of(s, p):
    return s.room[p]


def dir_of(a, b):
    ax, ay = xy(a)
    bx, by = xy(b)
    return DIRS.index((bx - ax, by - ay))


# ---------- 건물 생성 ----------
def gen(seed, tier):
    cfg = TIERS[tier]
    sub = 0
    while True:
        s = _gen(random.Random(seed * 1000 + tier * 37 + sub), cfg)
        sub += 1
        if s is not None:
            return s


def _gen(rng, cfg):
    s = S()
    cor = Room(0)
    s.rooms.append(cor)
    for y in range(1, 12):
        c = y * W + 5
        s.kind[c] = "."
        s.room[c] = 0
        cor.cells.append(c)
        s.T[c], s.fuel[c] = MATS[cfg["corridor"]]
    s.kind[EXIT] = "E"
    for side in (0, 1):
        xs = (1, 2, 3) if side == 0 else (7, 8, 9)
        wallx = 4 if side == 0 else 6
        outerx = 0 if side == 0 else 10
        y = 1
        prev_room = None
        for h in rng.choice(PARTS):
            r = Room(len(s.rooms))
            s.rooms.append(r)
            mat = rng.choices(["wood", "carpet", "tile", "storage"], [45, 25, 10, 20])[0]
            for yy in range(y, y + h):
                for x in xs:
                    c = yy * W + x
                    s.kind[c] = "."
                    s.room[c] = r.id
                    r.cells.append(c)
                    m = mat
                    if mat == "storage":
                        m = "paper" if rng.random() < 0.3 else "wood"
                    s.T[c], s.fuel[c] = MATS[m]
            dc = rng.randrange(y, y + h) * W + wallx
            s.kind[dc] = "D"
            s.door[dc] = [rng.random() < cfg["open_p"], DOOR_HP, False, 0, r.id]
            r.doors.append(dc)
            if prev_room is not None and rng.random() < 0.7:
                dc = (y - 1) * W + rng.choice(xs)
                s.kind[dc] = "D"
                s.door[dc] = [rng.random() < cfg["open_p"], DOOR_HP, False, prev_room.id, r.id]
                r.doors.append(dc)
                prev_room.doors.append(dc)
            if rng.random() < cfg["vent_p"]:
                s.kind[rng.randrange(y, y + h) * W + outerx] = "V"
                r.vent = True
            prev_room = r
            y += h + 1
    # 가구: 바깥 열에만(방 안 연결을 끊지 않는다), 문 옆 칸 제외
    for r in s.rooms[1:]:
        if len(r.cells) < 9 or s.fuel[r.cells[0]] == 0:
            continue
        for _ in range(rng.randrange(0, 3)):
            c = rng.choice(r.cells)
            if c % W not in (1, 9) or s.furn[c]:
                continue
            if any(step(c, d) in s.door for d in range(4)):
                continue
            s.furn[c] = True
            s.T[c], s.fuel[c] = MATS["furn"]
    for r in s.rooms:
        r.burnable = sum(1 for c in r.cells if s.fuel[c] > 0)
        r.full = r.air = len(r.cells) * AIR_PER_CELL
    free = [c for r in s.rooms[1:] for c in r.cells if not s.furn[c]]
    rng.shuffle(free)
    used_rooms = set()
    for c in free:
        if len(s.victims) >= cfg["victims"]:
            break
        if s.room[c] in used_rooms:
            continue
        used_rooms.add(s.room[c])
        s.victims.append([c, V_HP, "in"])
    if len(s.victims) < cfg["victims"]:
        return None
    vcells = {v[0] for v in s.victims}
    cand = [c for c in free if s.fuel[c] > 0 and c not in vcells
            and all(abs(c % W - v % W) + abs(c // W - v // W) >= 2 for v in vcells)]
    if cfg.get("apart"):
        vrooms = {s.room[v] for v in vcells}
        cand = [c for c in cand if s.room[c] not in vrooms]
    if len(cand) < cfg["origins"]:
        return None
    for c in rng.sample(cand, cfg["origins"]):
        s.fire[c] = 1
    for _ in range(rng.randint(*cfg["preburn"])):
        s.fire_step()
    for v in s.victims:
        c = v[0]
        if s.fire[c] == 1 or s.rubble[c] or s.rooms[s.room[c]].hp < 20:
            return None
    if not any(s.fire):
        return None
    s.preburn = False
    s.water = cfg["water"]
    s.t = 0
    s.stat = {k: 0 for k in s.stat}
    s.first_heat, s.single = {}, {}
    return s


# ---------- 봇 ----------
class Bot:
    def __init__(self, name, close=False, respect=False, soak=False, order="near", spray=True,
                 seal_first=False, shut_in=False, guard=False, rnd=None):
        self.name, self.close, self.respect, self.soak = name, close, respect, soak
        self.order, self.spray, self.seal_first, self.rnd = order, spray, seal_first, rnd
        self.shut_in, self.guard = shut_in, guard
        self.queue = []
        self.once = set()
        self.done = False

    def other_room(self, s, d, mine):
        a, b = s.door[d][3], s.door[d][4]
        return b if a == mine else a

    def choose(self, s):
        if self.queue:
            return self.queue.pop(0)
        if self.rnd is not None:
            if s.pos == EXIT and s.clock > 150:
                self.done = True
                return ("w",)
            return self.rnd.choice([("m", 0), ("m", 1), ("m", 2), ("m", 3), ("s", self.rnd.randrange(4)),
                                    ("c", self.rnd.randrange(4)), ("p",), ("w",)])
        p = s.pos
        living = [v for v in s.victims if v[2] == "in"]
        _, dexit = s.path(EXIT)
        goal = None
        if s.carry is not None or s.hp <= 1 or not living or s.air <= dexit + 6:
            goal = EXIT
        if goal == EXIT and p == EXIT:
            if s.carry is None and (s.hp <= 1 or not living):
                self.done = True
            return ("w",)
        nxt_hint = None
        if goal is None and self.seal_first:
            # 지배 전략 후보: 사람이 없는 불난 방의 문을 전부 닫고 나서 구조
            best = None
            for r in s.rooms[1:]:
                if r.collapsed:
                    continue
                burning = any(s.fire[c] == 1 for c in r.cells)
                anyfire = any(s.fire[c] for c in r.cells)
                has_v0 = any(s.room[v[0]] == r.id for v in living)
                if not (burning and not has_v0):
                    continue
                has_v = any(s.room[v[0]] == r.id for v in living)
                for d in r.doors:
                    if s.door[d][0] and not s.door[d][2] and d not in self.once:
                        for k in range(4):
                            a = step(d, k)
                            if a >= 0 and s.kind[a] == "." and s.room[a] != r.id and not s.furn[a]:
                                pa, cst = s.path(a)
                                if pa and (best is None or cst < best[0]):
                                    best = (cst, a)
            if best:
                goal = best[1]
                if goal == p:
                    for k in range(4):
                        n = step(p, k)
                        if n in s.door and s.door[n][0] and not s.door[n][2] and mine_of(s, p) >= 0:
                            far = self.other_room(s, n, s.room[p])
                            fr = s.rooms[far]
                            b1 = any(s.fire[c] == 1 for c in fr.cells)
                            a1 = any(s.fire[c] for c in fr.cells)
                            hv = any(s.room[v[0]] == far for v in living)
                            if far > 0 and b1 and not hv:
                                self.once.add(n)
                                return ("c", k)
                    goal = None
        if goal is None:
            best = None
            for v in living:
                pa, cst = s.path(v[0])
                if pa is None:
                    continue
                key = cst
                if self.order == "danger":
                    threat = s.smoky(s.rooms[s.room[v[0]]])
                    key = (0 if threat else 1, v[1] * 3 - cst if threat else cst)
                if best is None or key < best[0]:
                    best = (key, v[0])
            if best is None:
                goal = EXIT
            else:
                goal = best[1]
                if goal == p:
                    return ("p",)
        pa, _ = s.path(goal)
        if pa is None or len(pa) < 2:
            return ("w",)
        nxt = pa[1]
        d = dir_of(p, nxt)
        mine = s.room[p]
        # 들어가서 닫기: 불씨가 남은 방에 들어왔으면 등 뒤의 문을 닫아 공기를 끊는다
        if self.shut_in and mine > 0 and s.carry is None and len(pa) > 2:
            mr = s.rooms[mine]
            if any(s.fire[c] == 2 for c in mr.cells) and s.room[goal] == mine:
                for k in range(4):
                    n = step(p, k)
                    if n in s.door and s.door[n][0] and not s.door[n][2] and n != nxt:
                        return ("c", k)
        # 문 닫기: 내 옆의 열린 문 너머가 불타는 방이고, 거기 살릴 사람이 없고, 그 문으로 갈 게 아니면 닫는다
        if self.close and mine >= 0:
            for k in range(4):
                n = step(p, k)
                if n in s.door and s.door[n][0] and not s.door[n][2] and n != nxt:
                    far = self.other_room(s, n, mine)
                    if far <= 0:
                        continue
                    fr = s.rooms[far]
                    if fr.collapsed:
                        continue
                    has_v = any(s.room[v[0]] == far for v in living)
                    burning = any(s.fire[c] == 1 for c in fr.cells)
                    anyfire = any(s.fire[c] for c in fr.cells)
                    # (가) 사람 없는 불난 방은 가둔다 (나) 불 없는 방의 기다리는 사람은 문을 닫아 연기를 막아 준다
                    if (burning and not has_v) or (has_v and not anyfire and s.room[goal] != far):
                        return ("c", k)
        # 물 뿌리기(soak): 닿는 불은 전부
        if self.soak and s.carry is None and s.water > 0:
            for k in range(4):
                c = p
                for _ in range(SPRAY_LEN):
                    c = step(c, k)
                    if c < 0 or s.kind[c] in "#VE" or (c in s.door and not s.door[c][0]):
                        break
                    if s.fire[c] == 1:
                        return ("s", k)
        # 필요한 불만 끄기: 앞으로 밟을 세 칸의 불, 구조 대상에게 붙은 불
        if self.guard and s.carry is None and s.water > 0:
            need = set(pa[1:4])
            for v in living:
                need.add(v[0])
                for k in range(4):
                    need.add(step(v[0], k))
            for k in range(4):
                c = p
                for _ in range(SPRAY_LEN):
                    c = step(c, k)
                    if c < 0 or s.kind[c] in "#VE" or (c in s.door and not s.door[c][0]):
                        break
                    if s.fire[c] == 1 and c in need:
                        return ("s", k)
        if self.respect:
            danger = set()
            for r in s.rooms[1:]:
                if r.smolder and r.gas >= GAS_BURST and not r.collapsed and not s.sealed(r):
                    danger.update(s.jet_cells(r))
            if danger:
                if p in danger:
                    for k in range(4):
                        n = step(p, k)
                        if s.passable(n) and n not in danger and s.fire[n] != 1                                 and not (n in s.door and not s.door[n][0]):
                            return ("m", k)
                elif nxt in danger:
                    return ("w",)
        if nxt in s.door and not s.door[nxt][0]:
            if self.respect and mine >= 0:
                fr = s.rooms[self.other_room(s, nxt, mine)]
                if fr.smolder and fr.gas < GAS_BURST and self.spray and s.water > 0 and s.carry is None:
                    # 갓 숨죽은 방: 되살아나기 전의 한 틱에 문 너머 불씨 한 줄을 끈다
                    c, hit = nxt, False
                    for _ in range(SPRAY_LEN - 1):
                        c = step(c, d)
                        if c < 0 or s.kind[c] != ".":
                            break
                        hit = hit or s.fire[c] == 2
                    if hit:
                        self.queue = [("s", d)]
            return ("m", d)
        if s.fire[nxt] == 1 and self.spray and s.water > 0:
            if s.carry is None:
                return ("s", d)
            if s.kind[p] == ".":
                self.queue = [("s", d), ("p",)]
                return ("d",)
        return ("m", d)


BOTS = {
    "random": lambda seed: Bot("random", rnd=random.Random(seed)),
    "rusher(문 무시)": lambda seed: Bot("rusher"),
    "soaker(물만)": lambda seed: Bot("soaker", soak=True),
    "doorman(문+징후)": lambda seed: Bot("doorman", close=True, respect=True, order="danger", guard=True),
    "doorman-징후무시": lambda seed: Bot("doorman_nr", close=True, respect=False, order="danger", guard=True),
    "doorman-물 안 씀": lambda seed: Bot("doorman_nw", close=True, respect=True, order="danger", spray=False),
    "doorman-문 안 닫음": lambda seed: Bot("doorman_nc", close=False, respect=True, order="danger", guard=True),
    "veteran(문+징후+물 넉넉히)": lambda seed: Bot("veteran", close=True, respect=True, order="danger", guard=True, soak=True),
    "sealer(먼저 다 닫기)": lambda seed: Bot("sealer", close=True, respect=True, order="danger", seal_first=True, guard=True),
}


def play(seed, tier, botname):
    s = gen(seed, tier)
    bot = BOTS[botname](seed)
    while s.clock < MAX_ACTIONS and s.hp > 0 and not bot.done:
        s.act(bot.choose(s))
    saved = sum(1 for v in s.victims if v[2] == "saved")
    return dict(saved=saved, total=len(s.victims), dead=s.hp <= 0, hp=max(s.hp, 0), **s.stat)


def run(n):
    res = {}
    for tier in TIERS:
        for b in BOTS:
            rows = [play(seed, tier, b) for seed in range(n)]
            res[(tier, b)] = rows
    return res


def avg(rows, k):
    return sum(r[k] for r in rows) / len(rows)


def main():
    quick = "--quick" in sys.argv
    n = 30 if quick else 100
    res = run(n)
    print(f"불길 속으로 규칙 시뮬레이션 — 단계마다 건물 {n}채, 시드 0..{n - 1}\n")
    print("[1] 전략별 결과 (유효 = 소방관이 살아 나온 판만 친 구조율, 구조율 = 구한 사람 / 전체, 전원 = 전원 구조한 판, 순직 = 소방관 체력 0)")
    for tier in TIERS:
        print(f"\n  단계 {tier}  {TIERS[tier]}")
        print("    전략                   유효   구조율  전원   순직   행동    물   문닫기  역류피격  불피해")
        for b in BOTS:
            rows = res[(tier, b)]
            rate = sum(r["saved"] for r in rows) / sum(r["total"] for r in rows)
            eff = sum(0 if r["dead"] else r["saved"] for r in rows) / sum(r["total"] for r in rows)
            allr = sum(1 for r in rows if r["saved"] == r["total"]) / len(rows)
            dead = sum(1 for r in rows if r["dead"]) / len(rows)
            print(f"    {b:<24} {eff:6.1%} {rate:6.1%} {allr:6.1%} {dead:6.1%} {avg(rows, 'ticks'):5.0f} "
                  f"{avg(rows, 'sprays'):5.1f} {avg(rows, 'closes'):6.1f} {avg(rows, 'burst_hit'):8.2f} "
                  f"{avg(rows, 'fire_dmg'):6.2f}")

    def rate(tier, b):
        # 유효 구조율: 소방관이 쓰러진 판은 0명으로 친다(임무 실패)
        rows = res[(tier, b)]
        return sum(0 if r["dead"] else r["saved"] for r in rows) / sum(r["total"] for r in rows)

    def dead(tier, b):
        rows = res[(tier, b)]
        return sum(1 for r in rows if r["dead"]) / len(rows)

    D, R, K = "doorman(문+징후)", "rusher(문 무시)", "soaker(물만)"
    print("\n[1-2] 5번 연속 출동해 살아 돌아올 확률 (단계 3 순직률 기준)")
    for b in (R, K, D, "veteran(문+징후+물 넉넉히)"):
        print(f"    {b:<24} {(1 - dead(3, b)) ** 5:6.1%}")
    print("\n[2] 풀 수 있는가: 어느 봇이든 전원 구조에 성공한 건물의 비율")
    solv = {}
    for tier in TIERS:
        ok = 0
        for i in range(n):
            if any(res[(tier, b)][i]["saved"] == res[(tier, b)][i]["total"] and not res[(tier, b)][i]["dead"]
                   for b in BOTS):
                ok += 1
        solv[tier] = ok / n
        print(f"    단계 {tier}: {ok / n:.1%}")

    print("\n[3] 화면만 보고 불을 예측할 수 있는가 (next_test)")
    rows = [r for tier in TIERS for r in res[(tier, 'doorman(문+징후)')]]
    tot = sum(r["ign_total"] for r in rows)
    ex = sum(r["ign_exact"] for r in rows)
    ea = sum(r["ign_early"] for r in rows)
    print(f"    발화 {tot}건 중 '불 옆 칸은 재질 숫자(T)틱 뒤에 붙는다'대로: {ex / tot:.1%}, "
          f"그보다 빨리(불이 두 면 이상에서 옴): {ea / tot:.1%}, 늦게(열이 끊겼다 다시 옴): {(tot - ex - ea) / tot:.1%}")
    print("    (열 눈금을 칸에 그리면 세 경우 모두 '눈금이 차면 붙는다' 한 규칙으로 읽힌다 — 규칙은 결정론)")
    bo = sum(r["backdraft_opens"] for r in rows)
    print(f"    역류 징후가 있는 문을 연 횟수: 판당 {bo / len(rows):.2f}회")

    print("\n[4] 걸어 다니는 긴장: 불에서 2칸 안에 있던 행동의 비율 / 한 판 길이")
    for tier in TIERS:
        rows = res[(tier, 'doorman(문+징후)')]
        near = sum(r["near"] for r in rows) / max(1, sum(r["ticks"] for r in rows))
        print(f"    단계 {tier}: 불 가까이 {near:.1%}, 평균 {avg(rows, 'ticks'):.0f}행동, "
              f"붕괴 {avg(rows, 'collapses'):.2f}회, 역류 폭발 {avg(rows, 'bursts'):.2f}회")

    V = "veteran(문+징후+물 넉넉히)"
    NC, NR, NW = "doorman-문 안 닫음", "doorman-징후무시", "doorman-물 안 씀"
    T234 = (2, 3, 4)
    checks = [
        ("무작위는 통하지 않는다 (단계 1 유효 구조율 < 10%)", rate(1, "random") < 0.10),
        ("문 닫기가 값이 있다 (단계 2~4 각각: 문 닫는 봇 - 안 닫는 봇 >= +4%p)",
         all(rate(t, D) - rate(t, NC) >= 0.04 for t in T234)),
        ("역류 징후 읽기가 값이 있다 (단계 2~4 각각: 유효 구조율이 높고 순직률이 낮다)",
         all(rate(t, D) > rate(t, NR) and dead(t, D) < dead(t, NR) for t in T234)),
        ("물이 필요하다 (단계 2~4 각각: 물 쓰는 봇 - 안 쓰는 봇 >= +20%p)",
         all(rate(t, D) - rate(t, NW) >= 0.20 for t in T234)),
        ("문을 무시하고 달리는 전략은 순직이 2배 이상 잦다 (단계 2~4)",
         all(dead(t, R) >= 2 * dead(t, D) and dead(t, R) >= 0.15 for t in T234)),
        ("물만 쏟는 전략이 두 축 모두에서 최선인 단계가 없다 (단계 2~4 각각: 문 쓰는 봇 중 하나가 순직률이 "
         "절반 이하이면서 유효 구조율이 5%p 넘게 뒤지지 않는다)",
         all(any(dead(t, x) <= dead(t, K) / 2 and rate(t, x) >= rate(t, K) - 0.05 for x in (D, V)) for t in T234)),
        ("난이도가 오른다 (veteran 유효 구조율 단계 1 > 2 > 3 > 4)",
         rate(1, V) > rate(2, V) > rate(3, V) > rate(4, V)),
        ("첫 단계는 넉넉하다 (veteran 단계 1 >= 85%)", rate(1, V) >= 0.85),
        ("마지막 단계도 불가능하지 않다 (veteran 단계 4 >= 40%)", rate(4, V) >= 0.40),
        ("먼저 다 닫기가 지배 전략이 아니다 (단계 2~4 평균: sealer <= doorman + 3%p)",
         sum(rate(t, "sealer(먼저 다 닫기)") for t in T234) / 3 <= sum(rate(t, D) for t in T234) / 3 + 0.03),
        ("풀 수 있다 (전원 구조 가능한 건물: 단계 1 >= 95%, 단계 2~3 >= 70%)",
         solv[1] >= 0.95 and solv[2] >= 0.70 and solv[3] >= 0.70),
    ]
    print("\n[5] 판정")
    bad = 0
    for text, ok in checks:
        print(f"    {'PASS' if ok else 'FAIL'}  {text}")
        bad += 0 if ok else 1
    print("\n결론:", "전부 통과" if bad == 0 else f"{bad}개 실패")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
