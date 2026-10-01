extends RefCounted
## 같은 하루 — 규칙만. 노드·그리기·실시간 없음.
## 기준 구현 design/sim/sim.py 의 Day 클래스와 함수 단위로 대응한다(함수마다 주석).
## FIRST_BUILD.md "규칙 확정" 4~9번. 한 틱(tick_once)이 규칙을 끝까지 계산하고 일어난 일을 ev 에 남긴다.

# 콘텐츠 (chapter_first.json 형식)
var T := 90
var tick_seconds := 2.0
var fast_seconds := 0.5
var start := ""
var max_items := 2
var max_queue := 3
var places: Array[String] = []
var place_name := {}
var edges: Array = []
var dist := {}                    # a -> {b: 틱}
var hop := {}                     # a -> {b: 다음 장소}
var npcs: Array[String] = []
var npc_name := {}
var itinerary: Array = []
var events: Array = []
var scenes: Array = []
var actions: Array = []
var act := {}
var goal: Array = []
var goal_name := ""
var item_names := {}

# 바퀴를 넘어 남는 것
var notes: Array = []             # 수첩(적힌 순서)
var seen := {}                    # "주민|틱" -> 장소
var solved := false
var loop := 0

# 하루
var tick := 0
var place := ""                   # 서 있는 장소. 걷는 중이면 ""
var walk_from := ""
var walk_to := ""
var walk_left := 0
var walk_total := 0
var acting := ""
var act_end := -1
var items: Array = []
var flags := {}                   # 표지 묶음
var new_notes: Array = []
var done: Array = []
var queue: Array = []
var late: Array = []
var last_missed := ""
var over := true
var result_solved := false
var result_new: Array = []
var result_late: Array = []
var ev: Array = []


func load_data(text: String) -> bool:
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	T = int(d["ticks"])
	tick_seconds = float(d["tick_seconds"])
	fast_seconds = float(d["fast_seconds"])
	start = str(d["start"])
	max_items = int(d["max_items"])
	max_queue = int(d["max_queue"])
	places = []
	place_name = {}
	for p in d["places"]:
		places.append(str(p["id"]))
		place_name[p["id"]] = p["name"]
	edges = d["edges"]
	npcs = []
	npc_name = {}
	for n in d["npcs"]:
		npcs.append(str(n["id"]))
		npc_name[n["id"]] = n["name"]
	itinerary = d["itinerary"]
	events = d["events"]
	scenes = d["scenes"]
	actions = d["actions"]
	act = {}
	for a in actions:
		act[a["id"]] = a
	goal = d["goal"]
	goal_name = str(d["goal_name"])
	item_names = d["item_names"]
	_all_pairs()
	notes = []
	seen = {}
	solved = false
	loop = 0
	over = true
	return true


func _all_pairs() -> void:
	# sim.py all_pairs 대응: 모든 장소 쌍의 가장 짧은 거리(+ 화면이 걸음을 그릴 다음 장소)
	dist = {}
	hop = {}
	for a in places:
		dist[a] = {}
		hop[a] = {}
		for b in places:
			dist[a][b] = 0 if a == b else 9999
			hop[a][b] = b
	for e in edges:
		var w := int(e[2])
		dist[e[0]][e[1]] = w
		dist[e[1]][e[0]] = w
	for k in places:
		for a in places:
			for b in places:
				if dist[a][k] + dist[k][b] < dist[a][b]:
					dist[a][b] = dist[a][k] + dist[k][b]
					hop[a][b] = hop[a][k]


## a 에서 b 까지 지나는 장소(둘 다 포함).
func path(a: String, b: String) -> Array:
	var out: Array = [a]
	var c := a
	while c != b and out.size() < 20:
		c = hop[c][b]
		out.append(c)
	return out


func ok(rule: Dictionary) -> bool:
	# sim.py ok 대응
	for f in rule.get("need", []):
		if not flags.has(f):
			return false
	for f in rule.get("forbid", []):
		if flags.has(f):
			return false
	return true


