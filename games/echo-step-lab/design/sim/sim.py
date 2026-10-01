"""메아리 발자국 — 규칙 시뮬레이션(종이 프로토타입).

GAME_DESIGN.md 6절 규칙을 그대로 구현하고, 여러 전략으로 8층 런을 돌려
지배 전략·핵심 메커닉 필요성·난이도 곡선을 숫자로 확인한다.
표준 라이브러리만, 시드 고정, exit 0.

    python3 sim.py          기본(2차 설계 기준 규칙 + 칼 하나 규칙의 전·후 비교). 5분 안에 끝난다
    python3 sim.py --full   위에 더해 메아리 지연(2/3/4) 민감도와 베기 금지 봇까지(오래 걸린다)

2차(v2)에서 바뀐 규칙: 칼 하나(SWORD_CD). Game(..., sword_cd=0)으로 1차 규칙을 그대로 재현할 수 있다.
"""
import random
import sys
import time

N = 7
DIRS = {"U": (0, -1), "R": (1, 0), "D": (0, 1), "L": (-1, 0)}
DORDER = ["U", "R", "D", "L"]
OPP = {"U": "D", "D": "U", "L": "R", "R": "L"}
HP_MAX = 5
SQUEEZE_TURN = 30   # 이 턴 이후 3턴마다 졸개 증원
FLOORS = 8
SWORD_CD = 3        # 칼 하나: 베기를 하면 그 칼을 메아리가 휘두를 때까지(3턴) 다시 벨 수 없다. 0이면 1차 규칙


def add(p, d):
    return (p[0] + DIRS[d][0], p[1] + DIRS[d][1])


def inb(p):
    return 0 <= p[0] < N and 0 <= p[1] < N


class Enemy:
    __slots__ = ("id", "kind", "pos", "hp", "face", "intent", "cool")

    def __init__(self, i, kind, pos):
        self.id, self.kind, self.pos = i, kind, pos
        self.hp = 2 if kind == "S" else 1
        self.face, self.intent, self.cool = "D", None, 0

    def copy(self):
        e = Enemy.__new__(Enemy)
        e.id, e.kind, e.pos, e.hp, e.face, e.intent, e.cool = (
            self.id, self.kind, self.pos, self.hp, self.face, self.intent, self.cool)
        return e


