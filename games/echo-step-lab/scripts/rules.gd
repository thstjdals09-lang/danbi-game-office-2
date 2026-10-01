extends RefCounted
## 메아리 발자국 — 한 층의 규칙. 노드·그리기·시간 없음.
## 기준 구현: design/sim/sim.py 의 Game 클래스(졸개 W, 궁수 A만). design/FIRST_BUILD.md "규칙 확정"과 같은 순서.

const N := 7
const DELAY := 3
const HP_MAX := 5
const SQUEEZE_TURN := 30
const SQUEEZE_EVERY := 3
const SQUEEZE_CELL := Vector2i(3, 0)
const TURN_LIMIT := 60

# 방향 순서(동점 처리): 위 → 오른쪽 → 아래 → 왼쪽  (sim.py DORDER)
const DORDER: Array[String] = ["U", "R", "D", "L"]
const DIRS := {"U": Vector2i(0, -1), "R": Vector2i(1, 0), "D": Vector2i(0, 1), "L": Vector2i(-1, 0)}

var walls: Dictionary = {}        # Vector2i -> true
var player := Vector2i.ZERO
var hp := HP_MAX
var turn := 0
var hist: Array = []              # hist[k] = {"pos": Vector2i, "act": String}  (sim.py hist)
var enemies: Array = []           # id 오름차순. {"id","kind","pos","intent","dir"}
var next_id := 0
var spawns: Array = []            # [turn, kind, pos]
var kills: Dictionary             # 런 단위 누적. main 이 넘겨 준 것을 그대로 쓴다
var outcome := ""                 # "" 진행 중 | "clear" | "dead" | "timeout"


## sim.py Game.__init__ 대응
func setup(floor_data: Dictionary, start_hp: int, run_kills: Dictionary) -> void:
	walls.clear()
	for w in floor_data["walls"]:
		walls[w] = true
	player = floor_data["start"]
	hp = start_hp
	turn = 0
	hist = [{"pos": player, "act": "start"}]
	enemies = []
	next_id = 0
	for e in floor_data["enemies"]:
		enemies.append({"id": next_id, "kind": e[0], "pos": e[1], "intent": "none", "dir": Vector2i.ZERO})
		next_id += 1
	spawns = []
	for s in floor_data.get("spawns", []):
		spawns.append([s[0], s[1], s[2]])
	kills = run_kills
	outcome = ""
	compute_intents()


