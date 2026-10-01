extends RefCounted
## 불길 속으로 — 규칙만. 노드·그리기·시간·난수 없음.
## 기준 구현 design/sim/sim.py 의 S 클래스와 함수 단위로 대응한다(함수마다 주석).
## 행동 하나(act)가 규칙을 끝까지 계산하고, 그 사이 일어난 일을 ev(목록)에 남긴다. 화면은 ev 를 재생한다.

const W := 11
const H := 13
const N := W * H
const DX: Array[int] = [0, 1, 0, -1]      # 방향 순서: 위, 오른쪽, 아래, 왼쪽
const DY: Array[int] = [-1, 0, 1, 0]
const DIR_OF := {"U": 0, "R": 1, "D": 2, "L": 3}

# 수치 (FIRST_BUILD.md 수치표 = sim.py 상수)
const MATS := {"_": [0, 0], ".": [3, 12], "~": [2, 8], "\"": [1, 3], "F": [3, 20]}
const DOOR_HP := 10
const AIR_PER_CELL := 1
const GAS_BURST := 5
const BURST_LEN := 3
const BURST_IN := 2
const AIR_IN := 2
const ROOM_HP := 30
const COLLAPSE_WARN := 5
const P_HP := 4
const TANK_AIR := 140
const FIRE_EVERY := 2
const SPRAY_LEN := 3
const WET := -2
const V_HP := 12
const SMOKE_EVERY := 5
const CARRY_COST := 2
const RUBBLE_COST := 3
const MAX_ACTIONS := 600
const EXIT := 12 * W + 5

var kind: Array[String] = []      # "#" 벽, "V" 깨진 창, "E" 출구, "D" 문, "." 바닥
var mat: Array[String] = []       # 바닥 재질 글자(그리기용): _ . ~ " F
var room: Array[int] = []
var T: Array[int] = []
var fuel: Array[int] = []
var furn: Array[bool] = []
var fire: Array[int] = []         # 0 없음, 1 불, 2 숨죽은 불
var heat: Array[int] = []
var ash: Array[bool] = []
var rubble: Array[bool] = []
var door: Dictionary = {}         # 칸 -> {"open", "hp", "burnt", "a", "b"}
var rooms: Array = []             # {"id","cells","doors","vent","full","air","smolder","gas","front","hp","collapsed"}
var pos := EXIT
var hp := P_HP
var air := TANK_AIR
var water := 0
var carry := -1
var victims: Array = []           # {"cell", "hp", "state"}  state: in / carried / saved / dead
var t := 0                        # 지나간 불 박자
var clock := 0                    # 쓴 행동 수
var over := ""                    # "" / "retreat" / "dead" / "limit"
var hurt_cause := ""              # 마지막으로 체력을 깎은 원인: fire / backdraft / collapse / air
var name := ""
var title := ""
var ev: Array = []                # 마지막 act 에서 일어난 일


func step(i: int, d: int) -> int:
	# sim.py step 대응
	var x := i % W + DX[d]
	var y := i / W + DY[d]
	if x >= 0 and x < W and y >= 0 and y < H:
		return y * W + x
	return -1