class Game:
    def __init__(self, walls, start, enemies, spawns, delay=3, hp=HP_MAX, sword_cd=SWORD_CD):
        self.sword_cd = sword_cd
        self.walls = frozenset(walls)
        self.player = start
        self.hp = hp
        self.delay = delay
        self.hist = [(start, "start")]     # hist[t] = (턴 t 플레이어 행동 후 위치, 행동)
        self.turn = 0
        self.enemies = [Enemy(i, k, p) for i, (k, p) in enumerate(enemies)]
        self.next_id = len(self.enemies)
        self.spawns = list(spawns)           # (turn, kind, pos)
        self.bombs = []                       # [pos, fuse]
        self.dmg_taken = 0
        self.kills = {"stomp": 0, "swing": 0, "friendly": 0, "crush": 0}
        self.compute_intents()

    def copy(self):
        g = Game.__new__(Game)
        g.walls, g.player, g.hp, g.delay = self.walls, self.player, self.hp, self.delay
        g.sword_cd = self.sword_cd
        g.hist = list(self.hist)
        g.turn = self.turn
        g.enemies = [e.copy() for e in self.enemies]
        g.next_id = self.next_id
        g.spawns = list(self.spawns)
        g.bombs = [list(b) for b in self.bombs]
        g.dmg_taken = self.dmg_taken
        g.kills = dict(self.kills)
        return g

    # ---------- 조회 ----------
    def echo_pos(self):
        k = self.turn - self.delay
        return self.hist[k][0] if k >= 1 else None

    def enemy_at(self, p):
        for e in self.enemies:
            if e.pos == p:
                return e
        return None

    def won(self):
        return not self.enemies and not self.spawns and self.hp > 0

    def lost(self):
        return self.hp <= 0

    def sword_wait(self):
        """칼이 돌아올 때까지 남은 턴 수(0이면 지금 벨 수 있다).

        칼은 하나다. 베기를 하면 그 칼은 메아리가 휘두를 때까지 과거에 묶여 있다.
        = 최근 sword_cd턴(hist[turn-sword_cd+1 .. turn]) 안에 베기가 있으면 벨 수 없다.
        = 화면의 발자국 ③②① 중 하나에 칼 표시가 있으면 벨 수 없다.
        """
        for k in range(self.turn, max(0, self.turn - self.sword_cd), -1):
            if self.hist[k][1][0] == "S":
                return k + self.sword_cd - self.turn
        return 0

    def legal_actions(self):
        acts = ["W"]
        occ = {e.pos for e in self.enemies}
        sword = self.sword_wait() == 0
        for d in DORDER:
            q = add(self.player, d)
            if inb(q) and q not in self.walls and q not in occ:
                acts.append("M" + d)
            if sword and inb(q) and q not in self.walls:
                acts.append("S" + d)
        return acts

    # ---------- 적 의도(플레이어 턴 시작 시 공개) ----------
    def bfs_step(self, src, blocked):
        goal = self.player
        from collections import deque
        prev = {src: None}
        dq = deque([src])
        while dq:
            c = dq.popleft()
            if c == goal:
                break
            for d in DORDER:
                q = add(c, d)
                if not inb(q) or q in prev or q in self.walls:
                    continue
                if q != goal and q in blocked:
                    continue
                prev[q] = (c, d)
                dq.append(q)
        if goal not in prev:
            return None
        c, first = goal, None
        while prev[c] is not None:
            c, first = prev[c]
        return first

    def los_dir(self, src):
        ep = self.echo_pos()
        occ = {e.pos for e in self.enemies}
        for d in DORDER:
            q = add(src, d)
            if q == self.player:
                continue  # 최소 사거리 2: 붙은 대상은 못 쏜다
            while inb(q) and q not in self.walls and q not in occ and q != ep:
                if q == self.player:
                    return d
                q = add(q, d)
        return None

    def compute_intents(self):
        ep = self.echo_pos()
        occ = {e.pos for e in self.enemies}
        if ep:
            occ = occ | {ep}
        for e in self.enemies:
            e.intent = None
            if e.kind == "A":
                d = self.los_dir(e.pos)
                if d:
                    e.intent = ("shoot", d)
                elif abs(e.pos[0] - self.player[0]) + abs(e.pos[1] - self.player[1]) > 1:
                    m = self.bfs_step(e.pos, occ - {e.pos})  # 사선을 잡으러 한 칸 이동
                    e.intent = ("move", m) if m else None
                continue
            dist = abs(e.pos[0] - self.player[0]) + abs(e.pos[1] - self.player[1])
            if e.kind == "B":
                if e.cool == 0 and dist <= 3:
                    e.intent = ("bomb", self.player)
                    continue
            if dist == 1 and e.kind in "WS":
                for d in DORDER:
                    if add(e.pos, d) == self.player:
                        e.intent = ("hit", d)
                        e.face = d
                continue
            d = self.bfs_step(e.pos, occ - {e.pos})
            if d:
                e.intent = ("move", d)

    # ---------- 피해 ----------
    def damage_enemy(self, e, amt, src):
        e.hp -= amt
        if e.hp <= 0 and e in self.enemies:
            self.enemies.remove(e)
            self.kills[src] += 1

    def echo_strike(self, target, d, src):
        """메아리의 일격: target 칸 적에게 1피해 + d방향 밀치기(막히면 +1)."""
        e = self.enemy_at(target)
        if not e:
            return
        if e.kind == "S" and e.face == OPP[d]:
            return  # 방패 정면
        self.damage_enemy(e, 1, src)
        if e.hp > 0:
            q = add(target, d)
            if inb(q) and q not in self.walls and not self.enemy_at(q) and q != self.player:
                e.pos = q
            else:
                self.damage_enemy(e, 1, "crush")

    # ---------- 한 턴 ----------
    def step(self, act):
        self.turn += 1
        # 1. 플레이어
        if act[0] == "M":
            self.player = add(self.player, act[1])
        self.hist.append((self.player, act))
        # 2. 메아리
        k = self.turn - self.delay
        if k >= 1:
            pos, a = self.hist[k]
            if a[0] == "M":
                self.echo_strike(pos, a[1], "stomp")
            elif a[0] == "S":
                self.echo_strike(add(pos, a[1]), a[1], "swing")
        ep = self.echo_pos()
        # 3. 적 (id 순)
        for e in sorted(self.enemies, key=lambda x: x.id):
            if e not in self.enemies or not e.intent:
                continue
            kind, arg = e.intent
            if kind == "move":
                q = add(e.pos, arg)
                if inb(q) and q not in self.walls and q != ep and q != self.player and not self.enemy_at(q):
                    e.pos = q
                    e.face = arg
            elif kind == "hit":
                if add(e.pos, arg) == self.player:
                    self.hurt(1)
            elif kind == "shoot":
                q = add(e.pos, arg)
                while inb(q) and q not in self.walls:
                    if q == ep:
                        break
                    t = self.enemy_at(q)
                    if t:
                        self.damage_enemy(t, 1, "friendly")
                        break
                    if q == self.player:
                        self.hurt(1)
                        break
                    q = add(q, arg)
            elif kind == "bomb":
                self.bombs.append([arg, 2])
                e.cool = 3
        for e in self.enemies:
            if e.kind == "B" and e.cool > 0 and not (e.intent and e.intent[0] == "bomb"):
                e.cool -= 1
        # 4. 폭탄
        for b in list(self.bombs):
            b[1] -= 1
            if b[1] == 0:
                self.bombs.remove(b)
                cells = [b[0]] + [add(b[0], d) for d in DORDER]
                for c in cells:
                    if c == self.player:
                        self.hurt(1)
                    t = self.enemy_at(c)
                    if t:
                        self.damage_enemy(t, 1, "friendly")
        # 5. 증원
        if self.turn >= SQUEEZE_TURN and (self.turn - SQUEEZE_TURN) % 3 == 0 and self.enemies:
            self.spawns.append((self.turn + 1, "W", (3, 0)))
        keep = []
        for (t, kd, p) in self.spawns:
            if t <= self.turn:
                if p != self.player and p != ep and not self.enemy_at(p):
                    self.enemies.append(Enemy(self.next_id, kd, p))
                    self.next_id += 1
                    continue
                keep.append((t + 1, kd, p))
            else:
                keep.append((t, kd, p))
        self.spawns = keep
        self.compute_intents()

    def hurt(self, n):
        self.hp -= n
        self.dmg_taken += n