static func inb(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < N and p.y >= 0 and p.y < N


static func is_slash(act: String) -> bool:
	return act.length() == 2 and act[0] == "S"


static func is_move(act: String) -> bool:
	return act.length() == 1 and DIRS.has(act)


static func act_dir(act: String) -> Vector2i:
	if is_move(act):
		return DIRS[act]
	if is_slash(act):
		return DIRS[act[1]]
	return Vector2i.ZERO


## sim.py echo_pos 대응: 지금(끝난 턴 기준) 메아리가 서 있는가
func has_echo() -> bool:
	return turn - DELAY >= 1


func echo_pos() -> Vector2i:
	return hist[turn - DELAY]["pos"] if has_echo() else Vector2i(-1, -1)


func enemy_at(p: Vector2i):
	for e in enemies:
		if e["pos"] == p:
			return e
	return null


## sim.py legal_actions 대응
func can_act(act: String) -> bool:
	if outcome != "":
		return false
	if act == "W":
		return true
	if is_move(act):
		var q: Vector2i = player + DIRS[act]
		return inb(q) and not walls.has(q) and enemy_at(q) == null
	if is_slash(act) and DIRS.has(act[1]):
		var t: Vector2i = player + DIRS[act[1]]
		return inb(t) and not walls.has(t)
	return false


## 이 행동이 3턴 뒤 메아리의 타격이 될 칸(미리보기용). 대기면 (-1,-1)
func strike_cell_of(act: String) -> Vector2i:
	if is_move(act):
		return player + DIRS[act]
	if is_slash(act):
		return player + DIRS[act[1]]
	return Vector2i(-1, -1)


## 앞으로 메아리가 할 일, 빠른 순. [{"pos","act","in"}]
func footprints() -> Array:
	var out: Array = []
	for i in range(1, DELAY + 1):
		var k := turn + i - DELAY
		if k >= 1:
			out.append({"pos": hist[k]["pos"], "act": hist[k]["act"], "in": i})
	return out


## 다음 턴에 메아리가 설 칸(이미 확정되어 있다). 없으면 (-1,-1)
func next_echo_pos() -> Vector2i:
	var k := turn + 1 - DELAY
	return hist[k]["pos"] if k >= 1 else Vector2i(-1, -1)


## sim.py danger_cells 대응(표시용): 지금 공개된 의도대로면 다음 적 행동에서 피해가 나는 칸.
## 화살은 다음 턴의 메아리 칸에서 막히므로 그 칸부터는 위험하지 않다.
func danger_cells() -> Dictionary:
	var d: Dictionary = {}
	var block := next_echo_pos()
	for e in enemies:
		if e["intent"] == "hit":
			d[e["pos"] + e["dir"]] = true
		elif e["intent"] == "aim":
			var q: Vector2i = e["pos"] + e["dir"]
			while inb(q) and not walls.has(q) and q != block:
				d[q] = true
				q += e["dir"]
	return d


## sim.py bfs_step 대응: src 에서 플레이어까지 최단 경로의 첫 걸음 방향("" = 길 없음)
func bfs_step(src: Vector2i, blocked: Dictionary) -> String:
	var goal := player
	var prev: Dictionary = {src: null}
	var queue: Array[Vector2i] = [src]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c == goal:
			break
		for d in DORDER:
			var q: Vector2i = c + DIRS[d]
			if not inb(q) or prev.has(q) or walls.has(q):
				continue
			if q != goal and blocked.has(q):
				continue
			prev[q] = [c, d]
			queue.append(q)
	if not prev.has(goal):
		return ""
	var cur := goal
	var first := ""
	while prev[cur] != null:
		first = prev[cur][1]
		cur = prev[cur][0]
	return first


## sim.py los_dir 대응: 궁수가 조준할 방향("" = 사선 없음)
func los_dir(src: Vector2i) -> String:
	var ep := echo_pos()
	var echo := has_echo()
	for d in DORDER:
		var q: Vector2i = src + DIRS[d]
		if q == player:
			continue  # 최소 사거리 2
		while inb(q) and not walls.has(q) and enemy_at(q) == null and not (echo and q == ep):
			if q == player:
				return d
			q += DIRS[d]
	return ""


## sim.py compute_intents 대응: 다음 턴에 공개될 의도
func compute_intents() -> void:
	var occ: Dictionary = {}
	for e in enemies:
		occ[e["pos"]] = true
	if has_echo():
		occ[echo_pos()] = true
	for e in enemies:
		e["intent"] = "none"
		e["dir"] = Vector2i.ZERO
		var pos: Vector2i = e["pos"]
		var dist: int = absi(pos.x - player.x) + absi(pos.y - player.y)
		var blocked := occ.duplicate()
		blocked.erase(pos)
		if e["kind"] == "A":
			var aim := los_dir(pos)
			if aim != "":
				e["intent"] = "aim"
				e["dir"] = DIRS[aim]
			elif dist > 1:
				var m := bfs_step(pos, blocked)
				if m != "":
					e["intent"] = "move"
					e["dir"] = DIRS[m]
			continue
		if dist == 1:
			for d in DORDER:
				if pos + DIRS[d] == player:
					e["intent"] = "hit"
					e["dir"] = DIRS[d]
			continue
		var step_dir := bfs_step(pos, blocked)
		if step_dir != "":
			e["intent"] = "move"
			e["dir"] = DIRS[step_dir]


func _kill(e: Dictionary, src: String, events: Array) -> void:
	enemies.erase(e)
	kills[src] += 1
	events.append({"type": "kill", "pos": e["pos"], "kind": e["kind"], "src": src})


func _hurt(by: String, events: Array) -> void:
	hp = maxi(0, hp - 1)  # 한 턴에 여러 번 맞아도 0 아래로 내려가지 않는다
	events.append({"type": "hurt", "by": by, "hp": hp})


## sim.py step 대응. 한 턴을 끝까지 계산하고 그 턴에 일어난 일을 돌려준다. 호출 전에 can_act 로 확인할 것.
func step(act: String) -> Array:
	var events: Array = []
	turn += 1
	# 1. 플레이어
	var from := player
	if is_move(act):
		player = from + DIRS[act]
		events.append({"type": "move", "from": from, "to": player})
	elif is_slash(act):
		events.append({"type": "slash", "pos": player, "dir": DIRS[act[1]]})
	else:
		events.append({"type": "wait", "pos": player})
	hist.append({"pos": player, "act": act})

	# 2. 메아리 재생
	var echo := has_echo()
	var ep := echo_pos()
	if echo:
		var h: Dictionary = hist[turn - DELAY]
		var a: String = h["act"]
		events.append({"type": "echo", "pos": ep, "act": a, "first": turn - DELAY == 1})
		if is_move(a):
			var t = enemy_at(ep)
			if t != null:
				_kill(t, "stomp", events)
		elif is_slash(a):
			var target: Vector2i = ep + DIRS[a[1]]
			events.append({"type": "echo_slash", "pos": ep, "target": target})
			var t2 = enemy_at(target)
			if t2 != null:
				_kill(t2, "slash", events)

	# 3. 적 행동 (id 오름차순, 턴 시작에 공개된 의도대로)
	for e in enemies.duplicate():
		if not enemies.has(e) or e["intent"] == "none":
			continue
		var d: Vector2i = e["dir"]
		if e["intent"] == "move":
			var q: Vector2i = e["pos"] + d
			if inb(q) and not walls.has(q) and not (echo and q == ep) and q != player and enemy_at(q) == null:
				events.append({"type": "enemy_move", "id": e["id"], "from": e["pos"], "to": q})
				e["pos"] = q
		elif e["intent"] == "hit":
			var landed: bool = e["pos"] + d == player
			events.append({"type": "enemy_hit", "id": e["id"], "pos": e["pos"], "target": e["pos"] + d, "landed": landed})
			if landed:
				_hurt("W", events)
		elif e["intent"] == "aim":
			var q2: Vector2i = e["pos"] + d
			var result := "wall"
			var victim = null
			while inb(q2) and not walls.has(q2):
				if echo and q2 == ep:
					result = "echo"
					break
				victim = enemy_at(q2)
				if victim != null:
					result = "enemy"
					break
				if q2 == player:
					result = "player"
					break
				q2 += d
			if result == "wall":
				q2 -= d  # 마지막으로 지나간 칸에서 멈춘다(표시용)
			events.append({"type": "shot", "id": e["id"], "from": e["pos"], "to": q2, "result": result})
			if result == "enemy":
				_kill(victim, "friendly", events)
			elif result == "player":
				_hurt("A", events)
			elif result == "echo":
				events.append({"type": "block", "pos": ep})

	# 4. 증원
	if turn >= SQUEEZE_TURN and (turn - SQUEEZE_TURN) % SQUEEZE_EVERY == 0 and not enemies.is_empty():
		spawns.append([turn + 1, "W", SQUEEZE_CELL])
	var keep: Array = []
	for s in spawns:
		if s[0] <= turn:
			var p: Vector2i = s[2]
			if p != player and not (echo and p == ep) and enemy_at(p) == null:
				enemies.append({"id": next_id, "kind": s[1], "pos": p, "intent": "none", "dir": Vector2i.ZERO})
				events.append({"type": "spawn", "id": next_id, "kind": s[1], "pos": p})
				next_id += 1
				continue
			keep.append([s[0] + 1, s[1], s[2]])
		else:
			keep.append(s)
	spawns = keep

	# 5. 판정
	if hp <= 0:
		outcome = "dead"
	elif enemies.is_empty() and spawns.is_empty():
		outcome = "clear"
	elif turn >= TURN_LIMIT:
		outcome = "timeout"
	if outcome != "":
		events.append({"type": outcome})

	# 6. 다음 턴 의도
	compute_intents()
	return events