func load_json(text: String) -> bool:
	# design/first_build_replay.py from_json 대응
	var b = JSON.parse_string(text)
	if typeof(b) != TYPE_DICTIONARY:
		return false
	name = str(b.get("name", ""))
	title = str(b.get("title", ""))
	kind.resize(N); mat.resize(N); room.resize(N); T.resize(N); fuel.resize(N); furn.resize(N)
	fire.resize(N); heat.resize(N); ash.resize(N); rubble.resize(N)
	var nrooms: int = (b["rooms"] as Array).size()
	rooms = []
	for i in nrooms:
		rooms.append({"id": i, "cells": [], "doors": [], "vent": false, "full": 0, "air": 0, "smolder": false, "gas": 0,
			"front": -1, "hp": ROOM_HP, "collapsed": false})
	door = {}
	for y in H:
		for x in W:
			var c := y * W + x
			var ch: String = (b["floor"][y] as String)[x]
			kind[c] = "#"; mat[c] = ""; room[c] = -1; T[c] = 0; fuel[c] = 0; furn[c] = false
			fire[c] = 0; heat[c] = 0; ash[c] = false; rubble[c] = false
			if ch == "#" or ch == "V" or ch == "E":
				kind[c] = ch
			elif ch == "+" or ch == "/" or ch == "x":
				kind[c] = "D"
			else:
				kind[c] = "."
				mat[c] = ch
				var rid := int((b["room"][y] as String)[x])
				room[c] = rid
				(rooms[rid]["cells"] as Array).append(c)
				T[c] = MATS[ch][0]
				fuel[c] = MATS[ch][1]
				furn[c] = ch == "F"
				var st: String = (b["state"][y] as String)[x]
				if st == "f":
					fire[c] = 1
				elif st == "o":
					fire[c] = 2
				elif st == ",":
					ash[c] = true; fuel[c] = 0; furn[c] = false
				elif st == "r":
					rubble[c] = true; fuel[c] = 0; furn[c] = false
	for k in (b["heat"] as Dictionary):
		heat[int(k)] = int(b["heat"][k])
	for k in (b["fuel"] as Dictionary):
		fuel[int(k)] = int(b["fuel"][k])
	var dhp := {}
	for k in (b["doors"] as Dictionary):
		dhp[int(k)] = int(b["doors"][k])
	# 문: 네 이웃이 속한 방(없으면 -1). 낮은 번호가 먼저
	for y in H:
		for x in W:
			var c := y * W + x
			var ch: String = (b["floor"][y] as String)[x]
			if ch != "+" and ch != "/" and ch != "x":
				continue
			var near: Array[int] = []
			for d in 4:
				var n := step(c, d)
				if n >= 0 and room[n] >= 0 and not near.has(room[n]):
					near.append(room[n])
			near.sort()
			door[c] = {"open": ch == "/" or ch == "x", "hp": int(dhp.get(c, DOOR_HP)), "burnt": ch == "x",
				"a": near[0] if near.size() > 0 else -1, "b": near[1] if near.size() > 1 else -1}
			for rid in near:
				(rooms[rid]["doors"] as Array).append(c)
	for i in nrooms:
		var r: Dictionary = rooms[i]
		var rb: Dictionary = b["rooms"][i]
		r["full"] = (r["cells"] as Array).size() * AIR_PER_CELL
		r["air"] = int(rb["air"]); r["gas"] = int(rb["gas"]); r["smolder"] = bool(rb["smolder"])
		r["front"] = int(rb["front"]); r["hp"] = int(rb["hp"]); r["collapsed"] = bool(rb["collapsed"])
		var vent := false
		for c in r["cells"]:
			for d in 4:
				var n := step(c, d)
				if n >= 0 and kind[n] == "V":
					vent = true
		r["vent"] = vent
	victims = []
	for v in b["victims"]:
		victims.append({"cell": int(v[0]), "hp": int(v[1]), "state": "in"})
	water = int(b["water"])
	pos = int(b.get("start", EXIT))
	hp = int(b.get("hp", P_HP))
	air = int(b.get("air", TANK_AIR))
	carry = -1
	t = 0
	clock = 0
	over = ""
	hurt_cause = ""
	ev = []
	return true


func clone() -> RefCounted:
	var s = get_script().new()
	s.kind = kind; s.mat = mat; s.room = room; s.T = T      # 바뀌지 않는 것은 함께 쓴다
	s.fuel = fuel.duplicate(); s.furn = furn.duplicate(); s.fire = fire.duplicate(); s.heat = heat.duplicate()
	s.ash = ash.duplicate(); s.rubble = rubble.duplicate()
	s.door = door.duplicate(true); s.rooms = rooms.duplicate(true); s.victims = victims.duplicate(true)
	s.pos = pos; s.hp = hp; s.air = air; s.water = water; s.carry = carry; s.t = t; s.clock = clock; s.over = over
	return s


# ---------------------------------------------------------------- 불