# ---------------- 콘텐츠: 예시 층 3개 + 생성기 ----------------
EXAMPLES = {
    "E1 첫걸음": dict(walls=[(1, 1), (5, 1), (1, 5), (5, 5)], start=(3, 6),
                     enemies=[("W", (3, 0)), ("W", (0, 2))], spawns=[(6, "W", (6, 0))]),
    "E2 궁수의 복도": dict(walls=[(2, 2), (2, 3), (2, 4), (4, 2), (4, 3), (4, 4)], start=(3, 6),
                       enemies=[("A", (3, 0)), ("W", (0, 0)), ("W", (6, 0))], spawns=[(8, "W", (0, 6))]),
    "E3 방패와 폭탄": dict(walls=[(3, 3), (1, 4), (5, 2)], start=(3, 6),
                       enemies=[("S", (3, 0)), ("B", (0, 1)), ("W", (6, 1))],
                       spawns=[(7, "A", (0, 5)), (10, "W", (6, 4))]),
    # 2차: 방패병을 처음 만나는 층(폭탄병 없이)
    "E4 등 뒤": dict(walls=[(2, 3), (4, 3), (0, 5)], start=(3, 6),
                    enemies=[("S", (3, 1)), ("W", (6, 2))], spawns=[(6, "W", (0, 0))]),
    "E5 협공": dict(walls=[(1, 3), (5, 3), (3, 2)], start=(3, 6),
                   enemies=[("S", (3, 0)), ("A", (0, 1)), ("W", (6, 0))],
                   spawns=[(5, "S", (6, 3)), (9, "W", (0, 6))]),
}