func npc_loc(npc: String, t: int) -> String:
	# sim.py npc_loc 대응: 위에서부터 처음 맞는 줄. 없으면 길 위("")
	for r in itinerary:
		if r["npc"] == npc and int(r["t0"]) <= t and t <= int(r["t1"]) and ok(r):
			return r["loc"]
	return ""


func busy() -> bool:
	return walk_left > 0 or acting != ""


func start_day() -> void:
	# sim.py Day.__init__ 대응
	loop += 1
	tick = 0
	place = start
	walk_from = ""
	walk_to = ""
	walk_left = 0
	walk_total = 0
	acting = ""
	act_end = -1
	items = []
	flags = {}
	new_notes = []
	done = []
	queue = []
	late = []
	last_missed = ""
	over = false
	ev = []
	_world()
	_stand()


func _world() -> void:
	# sim.py Day._world 대응: ① 내 행동의 결과 ② 세계 사건
	if acting != "" and act_end == tick:
		var a: Dictionary = act[acting]
		for it in a["take"]:
			items.erase(it)
		for it in a["give"]:
			items.append(it)
		for f in a["set"]:
			flags[f] = true
		done.append(acting)
		ev.append({"e": "act_done", "id": acting})
		acting = ""
		act_end = -1
	for e in events:
		if int(e["t"]) == tick and ok(e):
			for f in e["set"]:
				flags[f] = true
				ev.append({"e": "flag", "id": f})


func _stand() -> void:
	# sim.py Day._observe 대응 + 본 위치, 늦은 매듭(FIRST_BUILD.md 5번의 5)
	for o in scenes:
		if (o["loc"] as Array).has(place) and int(o["t0"]) <= tick and tick <= int(o["t1"]) and ok(o):
			if not notes.has(o["note"]):
				notes.append(o["note"])
				new_notes.append(o["note"])
				ev.append({"e": "note", "id": o["note"]})
	for n in npcs:
		if npc_loc(n, tick) == place:
			seen["%s|%d" % [n, tick]] = place
	if not busy():
		for id in late_choices():
			if not late.has(id):
				late.append(id)


## 한 틱. FIRST_BUILD.md 5번의 순서 그대로.
func tick_once() -> void:
	# sim.py Day._tick 대응
	if over:
		return
	ev = []
	if tick >= T - 1:
		end_day()
		return
	tick += 1
	_world()
	if walk_left > 0:
		walk_left -= 1
		if walk_left == 0:
			place = walk_to
			walk_from = ""
			walk_to = ""
			walk_total = 0
			ev.append({"e": "arrive", "place": place})
	if place != "":
		_stand()
	_start_next()
	if place != "" and not busy():
		_stand_late()


func _stand_late() -> void:
	for id in late_choices():
		if not late.has(id):
			late.append(id)


func end_day() -> void:
	if over:
		return
	over = true
	result_solved = true
	for f in goal:
		if not flags.has(f):
			result_solved = false
	if result_solved:
		solved = true
	result_new = new_notes.duplicate()
	result_late = late.duplicate()
	ev.append({"e": "end"})


func can(a: Dictionary) -> bool:
	# sim.py Day.can 대응
	if busy() or place == "" or a["loc"] != place:
		return false
	if not (int(a["t0"]) <= tick and tick <= int(a["t1"])) or tick + int(a["dur"]) > T - 1:
		return false
	if not ok(a):
		return false
	for k in a["know"]:
		if not notes.has(k):
			return false
	for i in a["items"]:
		if not items.has(i):
			return false
	if str(a["npc"]) != "" and npc_loc(a["npc"], tick) != place:
		return false
	if items.size() - (a["take"] as Array).size() + (a["give"] as Array).size() > max_items:
		return false
	return true


## 예약이 다 끝났을 때 내가 있을 곳.
func end_place() -> String:
	for i in range(queue.size() - 1, -1, -1):
		if places.has(queue[i]):
			return queue[i]
	if walk_left > 0:
		return walk_to
	return place