func sealed(r: Dictionary) -> bool:
	# sim.py sealed 대응
	if r["vent"] or r["id"] == 0:
		return false
	for d in r["doors"]:
		if door[d]["open"]:
			return false
	return true


func smoke_map() -> Array:
	# sim.py smoke_map 대응. 방이 하나뿐인 문(b == -1)은 파이썬의 음수 인덱스처럼 마지막 방과 묶인다(sim 과 같게).
	var n := rooms.size()
	var comp: Array[int] = []
	for i in n:
		comp.append(i)
	var find := func(a: int) -> int:
		if a < 0:
			a += n
		while comp[a] != a:
			comp[a] = comp[comp[a]]
			a = comp[a]
		return a
	for d in door:
		var dr: Dictionary = door[d]
		if dr["open"]:
			comp[find.call(dr["a"])] = find.call(dr["b"])
	var hot := {}
	for r in rooms:
		for q in r["cells"]:
			if fire[q] != 0:
				hot[find.call(r["id"])] = true
				break
	var out: Array = []
	for r in rooms:
		out.append(hot.has(find.call(r["id"])))
	return out


func door_dist(r: Dictionary) -> Dictionary:
	# sim.py door_dist 대응: 열린 문(깨진 창)에 붙은 방 안 칸이 1, 거기서 너비 우선
	var dist := {}
	var q: Array[int] = []
	var rid: int = r["id"]
	if r["vent"]:
		for c in r["cells"]:
			for d in 4:
				var n := step(c, d)
				if n >= 0 and kind[n] == "V":
					dist[c] = 1
					q.append(c)
					break
	for d in r["doors"]:
		if door[d]["open"]:
			for k in 4:
				var c := step(d, k)
				if c >= 0 and room[c] == rid and not dist.has(c):
					dist[c] = 1
					q.append(c)
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		for k in 4:
			var n := step(c, k)
			if n >= 0 and room[n] == rid and not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return dist


func jet_from(r: Dictionary, d: int) -> Array:
	# sim.py jet_cells 의 문 하나 몫: 문 칸부터 방 바깥으로 문 칸 포함 최대 BURST_LEN + 1 칸
	var out: Array = []
	for k in 4:
		var inside := step(d, k)
		if inside >= 0 and room[inside] == r["id"]:
			var dir := (k + 2) % 4
			var c := d
			var n := 0
			while c >= 0 and n <= BURST_LEN:
				if kind[c] == "#" or kind[c] == "V" or kind[c] == "E" or (c != d and door.has(c) and not door[c]["open"]):
					break
				out.append(c)
				c = step(c, dir)
				n += 1
			break
	return out


func jet_cells(r: Dictionary) -> Array:
	# sim.py jet_cells 대응: 방의 열린 문마다
	var out: Array = []
	for d in r["doors"]:
		if not door[d]["open"]:
			continue
		out.append_array(jet_from(r, d))
	return out


func burst(r: Dictionary) -> void:
	# sim.py burst 대응
	var cells := jet_cells(r)
	ev.append({"e": "burst", "room": r["id"], "cells": cells.duplicate()})
	for c in cells:
		hit(c, 2, 4)
		if kind[c] == "." and fuel[c] > 0 and not ash[c] and fire[c] == 0 and not rubble[c]:
			fire[c] = 1
			heat[c] = T[c]
			ev.append({"e": "ignite", "c": c})


func hit(c: int, pdmg: int, vdmg: int) -> void:
	# sim.py hit 대응
	if pos == c:
		hp -= pdmg
		hurt_cause = "backdraft"
		ev.append({"e": "hurt", "cause": "backdraft", "n": pdmg})
		if carry >= 0:
			victims[carry]["hp"] -= vdmg
			ev.append({"e": "breath", "i": carry})
	for i in victims.size():
		var v: Dictionary = victims[i]
		if v["state"] == "in" and v["cell"] == c:
			v["hp"] -= vdmg
			ev.append({"e": "breath", "i": i})