# 층별 예산: (적 수, 증원 수, 허용 종류)
FLOOR_TABLE = {
    1: (2, 1, "W"), 2: (3, 1, "WA"), 3: (3, 2, "WA"), 4: (4, 2, "WAS"),
    5: (4, 3, "WAS"), 6: (5, 3, "WASB"), 7: (5, 4, "WASB"), 8: (6, 4, "WASB"),
}


def connected(walls):
    """벽이 아닌 모든 칸이 하나로 이어져 있어야 한다(갇힌 적 = 풀 수 없는 층)."""
    free = {(x, y) for x in range(N) for y in range(N)} - set(walls)
    seen, st = set(), [next(iter(free))]
    while st:
        c = st.pop()
        if c in seen:
            continue
        seen.add(c)
        st.extend(add(c, d) for d in DORDER if add(c, d) in free)
    return seen == free


def gen_floor(f, rng):
    while True:
        fl = _gen_floor(f, rng)
        if connected(fl["walls"]):
            return fl


def _gen_floor(f, rng):
    ne, ns, kinds = FLOOR_TABLE[f]
    start = (3, 6)
    cells = [(x, y) for x in range(N) for y in range(N) if abs(x - 3) + abs(y - 6) > 2]
    rng.shuffle(cells)
    walls = cells[:rng.randint(3, 6)]
    free = [c for c in cells[len(walls):] if c[1] <= 3]
    enemies = []
    for i in range(ne):
        k = kinds[i % len(kinds)] if i < len(kinds) else rng.choice(kinds)
        enemies.append((k, free.pop()))
    edge = [c for c in cells[len(walls):] if c[0] in (0, N - 1) or c[1] == 0]
    spawns = [(5 + 4 * i, rng.choice(kinds), edge[i % len(edge)]) for i in range(ns)]
    return dict(walls=walls, start=start, enemies=enemies, spawns=spawns)


# ---------------- 전략 ----------------
def danger_cells(g):
    """다음 적 단계에서 피해가 나는 칸(공개 의도 기준)."""
    d = set()
    for e in g.enemies:
        if not e.intent:
            continue
        k, a = e.intent
        if k == "hit":
            d.add(add(e.pos, a))
        elif k == "shoot":
            q = add(e.pos, a)
            while inb(q) and q not in g.walls:
                d.add(q)
                q = add(q, a)
    for b in g.bombs:
        if b[1] == 1:
            d |= {b[0]} | {add(b[0], x) for x in DORDER}
    return d


def s_random(g, rng):
    return rng.choice(g.legal_actions())


def s_flee(g, rng):
    """메아리를 모르는 생존형: 위험 칸 피하고 적에게서 멀어진다(공격 의도 없음)."""
    dz = danger_cells(g)
    best, bv = "W", -1e9
    for a in g.legal_actions():
        if a[0] == "S":
            continue
        p = add(g.player, a[1]) if a[0] == "M" else g.player
        md = min((abs(p[0] - e.pos[0]) + abs(p[1] - e.pos[1]) for e in g.enemies), default=9)
        v = (-100 if p in dz else 0) + md + rng.random() * 0.1
        if v > bv:
            best, bv = a, v
    return best


def s_turret(g, rng):
    """제자리 포탑: 움직이지 않는다. 벨 수 있으면 가장 가까운 적 쪽으로 베고, 아니면 대기."""
    best, bd = "W", 99
    for a in g.legal_actions():
        if a[0] != "S":
            continue
        t = add(g.player, a[1])
        d = min((abs(t[0] - e.pos[0]) + abs(t[1] - e.pos[1]) for e in g.enemies), default=99)
        if d < bd:
            best, bd = a, d
    return best