## 선택지(FIRST_BUILD.md 8번). 한가하면 can 인 행동, 바쁘면 예약할 수 있는 행동.
func choices() -> Array:
	var out: Array = []
	if over:
		return out
	if not busy():
		for a in actions:
			if can(a):
				out.append(a["id"])
		return out
	var ep := end_place()
	for a in actions:
		if a["loc"] != ep or a["id"] == acting or queue.has(a["id"]):
			continue
		var known := true
		for k in a["know"]:
			if not notes.has(k):
				known = false
		var blocked := false
		for f in a["forbid"]:
			if flags.has(f):
				blocked = true
		if known and not blocked:
			out.append(a["id"])
	return out


func late_choices() -> Array:
	var out: Array = []
	if over or busy() or place == "":
		return out
	for a in actions:
		if a["loc"] != place or tick <= int(a["t1"]) or done.has(a["id"]) or not ok(a):
			continue
		var fine := true
		for k in a["know"]:
			if not notes.has(k):
				fine = false
		for i in a["items"]:
			if not items.has(i):
				fine = false
		if fine:
			out.append(a["id"])
	return out


func _begin_walk(p: String) -> bool:
	# sim.py Day.go 대응(걷는 틱은 tick_once 가 넘긴다)
	if p == place or not places.has(p) or tick + int(dist[place][p]) > T - 1:
		return false
	walk_from = place
	walk_to = p
	walk_left = int(dist[place][p])
	walk_total = walk_left
	place = ""
	ev.append({"e": "walk", "to": p})
	return true


func _begin_act(id: String) -> bool:
	# sim.py Day.do 대응(걸리는 틱은 tick_once 가 넘긴다)
	if not act.has(id) or not can(act[id]):
		return false
	acting = id
	act_end = tick + int(act[id]["dur"])
	ev.append({"e": "act_start", "id": id})
	return true


func _start_next() -> void:
	while not busy() and not queue.is_empty():
		var q: String = queue.pop_front()
		if places.has(q):
			_begin_walk(q)
		elif not _begin_act(q):
			last_missed = q
			ev.append({"e": "missed", "id": q})


## 장소를 고른다(FIRST_BUILD.md 6·7번). 시작했거나 예약했으면 true.
func go(p: String) -> bool:
	if over or not places.has(p):
		return false
	ev = []
	if not busy():
		return _begin_walk(p)
	if queue.size() >= max_queue or p == end_place():
		return false
	queue.append(p)
	return true


## 선택지를 고른다. choices 에 없으면 false.
func choose(id: String) -> bool:
	if over or not choices().has(id):
		return false
	ev = []
	if not busy():
		return _begin_act(id)
	if queue.size() >= max_queue:
		return false
	queue.append(id)
	return true


func clear_queue() -> void:
	queue = []


func sorted_flags() -> Array:
	var out: Array = flags.keys()
	out.sort()
	return out


func expected(npc: String) -> String:
	return str(seen.get("%s|%d" % [npc, tick], ""))


func scene_of(note: String) -> Dictionary:
	for o in scenes:
		if o["note"] == note:
			return o
	return {}


## 지금 내 장소에서 보이는 장면(그리기용).
func scenes_here() -> Array:
	var out: Array = []
	if place == "":
		return out
	for o in scenes:
		if (o["loc"] as Array).has(place) and int(o["t0"]) <= tick and tick <= int(o["t1"]) and ok(o):
			out.append(o)
	return out


## 수첩 시간표: 주민 순서대로, 수첩에 있는 장면을 t0 순(같으면 데이터 순)으로.
func timetable() -> Array:
	var out: Array = []
	for n in npcs:
		var entries: Array = []
		for o in scenes:
			if o["who"] == n and notes.has(o["note"]):
				var e := {"note": o["note"], "t0": int(o["t0"]), "t1": int(o["t1"]), "text": o["text"]}
				var at := entries.size()        # 안정 삽입: t0 가 같으면 데이터 순서 그대로
				while at > 0 and int(entries[at - 1]["t0"]) > int(e["t0"]):
					at -= 1
				entries.insert(at, e)
		out.append({"who": n, "entries": entries})
	return out