func fire_step() -> void:
	# sim.py fire_step 대응 (FIRST_BUILD.md "불 박자" ①~⑥)
	t += 1
	ev.append({"e": "beat"})
	# ① 방의 공기
	for r in rooms:
		if r["collapsed"]:
			continue
		var burning: Array[int] = []
		var embers: Array[int] = []
		for c in r["cells"]:
			if fire[c] == 1:
				burning.append(c)
			elif fire[c] == 2:
				embers.append(c)
		if sealed(r):
			r["front"] = -1
			if not burning.is_empty():
				r["air"] -= burning.size()
				if r["air"] <= 0:
					r["air"] = 0
					r["smolder"] = true
					for c in burning:
						fire[c] = 2
					ev.append({"e": "smolder", "room": r["id"]})
			elif not embers.is_empty():
				r["smolder"] = true
				r["gas"] += 1
			else:
				r["smolder"] = false
				r["gas"] = 0
		else:
			r["air"] = mini(r["full"], r["air"] + AIR_IN)
			if not embers.is_empty():
				# 공기는 열린 문에서부터 한 박자에 한 칸씩 들어온다
				r["front"] += 1
				if r["front"] >= 1:
					if r["gas"] >= GAS_BURST:
						burst(r)
						r["front"] = maxi(r["front"], BURST_IN)
					r["gas"] = 0
					r["smolder"] = false
					var dist := door_dist(r)
					for c in embers:
						if int(dist.get(c, 99)) <= r["front"] and c != pos:
							fire[c] = 1
							ev.append({"e": "revive", "c": c})
				else:
					ev.append({"e": "suction", "room": r["id"]})
			else:
				r["smolder"] = false
				r["gas"] = 0
				r["front"] = -1
	# ② 열 전달
	var add := {}
	var was_burning: Array[int] = []
	for c in N:
		if fire[c] == 1:
			was_burning.append(c)
	for c in was_burning:
		for d in 4:
			var n := step(c, d)
			if n < 0:
				continue
			var k := kind[n]
			if k == "D":
				var dr: Dictionary = door[n]
				if dr["open"]:
					var n2 := step(n, d)
					if n2 >= 0 and kind[n2] == ".":
						add[n2] = int(add.get(n2, 0)) + 1
				else:
					dr["hp"] -= 1
					if dr["hp"] <= 0:
						dr["open"] = true
						dr["burnt"] = true
						ev.append({"e": "doorburnt", "c": n})
			elif k == ".":
				add[n] = int(add.get(n, 0)) + 1
	for c in N:
		if kind[c] != "." or fire[c] != 0:
			continue
		var a := int(add.get(c, 0))
		if a > 0:
			heat[c] += a
		elif heat[c] > 0:
			heat[c] -= 1
		elif heat[c] < 0:
			heat[c] += 1
	# ③ 발화
	for c in add:
		if fire[c] != 0 or ash[c] or fuel[c] <= 0 or rubble[c]:
			continue
		if heat[c] >= T[c]:
			var r: Dictionary = rooms[room[c]]
			if r["smolder"] or c == pos:
				heat[c] = T[c]
				continue
			fire[c] = 1
			ev.append({"e": "ignite", "c": c})
	# ④ 연소
	for c in was_burning:
		if fire[c] != 1:
			continue
		fuel[c] -= 1
		if fuel[c] <= 0:
			fire[c] = 0
			heat[c] = 0
			ash[c] = true
			furn[c] = false
	# ⑤ 붕괴 (복도는 무너지지 않는다)
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		if r["collapsed"]:
			continue
		var any_fire := false
		for c in r["cells"]:
			if fire[c] == 1:
				any_fire = true
				break
		if any_fire:
			r["hp"] -= 1
		if r["hp"] <= 0:
			r["collapsed"] = true
			ev.append({"e": "collapse", "room": i})
			for c in r["cells"]:
				rubble[c] = true
				fire[c] = 0
				heat[c] = 0
				fuel[c] = 0
				furn[c] = false
			if room[pos] == i:
				hp -= 2
				hurt_cause = "collapse"
				ev.append({"e": "hurt", "cause": "collapse", "n": 2})
				if carry >= 0:
					victims[carry]["state"] = "dead"
					ev.append({"e": "dead", "i": carry})
					carry = -1
			for j in victims.size():
				var v: Dictionary = victims[j]
				if v["state"] == "in" and room[v["cell"]] == i:
					v["state"] = "dead"
					ev.append({"e": "dead", "i": j})
	# ⑥ 구조 대상
	var smoke: Array = smoke_map() if t % SMOKE_EVERY == 0 else []
	for j in victims.size():
		var v: Dictionary = victims[j]
		if v["state"] != "in":
			continue
		var c: int = v["cell"]
		var near := false
		for d in 4:
			var n := step(c, d)
			if n >= 0 and fire[n] == 1:
				near = true
				break
		var before: int = v["hp"]
		if fire[c] == 1:
			v["hp"] -= 2
		elif near:
			v["hp"] -= 1
		elif not smoke.is_empty() and room[c] >= 0 and smoke[room[c]]:
			v["hp"] -= 1
		if v["hp"] != before:
			ev.append({"e": "breath", "i": j})
		if v["hp"] <= 0:
			v["state"] = "dead"
			ev.append({"e": "dead", "i": j})