SPIN = ["MR", "MD", "ML", "MU"]


def s_spin(g, rng):
    """한 가지 반복: 2x2 맴돌기."""
    a = SPIN[g.turn % 4]
    return a if a in g.legal_actions() else "W"


def evaluate(g, base_kills):
    # 이미 확정된 메아리 경로를 끝까지 재생(그 동안 플레이어는 제자리)해 본 결과로 평가
    # (제자리 대기 중 맞는 피해는 무시: 실제로는 움직여 피할 수 있으므로 처치만 센다)
    h = g.copy()
    h.hp = 99
    k0 = sum(h.kills.values())
    for _ in range(h.delay):
        if not h.enemies:
            break
        h.step("W")
    return static_eval(g, base_kills) + 30 * (sum(h.kills.values()) - k0)


def static_eval(g, base_kills):
    if g.lost():
        return -10000
    if g.won():
        return 10000 + g.hp * 100 - g.turn
    kills = sum(g.kills.values()) - base_kills
    md = path_to_enemy(g)
    if g.player in danger_cells(g):
        md += 2
    # 예약된 메아리 타격이 적을 노리는지(앞으로 delay턴의 경로는 이미 확정)
    threat = 0
    epos = {e.pos for e in g.enemies}
    for k in range(g.turn - g.delay + 1, g.turn + 1):
        if k < 1:
            continue
        pos, a = g.hist[k]
        tgt = pos if a[0] == "M" else (add(pos, a[1]) if a[0] == "S" else None)
        if tgt and any(abs(tgt[0] - p[0]) + abs(tgt[1] - p[1]) <= 1 for p in epos):
            threat += 1
    return g.hp * 60 + kills * 45 + threat * 6 - len(g.enemies) * 5 - md * 3


def path_to_enemy(g):
    """벽·적을 피해 가장 가까운 적의 이웃 칸까지 걸음 수."""
    goals = set()
    occ = {e.pos for e in g.enemies}
    for e in g.enemies:
        for d in DORDER:
            goals.add(add(e.pos, d))
    if not goals:
        return 0
    from collections import deque
    seen = {g.player: 0}
    dq = deque([g.player])
    while dq:
        c = dq.popleft()
        if c in goals:
            return seen[c]
        for d in DORDER:
            q = add(c, d)
            if inb(q) and q not in seen and q not in g.walls and q not in occ:
                seen[q] = seen[c] + 1
                dq.append(q)
    return 12


def search(g, depth, base, allow_swing, allow_move=True):
    if depth == 0 or g.won() or g.lost():
        return evaluate(g, base), None
    best, ba = -1e9, "W"
    for a in g.legal_actions():
        if (a[0] == "S" and not allow_swing) or (a[0] == "M" and not allow_move):
            continue
        h = g.copy()
        h.step(a)
        v, _ = search(h, depth - 1, base, allow_swing, allow_move)
        if v > best:
            best, ba = v, a
    return best, ba


def make_planner(depth, allow_swing=True, allow_move=True):
    """allow_move=False 는 "제자리에서 베기만" 하는 계획형(이동 금지)이다."""
    def s(g, rng):
        base = sum(g.kills.values())
        best, ba = -1e9, "W"
        for a in g.legal_actions():
            if (a[0] == "S" and not allow_swing) or (a[0] == "M" and not allow_move):
                continue
            h = g.copy()
            h.step(a)
            # 같은 결과면 진전을 먼저 하는 수를 고르도록 첫 수의 평가를 조금 더한다
            v = search(h, depth - 1, base, allow_swing, allow_move)[0] + 0.3 * evaluate(h, base) + rng.random() * 0.01
            if v > best:
                best, ba = v, a
        return ba
    return s