func player_step() -> void:
	# sim.py player_step 대응 (FIRST_BUILD.md "소방관 처리")
	clock += 1
	if fire[pos] == 1:
		hp -= 1
		hurt_cause = "fire"
		ev.append({"e": "hurt", "cause": "fire", "n": 1})
		if carry >= 0:
			victims[carry]["hp"] -= 2
			ev.append({"e": "breath", "i": carry})
	air -= 1
	if air < 0 and (-air) % 6 == 0:
		hp -= 1
		hurt_cause = "air"
		ev.append({"e": "hurt", "cause": "air", "n": 1})
	if pos == EXIT:
		air = TANK_AIR
		if carry >= 0:
			victims[carry]["state"] = "saved"
			victims[carry]["cell"] = pos
			ev.append({"e": "saved", "i": carry})
			carry = -1
	if carry >= 0 and victims[carry]["hp"] <= 0:
		victims[carry]["state"] = "dead"
		victims[carry]["cell"] = pos
		ev.append({"e": "dead", "i": carry})
		carry = -1


# ---------------------------------------------------------------- 행동

func passable(c: int) -> bool:
	# sim.py passable 대응
	return c >= 0 and (kind[c] == "." or kind[c] == "D" or kind[c] == "E") and not furn[c]


func closed_door(c: int) -> bool:
	return door.has(c) and not door[c]["open"]


func legal(a: String) -> bool:
	# design/first_build_replay.py legal 대응 (FIRST_BUILD.md "행동 가능 여부")
	if over != "":
		return false
	if a == "W":
		return true
	if a == "Q":
		return pos == EXIT
	if a == "P":
		if carry >= 0:
			return false
		for v in victims:
			if v["state"] == "in" and v["cell"] == pos:
				return true
		return false
	if a == "X":
		return carry >= 0 and kind[pos] == "."
	if a.length() == 1 and DIR_OF.has(a):
		return passable(step(pos, DIR_OF[a]))
	if a.length() == 2 and DIR_OF.has(a[1]):
		var n := step(pos, DIR_OF[a[1]])
		if a[0] == "S":
			if water <= 0 or carry >= 0:
				return false
			return not (n < 0 or kind[n] == "#" or kind[n] == "V" or kind[n] == "E" or closed_door(n))
		if a[0] == "C":
			if not door.has(n) or not door[n]["open"] or door[n]["burnt"]:
				return false
			for v in victims:
				if v["state"] == "in" and v["cell"] == n:
					return false
			return true
	return false


## 물이 닿을 칸(미리보기와 연출용). sim.py act 의 "s" 와 같은 걸음.
func spray_cells(d: int) -> Array:
	var out: Array = []
	var c := pos
	for _i in SPRAY_LEN:
		c = step(c, d)
		if c < 0 or kind[c] == "#" or kind[c] == "V" or kind[c] == "E" or closed_door(c):
			break
		out.append(c)
		if kind[c] == "." and furn[c]:
			break
	return out