# ---------------- 실행 ----------------
def play_floor(fl, strat, rng, delay, hp, max_turns=60, sword_cd=SWORD_CD):
    g = Game(fl["walls"], fl["start"], fl["enemies"], fl["spawns"], delay=delay, hp=hp, sword_cd=sword_cd)
    while not g.won() and not g.lost() and g.turn < max_turns:
        g.step(strat(g, rng))
    return g


def run(strat, seed, delay=3, floors=FLOORS, sword_cd=SWORD_CD):
    rng = random.Random(seed)
    frng = random.Random(seed * 7919)
    hp = HP_MAX
    rec = []
    for f in range(1, floors + 1):
        g = play_floor(gen_floor(f, frng), strat, rng, delay, hp, sword_cd=sword_cd)
        rec.append((f, g.won(), g.turn, g.dmg_taken, dict(g.kills)))
        if not g.won():
            return rec, False
        hp = min(HP_MAX, g.hp + 1)
    return rec, True


def kill_share(kills):
    tot = max(1, sum(kills.values()))
    return "밟기 %d%% · 베기 %d%% · 오사 %d%% · 으깨기 %d%%" % tuple(
        round(100 * kills[k] / tot) for k in ("stomp", "swing", "friendly", "crush"))


def summarize(name, strat, seeds, delay=3, sword_cd=SWORD_CD):
    wins, reached, per_floor_dmg, per_floor_turn, kills = 0, [], {}, {}, {"stomp": 0, "swing": 0, "friendly": 0, "crush": 0}
    fail_floor = {}
    cause = [0, 0]  # [턴 제한, 체력 0]
    for s in seeds:
        rec, w = run(strat, s, delay, sword_cd=sword_cd)
        wins += w
        cleared = sum(1 for r in rec if r[1])
        reached.append(cleared)
        if not w:
            fail_floor[rec[-1][0]] = fail_floor.get(rec[-1][0], 0) + 1
            cause[0 if rec[-1][2] >= 60 else 1] += 1
        for f, ok, t, d, k in rec:
            per_floor_dmg.setdefault(f, []).append(d)
            if ok:
                per_floor_turn.setdefault(f, []).append(t)
            for kk in kills:
                kills[kk] += k[kk]
    n = len(seeds)
    print(f"[{name}] runs={n}  8층 클리어 {wins}/{n} ({100*wins/n:.0f}%)  평균 클리어 층 {sum(reached)/n:.2f}  "
          f"패배원인 턴제한 {cause[0]} / 체력0 {cause[1]}  처치 {kill_share(kills)}")
    return dict(wins=wins / n, reached=sum(reached) / n, dmg=per_floor_dmg, turns=per_floor_turn, kills=kills, fail=fail_floor)


FIRST_BUILD_FLOORS = ["E1 첫걸음", "E2 궁수의 복도", None]   # 1차 빌드의 세 층(3층은 아래 F3)
F3 = dict(walls=[(1, 2), (5, 2), (3, 3)], start=(3, 6), enemies=[("A", (0, 0)), ("W", (3, 0)), ("A", (6, 1))],
          spawns=[(5, "W", (0, 3)), (9, "W", (6, 4))])


def first_build_run(strat, sword_cd):
    """1차 빌드의 고정 3개 층을 이어서. [(클리어?, 턴, 피해)], 처치 합계."""
    hp, out, kills = HP_MAX, [], {"stomp": 0, "swing": 0, "friendly": 0, "crush": 0}
    for fl in (EXAMPLES["E1 첫걸음"], EXAMPLES["E2 궁수의 복도"], F3):
        g = play_floor(fl, strat, random.Random(1), 3, hp, sword_cd=sword_cd)
        out.append(("클리어" if g.won() else "실패") + f" {g.turn}턴 피해 {g.dmg_taken}")
        for k in kills:
            kills[k] += g.kills[k]
        if not g.won():
            break
        hp = min(HP_MAX, g.hp + 1)
    return " / ".join(out) + "  처치 " + kill_share(kills)


def main():
    full = "--full" in sys.argv
    t0 = time.time()
    print("== 1. 예시 층 5개: 계획형(3수 앞)으로 클리어되는가 (칼 하나 규칙) ==")
    for name, fl in EXAMPLES.items():
        g = play_floor(fl, make_planner(3), random.Random(1), 3, HP_MAX)
        print(f"  {name}: {'클리어' if g.won() else '실패'} {g.turn}턴, 받은 피해 {g.dmg_taken}, 처치 {g.kills}")

    print("\n== 2. 전략 비교 (8층 런, 칼 하나 규칙) ==")
    seeds = list(range(1, 41))
    res = {}
    res["random"] = summarize("무작위", s_random, seeds)
    res["flee"] = summarize("도망만(메아리 무시)", s_flee, seeds)
    res["spin"] = summarize("2x2 맴돌기 반복", s_spin, seeds)
    res["turret"] = summarize("제자리 포탑(가까운 쪽 베기)", s_turret, seeds)
    res["nm2"] = summarize("제자리 베기만, 2수 앞", make_planner(2, allow_move=False), seeds[:10])
    res["p1"] = summarize("1수 앞(탐욕)", make_planner(1), seeds[:20])
    res["p2"] = summarize("2수 앞", make_planner(2), seeds[:20])
    res["p3"] = summarize("3수 앞(계획형)", make_planner(3), seeds[:4])

    print("\n== 3. 난이도 곡선 (2수 앞 기준, 층별 평균 피해/턴, 탈락 층) ==")
    for f in range(1, FLOORS + 1):
        d = res["p2"]["dmg"].get(f, [])
        t = res["p2"]["turns"].get(f, [])
        if d:
            print(f"  {f}층: 도달 {len(d):2d}  평균 피해 {sum(d)/len(d):.2f}  평균 턴 {sum(t)/max(1,len(t)):.1f}")
    print("  탈락 층 분포(2수 앞):", dict(sorted(res["p2"]["fail"].items())))

    print("\n== 4. 칼 하나 규칙의 전·후 (1차 규칙 sword_cd=0 과 비교) ==")
    print("  1차 빌드 고정 3층")
    for cd in (0, SWORD_CD):
        tag = "1차 규칙" if cd == 0 else "칼 하나 "
        print(f"   [{tag}] 제자리 베기만 2수: {first_build_run(make_planner(2, allow_move=False), cd)}")
        print(f"   [{tag}] 3수 앞          : {first_build_run(make_planner(3), cd)}")
    print("  무작위 8층 런 (1차 규칙)")
    old = {}
    old["nm2"] = summarize("1차 규칙 · 제자리 베기만, 2수 앞", make_planner(2, allow_move=False), seeds[:10], sword_cd=0)
    old["p1"] = summarize("1차 규칙 · 1수 앞", make_planner(1), seeds[:20], sword_cd=0)
    old["p2"] = summarize("1차 규칙 · 2수 앞", make_planner(2), seeds[:10], sword_cd=0)
    p2new = summarize("칼 하나 · 2수 앞(같은 10런)", make_planner(2), seeds[:10])
    print(f"  제자리 베기만: 평균 {old['nm2']['reached']:.2f}층 → {res['nm2']['reached']:.2f}층")
    print(f"  계획 이득(2수-1수 평균 층, 2수는 같은 10런): {old['p2']['reached'] - old['p1']['reached']:+.2f} → {p2new['reached'] - res['p1']['reached']:+.2f}")

    if full:
        print("\n== 5. (--full) 베기 금지 봇, 메아리 지연 민감도 ==")
        summarize("3수 앞, 베기 금지", make_planner(3, allow_swing=False), seeds[:4])
        for d in (2, 3, 4):
            a = summarize(f"2수 앞 d={d}", make_planner(2), seeds[:10], delay=d)
            b = summarize(f"1수 앞 d={d}", make_planner(1), seeds[:10], delay=d)
            print(f"  d={d}: 계획 이득(2수-1수 평균 층) = {a['reached'] - b['reached']:+.2f}")

    print(f"\n소요 {time.time() - t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