func act(a: String) -> bool:
	# sim.py act 대응. 불가능한 행동은 거절한다(행동 수를 쓰지 않는다).
	if not legal(a):
		return false
	ev = []
	if a == "Q":
		over = "retreat"
		ev.append({"e": "retreat"})
		return true
	var cost := 1
	if a.length() == 1 and DIR_OF.has(a):
		var n := step(pos, DIR_OF[a])
		if closed_door(n):
			door[n]["open"] = true
			ev.append({"e": "open", "c": n})
		else:
			ev.append({"e": "move", "from": pos, "to": n})
			pos = n
			if carry >= 0:
				cost = CARRY_COST
				victims[carry]["cell"] = pos
			if rubble[n]:
				cost += RUBBLE_COST - 1
	elif a[0] == "S" and a.length() == 2:
		water -= 1
		var cells := spray_cells(DIR_OF[a[1]])
		for c in cells:
			if kind[c] == ".":
				fire[c] = 0
				heat[c] = WET
		ev.append({"e": "spray", "cells": cells, "dir": DIR_OF[a[1]]})
	elif a[0] == "C" and a.length() == 2:
		var n := step(pos, DIR_OF[a[1]])
		door[n]["open"] = false
		ev.append({"e": "close", "c": n})
	elif a == "P":
		for i in victims.size():
			var v: Dictionary = victims[i]
			if v["state"] == "in" and v["cell"] == pos:
				v["state"] = "carried"
				carry = i
				ev.append({"e": "pick", "i": i})
				break
	elif a == "X":
		var v: Dictionary = victims[carry]
		v["cell"] = pos
		v["state"] = "in"
		ev.append({"e": "drop", "i": carry})
		carry = -1
	for _i in cost:
		player_step()
		if clock % FIRE_EVERY == 0:
			fire_step()
		if hp <= 0:
			break
	if hp <= 0:
		over = "dead"
	elif clock >= MAX_ACTIONS:
		over = "limit"
	return true


# ---------------------------------------------------------------- 표시용 값 (규칙이 아님)

## 다음 불 박자에 새로 불이 붙을 칸(칸 번호 오름차순). first_build_replay.py forecast 대응.
func forecast() -> Array:
	var s = clone()
	s.ev = []
	s.fire_step()
	var out: Array = []
	for c in N:
		if s.fire[c] == 1 and fire[c] == 0:
			out.append(c)
	return out


## 닫힌 문의 징후. first_build_replay.py door_sign 대응.
func door_sign(d: int) -> String:
	if not door.has(d) or door[d]["open"]:
		return "none"
	var rank := {"none": 0, "burning": 1, "smolder": 2, "backdraft": 3}
	var best := "none"
	for rid in [door[d]["a"], door[d]["b"]]:
		var s := room_sign(rid)
		if rank[s] > rank[best]:
			best = s
	return best


func room_sign(rid: int) -> String:
	if rid <= 0:
		return "none"
	var r: Dictionary = rooms[rid]
	if r["collapsed"]:
		return "none"
	if r["smolder"] and r["gas"] >= GAS_BURST:
		return "backdraft"
	if r["smolder"]:
		return "smolder"
	for c in r["cells"]:
		if fire[c] == 1:
			return "burning"
	return "none"


## 문 d 의 징후를 만든 방(없으면 -1). 그리기에서 점이 움직이는 방향에 쓴다.
func sign_room(d: int) -> int:
	var s := door_sign(d)
	if s == "none":
		return -1
	for rid in [door[d]["a"], door[d]["b"]]:
		if room_sign(rid) == s:
			return rid
	return -1


func saved_count() -> int:
	var n := 0
	for v in victims:
		if v["state"] == "saved":
			n += 1
	return n


func stars() -> int:
	if over == "dead":
		return 0
	var s := saved_count()
	if s == 0:
		return 0
	if s == victims.size():
		return 3
	if s == victims.size() - 1:
		return 2
	return 1
