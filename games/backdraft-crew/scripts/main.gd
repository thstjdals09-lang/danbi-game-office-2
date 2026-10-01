extends Node2D
## 불길 속으로 — 첫 빌드(기획 v1). 상태·입력·그리기·연출.
## 규칙은 scripts/rules.gd (design/sim/sim.py 대응), 콘텐츠는 scripts/content.gd.
## 규칙 상태는 행동을 확정하는 즉시 끝까지 계산되고, 화면은 rules.ev 를 따라 연출만 한다.

enum State { TITLE, PLAY, RESULT }

const Rules := preload("res://scripts/rules.gd")
const Content := preload("res://scripts/content.gd")

const W := 540.0
const H := 960.0
const CELL := 44.0
const BOARD := Vector2(28, 40)            # 보드 484×572, 화면 위쪽 64% 안(아래 끝 612)
const SWIPE_MIN := 24.0                   # 이보다 짧게 밀면 탭
const BTN_Y := 704.0
const BTN_H := 100.0
const BTN_W := 120.0
const BTN_GAP := 12.0
const BTN_IDS: Array[String] = ["water", "close", "carry", "wait"]
const RETREAT_RECT := Rect2(150, 654, 240, 42)
const DIRS: Array[String] = ["U", "R", "D", "L"]
const DIRV: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const WALK_TIME := 0.12
const FLASH_TIME := 0.15
const HURT_TIME := 0.2
const BURST_HOLD := 0.2

const C_BG := Color("0b1420")
const C_WALL := Color("1b2532")
const C_WALL_HI := Color("2b3848")
const C_TEXT := Color("edf4ff")
const C_DIM := Color("8794a6")
const C_FIRE := Color("f08a24")
const C_FIRE_HI := Color("ffd65a")
const C_EMBER := Color("a9b1bb")
const C_WATER := Color("5ab0ff")
const C_WARN := Color("ff5a4d")
const C_ME := Color("ffd23c")
const C_OK := Color("7be08a")

var state: State = State.TITLE
var font: Font
var rules: RefCounted
var buildings: Array = []
var custom := false                        # debug_load 로 시작한 출동인가
var building_index := 0
var last_action := ""
var mode := ""                             # 방향 대기: "" / "water" / "close"
var forecast: Array = []
var result_stars := 0
var result_cause := ""
var water0 := 0

var building_count: int:
	get: return buildings.size()
var clock: int:
	get: return rules.clock if rules else 0
var beat: int:
	get: return rules.t if rules else 0
var pos: Vector2i:
	get: return _xy(rules.pos) if rules else Vector2i.ZERO
var hp: int:
	get: return maxi(0, rules.hp) if rules else 0
var air: int:
	get: return rules.air if rules else 0
var water: int:
	get: return rules.water if rules else 0
var carrying: bool:
	get: return rules != null and rules.carry >= 0
var saved: int:
	get: return rules.saved_count() if rules else 0
var victims: Array:
	get:
		var out: Array = []
		if rules:
			for i in rules.victims.size():
				var v: Dictionary = rules.victims[i]
				var c: int = rules.pos if v["state"] == "carried" else int(v["cell"])
				out.append({"pos": _xy(c), "breath": maxi(0, int(v["hp"])), "state": v["state"]})
		return out

# 연출
var clk := 0.0
var fx: Array = []                         # {"k", "t", "d", ...}
var slide_from := Vector2.ZERO
var slide_t := 1.0
var slide_d := WALK_TIME
var shake_t := 0.0
var shake_amp := 0.0
var pressing := false
var press_pos := Vector2.ZERO
var hint_flash := ""


func _ready() -> void:
	font = load("res://assets/fonts/NotoSansKR-Medium.ttf")
	buildings = Content.BUILDINGS.duplicate()


func _process(delta: float) -> void:
	clk += delta
	slide_t = minf(1.0, slide_t + delta / slide_d)
	shake_t = maxf(0.0, shake_t - delta)
	for f in fx:
		f["t"] += delta
	fx = fx.filter(func(f): return f["t"] < f["d"])
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)


# ---------------------------------------------------------------- 입력 (실제 터치와 debug_* 가 같은 길)

func _press(p: Vector2) -> void:
	_skip_fx()          # 연출 중 새로 누르면 연출을 끝까지 넘기고, 이 입력은 정상 처리한다
	pressing = true
	press_pos = p


func _release(p: Vector2) -> void:
	if not pressing:
		return
	pressing = false
	match state:
		State.TITLE:
			buildings = Content.BUILDINGS.duplicate()
			custom = false
			_start_building(0)
		State.RESULT:
			if building_index + 1 < buildings.size():
				_start_building(building_index + 1)
			else:
				_to_title()
		State.PLAY:
			var d := p - press_pos
			if d.length() >= SWIPE_MIN:
				var dir := 0
				if absf(d.x) > absf(d.y):
					dir = 1 if d.x > 0 else 3
				else:
					dir = 2 if d.y > 0 else 0
				_swipe(dir)
			else:
				var id := _button_at(press_pos)
				if id != "":
					_button(id)


func _swipe(dir: int) -> void:
	var a := DIRS[dir]
	if mode == "water":
		a = "S" + a
	elif mode == "close":
		a = "C" + a
	mode = ""
	_do(a)


func _button_rect(i: int) -> Rect2:
	return Rect2(BTN_GAP + i * (BTN_W + BTN_GAP), BTN_Y, BTN_W, BTN_H)


func _button_at(p: Vector2) -> String:
	for i in BTN_IDS.size():
		if _button_rect(i).has_point(p):
			return BTN_IDS[i]
	if RETREAT_RECT.has_point(p):
		return "retreat"
	return ""


func _closable() -> Array:
	var out: Array = []
	for d in DIRS:
		if rules.legal("C" + d):
			out.append(d)
	return out


func _button(id: String) -> void:
	if state != State.PLAY:
		return
	match id:
		"water":
			if mode == "water":
				mode = ""
			elif rules.water <= 0 or rules.carry >= 0:
				_add_fx("btn", 0.2, {"id": id})
			else:
				mode = "water"
		"close":
			var c := _closable()
			if mode == "close":
				mode = ""
			elif c.is_empty():
				_add_fx("btn", 0.2, {"id": id})
			elif c.size() == 1:
				mode = ""
				_do("C" + str(c[0]))
			else:
				mode = "close"
		"carry":
			mode = ""
			if rules.legal("P"):
				_do("P")
			elif rules.legal("X"):
				_do("X")
			else:
				_add_fx("btn", 0.2, {"id": id})
		"wait":
			mode = ""
			_do("W")
		"retreat":
			if rules.legal("Q"):
				mode = ""
				_do("Q")


## 행동 하나를 확정한다. 규칙을 끝까지 계산한 뒤 연출을 건다. 불가능하면 false(아무것도 바뀌지 않는다).
func _do(a: String) -> bool:
	if state != State.PLAY:
		return false
	var heat_before: Array = rules.heat.duplicate()
	var was_carrying: bool = rules.carry >= 0
	if not rules.act(a):
		_add_fx("reject", 0.18, {"dir": DIRS.find(a.right(1))})
		return false
	last_action = a
	forecast = _forecast()
	_play_events(heat_before, was_carrying)
	if rules.over != "":
		state = State.RESULT
		result_cause = rules.over
		result_stars = rules.stars()
		_add_fx("result", 0.4, {})
	return true


func _forecast() -> Array:
	var out: Array = []
	for c in rules.forecast():
		out.append(_xy(c))
	return out


func _start_building(i: int) -> void:
	building_index = i
	rules = Rules.new()
	rules.load_json(buildings[i])
	water0 = rules.water
	state = State.PLAY
	last_action = ""
	mode = ""
	result_stars = 0
	result_cause = ""
	forecast = _forecast()
	_skip_fx()


func _to_title() -> void:
	state = State.TITLE
	buildings = Content.BUILDINGS.duplicate()
	custom = false
	building_index = 0
	rules = null
	mode = ""
	_skip_fx()


# ---------------------------------------------------------------- 연출

func _add_fx(k: String, d: float, data: Dictionary, delay := 0.0) -> void:
	var f := data.duplicate()
	f["k"] = k
	f["t"] = -delay
	f["d"] = d
	fx.append(f)


func _skip_fx() -> void:
	fx.clear()
	slide_t = 1.0
	shake_t = 0.0


func _fx_of(k: String) -> Array:
	return fx.filter(func(f): return f["k"] == k and f["t"] >= 0.0)


func _play_events(heat_before: Array, was_carrying: bool) -> void:
	# 한 행동의 연출은 합쳐서 0.6초를 넘지 않는다(가장 긴 것: 역류 0.2 + 0.3)
	for e in rules.ev:
		match e["e"]:
			"move":
				slide_from = _center(e["from"])
				slide_t = 0.0
				slide_d = WALK_TIME * (2.0 if was_carrying else 1.0)
			"open", "close":
				_add_fx("door", 0.12, {"c": e["c"], "opening": e["e"] == "open"})
			"spray":
				_add_fx("spray", 0.3, {"cells": e["cells"], "dir": e["dir"]})
			"beat":
				_add_fx("beat", 0.25, {})
			"ignite", "revive":
				_add_fx("flash", FLASH_TIME, {"c": e["c"]})
			"doorburnt":
				_add_fx("flash", FLASH_TIME, {"c": e["c"]})
			"smolder":
				_add_fx("dim", 0.35, {"room": e["room"]})
			"burst":
				_add_fx("burst", 0.3, {"cells": e["cells"]}, BURST_HOLD)
				_add_fx("label", 0.5, {"text": "역류!", "c": (e["cells"] as Array)[0] if not (e["cells"] as Array).is_empty() else rules.pos, "col": C_WARN})
				shake_t = 0.5
				shake_amp = 7.0
			"collapse":
				_add_fx("label", 0.5, {"text": "붕괴!", "c": (rules.rooms[e["room"]]["cells"] as Array)[0], "col": C_WARN})
				shake_t = 0.4
				shake_amp = 6.0
			"hurt":
				_add_fx("hurt", HURT_TIME, {})
			"saved":
				_add_fx("label", 0.55, {"text": "구조!", "c": Rules.EXIT, "col": C_OK})
			"pick", "drop":
				_add_fx("pop", 0.15, {})
			"breath":
				_add_fx("vblink", 0.3, {"i": e["i"]})
			"dead":
				_add_fx("vblink", 0.4, {"i": e["i"]})
	for c in Rules.N:
		if rules.heat[c] > int(heat_before[c]) and rules.fire[c] == 0:
			_add_fx("crack", 0.25, {"c": c})


# ---------------------------------------------------------------- 좌표

func _xy(c: int) -> Vector2i:
	return Vector2i(c % Rules.W, c / Rules.W)


func _cell_rect(c: int) -> Rect2:
	return Rect2(BOARD + Vector2(c % Rules.W, c / Rules.W) * CELL, Vector2(CELL, CELL))


func _center(c: int) -> Vector2:
	return _cell_rect(c).get_center()


func _txt(s: String, p: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, p, s, align, width, size, col)


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), C_BG)
	match state:
		State.TITLE:
			_draw_title()
		State.PLAY:
			_draw_play()
		State.RESULT:
			_draw_play()
			_draw_result()


func _draw_title() -> void:
	_txt("불길 속으로", Vector2(0, 250), 52, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_txt("문을 열면 불이 깨어난다", Vector2(0, 318), 24, C_FIRE_HI, HORIZONTAL_ALIGNMENT_CENTER, W)
	_txt("닫으면 불이 굶는다", Vector2(0, 352), 24, C_EMBER, HORIZONTAL_ALIGNMENT_CENTER, W)
	# 닫힌 문 뒤의 숨죽은 불 / 열린 문 뒤의 불 — 게임 안과 같은 모양
	for side in 2:
		var o := Vector2(58 + side * 232, 440)
		draw_rect(Rect2(o, Vector2(4 * CELL, CELL)).grow(6), C_WALL)
		draw_rect(Rect2(o, Vector2(CELL, CELL)), Color("26323c"))
		_icon_me(Rect2(o, Vector2(CELL, CELL)), false)
		var dr := Rect2(o + Vector2(CELL, 0), Vector2(CELL, CELL))
		draw_rect(dr, Color("26323c"))
		if side == 0:
			draw_line(dr.get_center() - Vector2(0, 20), dr.get_center() + Vector2(0, 20), Color("c9a36a"), 6)
			for k in 3:
				var ph := fmod(clk * 0.8 + k * 0.33, 1.0)
				draw_circle(dr.get_center() - Vector2(6 + ph * 14, (k - 1) * 9), 2.5, Color(C_EMBER, 1.0 - ph))
		else:
			draw_line(dr.position + Vector2(22, 2), dr.position + Vector2(42, 2), Color("c9a36a"), 6)
		for k in 2:
			var r := Rect2(o + Vector2((2 + k) * CELL, 0), Vector2(CELL, CELL))
			draw_rect(r, Color("3a2c20"))
			if side == 0:
				draw_rect(r, Color(0, 0, 0, 0.35))
				_icon_ember(r)
			else:
				_icon_fire(r, k * 1.7, 1.0)
		_txt("닫힌 문 — 숨죽은 불" if side == 0 else "열린 문 — 되살아난 불", Vector2(o.x - 6, o.y + CELL + 30), 15, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 4 * CELL + 12)
	var a := 0.55 + 0.45 * sin(clk * 3.0)
	_txt("화면을 눌러 출동", Vector2(0, 640), 26, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, W)
	_txt("밀어서 걷기 · 문 쪽으로 밀면 문 열기", Vector2(0, 700), 16, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, W)


func _draw_play() -> void:
	_draw_top()
	var off := Vector2.ZERO
	if shake_t > 0.0:
		off = Vector2(sin(clk * 90.0), cos(clk * 70.0)) * shake_amp * minf(1.0, shake_t * 3.0)
	draw_set_transform(off, 0.0, Vector2.ONE)
	_draw_board()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_bottom()
	if not _fx_of("hurt").is_empty():
		var b := Color(C_WARN, 0.7)
		draw_rect(Rect2(0, 0, W, H), b, false, 14)


func _heart(c: Vector2, s: float, col: Color) -> void:
	draw_circle(c + Vector2(-s * 0.5, -s * 0.3), s * 0.55, col)
	draw_circle(c + Vector2(s * 0.5, -s * 0.3), s * 0.55, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.05), c + Vector2(s, -s * 0.05), c + Vector2(0, s)]), col)


func _draw_top() -> void:
	# 위 띠 한 줄: 체력, 공기, 물, 사람, 박자
	var hurt := not _fx_of("hurt").is_empty()
	for i in Rules.P_HP:
		var c := Vector2(20 + i * 22, 20)
		if i < hp:
			_heart(c, 8, C_WARN)
		else:
			_heart(c, 8, Color("3a2530"))
			draw_line(c + Vector2(-3, -6), c + Vector2(3, 6), C_BG, 2)      # 깨진 하트
		if hurt and i == hp:
			draw_arc(c, 12, 0, TAU, 16, C_TEXT, 2)
	var acol := C_TEXT
	if air < 0:
		acol = C_WARN
	elif air <= 20 and fmod(clk, 0.5) < 0.25:
		acol = C_WARN
	_txt("공기 %d" % air, Vector2(104, 26), 17, acol)
	draw_rect(Rect2(104, 31, 78, 4), Color("26323c"))
	draw_rect(Rect2(104, 31, 78 * clampf(air / float(Rules.TANK_AIR), 0.0, 1.0), 4), acol)
	_drop(Vector2(204, 20), 7, C_WATER)
	_txt("물 %d" % water, Vector2(216, 26), 17, C_TEXT if water > 0 else C_WARN)
	_txt("사람 %d/%d" % [saved, rules.victims.size()], Vector2(282, 26), 17, C_TEXT)
	# 박자 표시: 쓴 행동 수가 홀수이면(다음 행동에 불이 움직이면) 두 개 다 채워진다
	var odd := clock % 2 == 1
	var jump := 0.0
	for f in _fx_of("beat"):
		jump = 5.0 * sin(PI * f["t"] / f["d"])
	_txt("박자", Vector2(392, 26), 15, C_DIM)
	for i in 2:
		var c := Vector2(444 + i * 22, 20 - jump)
		if i == 0 or odd:
			draw_circle(c, 8, C_FIRE if odd else C_TEXT)
		else:
			draw_arc(c, 7, 0, TAU, 20, C_DIM, 2)
	_txt("%d" % beat, Vector2(486, 26), 15, C_DIM)


func _drop(c: Vector2, s: float, col: Color) -> void:
	draw_circle(c + Vector2(0, s * 0.3), s * 0.6, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.55, s * 0.15), c + Vector2(s * 0.55, s * 0.15), c + Vector2(0, -s)]), col)


func _passage_horizontal(c: int) -> bool:
	for d in [1, 3]:
		var n: int = rules.step(c, d)
		if n >= 0 and rules.kind[n] != "#" and rules.kind[n] != "V":
			return true
	return false


func _draw_board() -> void:
	var beat_pulse := 0.0
	for f in _fx_of("beat"):
		beat_pulse = sin(PI * f["t"] / f["d"])
	var smoke: Array = rules.smoke_map()
	# 1. 칸 바닥
	for c in Rules.N:
		var r := _cell_rect(c)
		var k: String = rules.kind[c]
		if k == "#":
			draw_rect(r, C_WALL)
			draw_rect(Rect2(r.position, Vector2(CELL, 3)), C_WALL_HI)
		elif k == "V":
			draw_rect(r, C_WALL)
			draw_rect(r.grow(-7), Color("3d6a85"))
			draw_line(r.position + Vector2(10, 10), r.position + Vector2(24, 26), C_TEXT, 1.5)
			draw_line(r.position + Vector2(24, 26), r.position + Vector2(18, 36), C_TEXT, 1.5)
			draw_line(r.position + Vector2(24, 26), r.position + Vector2(36, 20), C_TEXT, 1.5)
		elif k == "E":
			draw_rect(r, Color("2f6b4a"))
			_txt("출구", Vector2(r.position.x, r.position.y + 28), 14, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, CELL)
		elif k == "D":
			draw_rect(r, Color("26323c"))
		else:
			_draw_floor(c, r)
	# 2. 방: 연기, 숨죽음, 테두리, 공기·가스·버팀
	for room in rules.rooms:
		_draw_room(room, smoke[room["id"]])
	# 3. 칸 위의 것: 열, 불, 예보
	for c in Rules.N:
		if rules.kind[c] != ".":
			continue
		var r := _cell_rect(c)
		var fire: int = rules.fire[c]
		var heat: int = rules.heat[c]
		if rules.rubble[c]:
			_icon_rubble(r)
		elif rules.ash[c]:
			_icon_ash(r)
		if heat < 0:
			_icon_wet(r, -heat)
		if fire == 1:
			_icon_fire(r, c * 1.3, 1.0 + 0.25 * beat_pulse)
		elif fire == 2:
			_icon_ember(r)
		elif heat > 0 and rules.fuel[c] > 0:
			var jit := Vector2.ZERO
			if heat == rules.T[c] - 1 or heat >= rules.T[c]:
				jit = Vector2(sin(clk * 40.0 + c), cos(clk * 33.0 + c)) * 1.2     # 한 박자 남았다: 떨림
			var pop := 1.0
			for f in _fx_of("crack"):
				if f["c"] == c:
					pop = 1.0 + 0.8 * (1.0 - f["t"] / f["d"])
			_icon_heat(Rect2(r.position + jit, r.size), heat, pop)
	for p in forecast:
		var r := _cell_rect(p.y * Rules.W + p.x)
		draw_circle(r.position + Vector2(34, 11), 9, C_WARN)
		_txt("!", Vector2(r.position.x + 24, r.position.y + 18), 18, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 20)
	# 4. 문과 징후
	for d in rules.door:
		_draw_door(d)
	# 5. 미리보기(방향 대기 중)
	if mode == "water" and state == State.PLAY:
		for dir in 4:
			if not rules.legal("S" + DIRS[dir]):
				continue
			for c in rules.spray_cells(dir):
				draw_rect(_cell_rect(c).grow(-4), Color(C_WATER, 0.9), false, 2)
	elif mode == "close" and state == State.PLAY:
		for dir in 4:
			if rules.legal("C" + DIRS[dir]):
				_preview_close(rules.step(rules.pos, dir))
	# 6. 사람, 소방관
	for i in rules.victims.size():
		_draw_victim(i)
	_draw_me()
	# 7. 연출
	for f in _fx_of("flash"):
		draw_rect(_cell_rect(f["c"]), Color(1, 1, 1, 0.85 * (1.0 - f["t"] / f["d"])))
	for f in _fx_of("spray"):
		var p := float(f["t"]) / float(f["d"])
		var from := _center(rules.pos)
		for c in f["cells"]:
			var to := _center(c)
			draw_line(from, to, Color(C_WATER, 0.9 * (1.0 - p)), 8)
			for k in 3:
				draw_circle(to + Vector2((k - 1) * 9, -6 - p * 14 - k * 3), 4.0 * (1.0 - p) + 1.0, Color(1, 1, 1, 0.6 * (1.0 - p)))      # 김
	for f in _fx_of("burst"):
		var p := float(f["t"]) / float(f["d"])
		for c in f["cells"]:
			var r := _cell_rect(c)
			draw_rect(r, Color(C_FIRE_HI, 0.85 * (1.0 - p)))
			_icon_fire(r, c * 0.7, 1.3)
	for f in fx:
		if f["k"] == "burst" and f["t"] < 0.0:
			for c in f["cells"]:
				draw_rect(_cell_rect(c), Color(1, 1, 1, 0.25))          # 0.2초 멈춤: 지나갈 칸이 하얗게
	for f in _fx_of("label"):
		var p := float(f["t"]) / float(f["d"])
		var r := _cell_rect(f["c"])
		var x := clampf(r.position.x - 40, 4, W - 134)
		_txt(f["text"], Vector2(x, r.position.y - 4 - p * 22), 26, Color(f["col"], 1.0 - p * 0.6), HORIZONTAL_ALIGNMENT_CENTER, 130)


func _draw_floor(c: int, r: Rect2) -> void:
	var m: String = rules.mat[c]
	if rules.rubble[c]:
		draw_rect(r, Color("23262b"))
		return
	match m:
		"_":      # 타일: 격자
			draw_rect(r, Color("26323c"))
			draw_line(r.position + Vector2(22, 0), r.position + Vector2(22, 44), Color("33424f"), 1)
			draw_line(r.position + Vector2(0, 22), r.position + Vector2(44, 22), Color("33424f"), 1)
		"~":      # 카펫: 점
			draw_rect(r, Color("2f2c48"))
			for i in 3:
				for j in 3:
					draw_circle(r.position + Vector2(8 + i * 14, 8 + j * 14), 1.6, Color("4b4770"))
		"\"":     # 종이 더미: 겹친 사각형
			draw_rect(r, Color("3b3a30"))
			draw_rect(Rect2(r.position + Vector2(8, 16), Vector2(20, 16)), Color("8d8a70"), false, 1.5)
			draw_rect(Rect2(r.position + Vector2(14, 10), Vector2(20, 16)), Color("a8a585"), false, 1.5)
		"F":      # 가구: 굵은 테두리 블록(탄 뒤에는 재)
			draw_rect(r, Color("3a2c20"))
			if rules.furn[c]:
				draw_rect(r.grow(-5), Color("5a4630"))
				draw_rect(r.grow(-5), Color("8a6c48"), false, 4)
		_:        # 나무: 긴 널
			draw_rect(r, Color("3a2c20"))
			draw_line(r.position + Vector2(0, 15), r.position + Vector2(44, 15), Color("4c3a2a"), 1)
			draw_line(r.position + Vector2(0, 30), r.position + Vector2(44, 30), Color("4c3a2a"), 1)
	draw_rect(r, Color(0, 0, 0, 0.18), false, 1)


func _draw_room(room: Dictionary, smoky: bool) -> void:
	var rid: int = room["id"]
	var cells: Array = room["cells"]
	if cells.is_empty():
		return
	if room["collapsed"]:
		return
	var dim := 0.0
	if room["smolder"]:
		dim = 0.42
	for f in _fx_of("dim"):
		if f["room"] == rid:
			dim = 0.42 * f["t"] / f["d"]
	for c in cells:
		var r := _cell_rect(c)
		if dim > 0.0:
			draw_rect(r, Color(0, 0, 0, dim))
		if smoky:
			# 연기: 반투명 회색 줄무늬
			for k in 3:
				var y := r.position.y + 6 + k * 14 + fmod(clk * 4.0, 14.0) * 0.0
				draw_line(Vector2(r.position.x + 2, y + 6), Vector2(r.position.x + 42, y), Color(0.75, 0.78, 0.82, 0.24), 3)
	if rid == 0:
		return
	# 방 테두리: 밀폐면 굵게
	var is_sealed: bool = rules.sealed(room)
	var col := Color("c9d3df") if is_sealed else Color("5c6a7a")
	var wd := 4.0 if is_sealed else 1.5
	if room["hp"] <= Rules.COLLAPSE_WARN:
		col = C_WARN
	for c in cells:
		var r := _cell_rect(c)
		for d in 4:
			var n: int = rules.step(c, d)
			if n >= 0 and rules.room[n] == rid:
				continue
			var a := r.position
			var b := r.position
			match d:
				0: b += Vector2(CELL, 0)
				1:
					a += Vector2(CELL, 0)
					b += Vector2(CELL, CELL)
				2:
					a += Vector2(0, CELL)
					b += Vector2(CELL, CELL)
				3: b += Vector2(0, CELL)
			draw_line(a, b, col, wd)
	# 방 구석: 공기 눈금 / 가스 / 버팀
	var r0 := _cell_rect(_label_cell(room))
	var label := "공기 %d/%d" % [room["air"], room["full"]]
	if room["vent"]:
		label = "창 열림"
	var lw := 58.0
	draw_rect(Rect2(r0.position + Vector2(2, 2), Vector2(lw, 15)), Color(0, 0, 0, 0.55))
	_txt(label, Vector2(r0.position.x + 4, r0.position.y + 14), 11, C_TEXT)
	if not room["vent"]:
		draw_rect(Rect2(r0.position + Vector2(2, 17), Vector2(lw, 3)), Color("26323c"))
		draw_rect(Rect2(r0.position + Vector2(2, 17), Vector2(lw * clampf(float(room["air"]) / maxf(1.0, float(room["full"])), 0.0, 1.0), 3)), C_WATER)
	if room["smolder"]:
		var gcol := C_WARN if room["gas"] >= Rules.GAS_BURST else C_FIRE_HI
		draw_rect(Rect2(r0.position + Vector2(2, 22), Vector2(lw, 17)), Color(0, 0, 0, 0.6))
		_txt("가스 %d" % room["gas"], Vector2(r0.position.x + 4, r0.position.y + 36), 13, gcol)
	if room["hp"] <= Rules.COLLAPSE_WARN:
		var rl := _cell_rect(cells[cells.size() - 1])
		draw_rect(Rect2(rl.position + Vector2(-16, 26), Vector2(58, 16)), Color(0, 0, 0, 0.6))
		_txt("붕괴 %d" % room["hp"], Vector2(rl.position.x - 14, rl.position.y + 39), 13, C_WARN)
		for k in 4:
			var ph := fmod(clk * 1.5 + k * 0.25, 1.0)
			draw_circle(Vector2(r0.position.x + 20 + k * 30, r0.position.y + ph * 30), 2, Color(0.8, 0.8, 0.8, 1.0 - ph))      # 먼지


## 방의 공기 표시를 둘 칸: 사람이나 소방관이 가리지 않는 가장 앞 칸.
func _label_cell(room: Dictionary) -> int:
	for c in room["cells"]:
		var busy: bool = c == rules.pos
		for v in rules.victims:
			if v["cell"] == c and v["state"] != "saved" and v["state"] != "carried":
				busy = true
		if not busy:
			return c
	return room["cells"][0]


func _draw_door(d: int) -> void:
	var dr: Dictionary = rules.door[d]
	var r := _cell_rect(d)
	var horiz := _passage_horizontal(d)
	var open_amt := 1.0 if dr["open"] else 0.0
	for f in _fx_of("door"):
		if f["c"] == d:
			var p := float(f["t"]) / float(f["d"])
			open_amt = p if f["opening"] else 1.0 - p
	var sign: String = rules.door_sign(d)
	var shake := Vector2.ZERO
	if sign == "backdraft":
		shake = Vector2(sin(clk * 60.0), cos(clk * 47.0)) * 1.6
	if dr["burnt"]:
		# 탄 문: 그을린 문틀만
		var a := r.position + (Vector2(22, 2) if horiz else Vector2(2, 22))
		var b := r.position + (Vector2(22, 42) if horiz else Vector2(42, 22))
		draw_circle(a, 4, Color("111111"))
		draw_circle(b, 4, Color("111111"))
		draw_rect(r.grow(-14), Color(0, 0, 0, 0.3))
	else:
		var hinge := r.position + (Vector2(22, 2) if horiz else Vector2(2, 22)) + shake
		var closed_dir := Vector2(0, 1) if horiz else Vector2(1, 0)
		var open_dir := Vector2(1, 0) if horiz else Vector2(0, 1)
		var dirv := closed_dir.lerp(open_dir, open_amt).normalized()
		var col := Color("c9a36a")
		if sign == "burning":
			col = Color("ff5a3a").lerp(Color("ffb38a"), 0.5 + 0.5 * sin(clk * 6.0))        # 달아오른 문
			draw_rect(r.grow(-2), Color(1.0, 0.3, 0.15, 0.22))
		draw_line(hinge, hinge + dirv * lerpf(40.0, 20.0, open_amt), col, 7)       # 열린 문짝은 칸 밖으로 나가지 않게 접힌다
		draw_circle(hinge, 4, Color("7a6038"))
		if not dr["open"] and dr["hp"] < Rules.DOOR_HP:
			_txt("%d" % dr["hp"], Vector2(r.position.x + 26, r.position.y + 40), 12, C_WARN)
	if sign != "smolder" and sign != "backdraft":
		return
	# 징후의 점: 위험한 방에서 바깥으로(숨죽음) / 방 안쪽으로(역류)
	var rid: int = rules.sign_room(d)
	var inward := Vector2.ZERO
	for k in 4:
		var n: int = rules.step(d, k)
		if n >= 0 and rules.room[n] == rid:
			inward = DIRV[k]
			break
	var side := Vector2(-inward.y, inward.x)
	for k in 3:
		var ph := fmod(clk * (0.7 if sign == "smolder" else 1.6) + k * 0.33, 1.0)
		var along := (-inward) * (6.0 + ph * 16.0) if sign == "smolder" else (-inward) * (22.0 - ph * 20.0)
		var p := r.get_center() + along + side * float(k - 1) * 9.0
		draw_circle(p, 3.0, Color(C_EMBER if sign == "smolder" else C_WARN, 1.0 - ph * 0.7))
	if sign == "backdraft":
		# 화염이 지나갈 칸(문 칸 + 문 밖 3칸)에 빗금
		var strong := 0.55
		for room in rules.rooms:
			if room["id"] == rid and room["front"] == 0:
				strong = 0.95          # 흡입 박자: 빗금이 진해진다
		for c in rules.jet_from(rules.rooms[rid], d):
			var jr := _cell_rect(c)
			for k in 4:
				var o := 11.0 * k
				draw_line(jr.position + Vector2(o, 0), jr.position + Vector2(0, o), Color(C_WARN, strong), 2)
				draw_line(jr.position + Vector2(CELL, o), jr.position + Vector2(o, CELL), Color(C_WARN, strong), 2)


func _preview_close(d: int) -> void:
	draw_rect(_cell_rect(d).grow(-1), C_TEXT, false, 4)
	# 닫으면 밀폐되는 방의 윤곽
	for rid in [rules.door[d]["a"], rules.door[d]["b"]]:
		if rid <= 0:
			continue
		var room: Dictionary = rules.rooms[rid]
		if room["vent"] or room["collapsed"]:
			continue
		var others_closed := true
		for o in room["doors"]:
			if o != d and rules.door[o]["open"]:
				others_closed = false
		if others_closed:
			for c in room["cells"]:
				draw_rect(_cell_rect(c).grow(-3), Color(C_TEXT, 0.5), false, 1.5)


func _draw_victim(i: int) -> void:
	var v: Dictionary = rules.victims[i]
	if v["state"] == "carried" or v["state"] == "saved":
		return
	var r := _cell_rect(v["cell"])
	var c := r.get_center() + Vector2(0, -5)
	if v["state"] == "dead":
		draw_line(c + Vector2(-9, -9), c + Vector2(9, 9), Color("7c838c"), 4)
		draw_line(c + Vector2(9, -9), c + Vector2(-9, 9), Color("7c838c"), 4)
		return
	var breath := maxi(0, int(v["hp"]))
	var blink := breath <= 3 and fmod(clk, 0.4) < 0.2
	for f in _fx_of("vblink"):
		if f["i"] == i:
			blink = fmod(f["t"], 0.1) < 0.05
	draw_circle(c, 11, Color("101820"))
	draw_circle(c, 9, C_WARN if blink else Color.WHITE)
	if breath <= 3:
		_txt("콜록", Vector2(r.position.x + 22, r.position.y + 12), 10, C_WARN)
	# 숨 눈금 12칸(3칸씩 4덩이)
	for k in Rules.V_HP:
		var x := r.position.x + 2 + k * 3 + (k / 3) * 2
		draw_rect(Rect2(x, r.position.y + 34, 2, 8), Color.WHITE if k < breath else Color("3a424c"))


func _draw_me() -> void:
	var c := _center(rules.pos)
	if slide_t < 1.0:
		c = slide_from.lerp(c, slide_t)
	for f in _fx_of("reject"):
		c.x += sin(f["t"] / f["d"] * TAU * 2.0) * 5.0
		if f["dir"] >= 0:
			# 막힌 쪽 칸 경계에 짧은 × (흔들림만으로는 한 장면에서 잘 안 보인다)
			var m: Vector2 = _center(rules.pos) + DIRV[f["dir"]] * 22.0
			draw_line(m + Vector2(-7, -7), m + Vector2(7, 7), C_WARN, 3)
			draw_line(m + Vector2(7, -7), m + Vector2(-7, 7), C_WARN, 3)
	var r := Rect2(c - Vector2(22, 22), Vector2(CELL, CELL))
	var white := not _fx_of("hurt").is_empty()
	_icon_me(r, white)
	if rules.carry >= 0:
		var s := 1.0
		for f in _fx_of("pop"):
			s = 1.0 + 0.6 * (1.0 - f["t"] / f["d"])
		draw_circle(c + Vector2(10, -12), 8.0 * s, Color("101820"))
		draw_circle(c + Vector2(10, -12), 6.5 * s, Color.WHITE)


# ---------------------------------------------------------------- 아이콘 (보드·타이틀·범례가 같은 모양을 쓴다)

func _icon_me(r: Rect2, white: bool) -> void:
	var c := r.get_center()
	draw_circle(c, 15, Color("101820"))
	draw_circle(c, 13, Color.WHITE if white else C_ME)
	draw_rect(Rect2(c + Vector2(-12, -5), Vector2(24, 5)), Color("b8322a"))      # 헬멧 띠


func _icon_fire(r: Rect2, seed: float, scale: float) -> void:
	var base := r.position + Vector2(22, 40)
	for k in 3:
		var w := 9.0 * scale
		var x := (k - 1) * 11.0
		var h := (20.0 + 7.0 * sin(clk * 9.0 + seed + k * 2.1)) * scale * (1.15 if k == 1 else 0.85)
		draw_colored_polygon(PackedVector2Array([base + Vector2(x - w, 0), base + Vector2(x + w, 0), base + Vector2(x + sin(clk * 7.0 + seed + k) * 3.0, -h)]), C_FIRE)
	var h2 := (13.0 + 4.0 * sin(clk * 11.0 + seed)) * scale
	draw_colored_polygon(PackedVector2Array([base + Vector2(-7, 0), base + Vector2(7, 0), base + Vector2(0, -h2)]), C_FIRE_HI)


func _icon_ember(r: Rect2) -> void:
	var c := r.get_center()
	draw_arc(c, 10, 0, TAU, 24, C_EMBER, 3)
	draw_circle(c, 3, Color(C_FIRE, 0.5 + 0.3 * sin(clk * 2.0 + r.position.x)))


func _icon_ash(r: Rect2) -> void:
	for k in 5:
		draw_circle(r.position + Vector2(9 + (k * 17) % 28, 12 + (k * 11) % 24), 2.2, Color("0c0f13"))


func _icon_rubble(r: Rect2) -> void:
	var col := Color("7a7f87")
	draw_line(r.position + Vector2(6, 10), r.position + Vector2(38, 30), col, 4)
	draw_line(r.position + Vector2(36, 8), r.position + Vector2(10, 36), col, 4)
	draw_line(r.position + Vector2(4, 26), r.position + Vector2(30, 40), Color("555a61"), 3)


func _icon_wet(r: Rect2, n: int) -> void:
	for k in mini(n, 2):
		_drop(r.position + Vector2(10 + k * 12, 34), 5, C_WATER)


func _icon_heat(r: Rect2, n: int, pop: float) -> void:
	# 열 눈금: 왼쪽 위 모서리에서 뻗는 금의 개수
	for k in mini(n, 4):
		var a := r.position + Vector2(5 + k * 9, 4)
		var b := a + Vector2(4, 9) * pop
		var c := b + Vector2(-4, 8) * pop
		draw_line(a, b, Color("101820"), 5)
		draw_line(b, c, Color("101820"), 5)
		draw_line(a, b, C_FIRE_HI, 2.5)
		draw_line(b, c, C_FIRE_HI, 2.5)


func _draw_button(i: int, label: String, sub: String, enabled: bool, active: bool) -> void:
	var r := _button_rect(i)
	for f in _fx_of("btn"):
		if f["id"] == BTN_IDS[i]:
			r.position.x += sin(f["t"] / f["d"] * TAU * 2.0) * 5.0
	var bg := Color("21405a") if enabled else Color("141d28")
	if active:
		bg = Color("2f78b8")
	draw_rect(r, bg)
	draw_rect(r, Color("5c7fa0") if enabled else Color("2a3644"), false, 2)
	var col := C_TEXT if enabled else Color("56606d")
	_txt(label, Vector2(r.position.x, r.position.y + 48), 21, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sub != "":
		_txt(sub, Vector2(r.position.x, r.position.y + 76), 14, col if active else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_bottom() -> void:
	var playing := state == State.PLAY
	_txt("%d/%d %s" % [building_index + 1, buildings.size(), rules.title], Vector2(28, 640), 17, C_TEXT)
	var hint := "아무 곳이나 밀어서 걷기"
	if mode == "water":
		hint = "물을 뿌릴 방향으로 미세요"
	elif mode == "close":
		hint = "닫을 문 쪽으로 미세요"
	_txt(hint, Vector2(200, 640), 16, C_FIRE_HI if mode != "" else C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 312)
	if playing and rules.legal("Q"):
		draw_rect(RETREAT_RECT, Color("2f6b4a"))
		draw_rect(RETREAT_RECT, C_OK, false, 2)
		_txt("철수 (출동 끝)", Vector2(RETREAT_RECT.position.x, RETREAT_RECT.position.y + 28), 19, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, RETREAT_RECT.size.x)
	var can_water: bool = rules.water > 0 and rules.carry < 0
	_draw_button(0, "물", "남은 물 %d" % rules.water if mode != "water" else "다시 누르면 취소", can_water, mode == "water")
	_draw_button(1, "문 닫기", "" if mode != "close" else "다시 누르면 취소", not _closable().is_empty(), mode == "close")
	var can_drop: bool = rules.legal("X")
	_draw_button(2, "내려놓기" if rules.carry >= 0 else "업기", "", rules.legal("P") or can_drop, false)
	_draw_button(3, "기다리기", "한 행동", true, false)
	# 범례: 화면만 보고 읽을 수 있게 같은 모양으로
	var y := 822.0
	var items := [["fire", "불"], ["ember", "숨죽은 불"], ["heat", "열(금 3개면 나무가 붙는다)"]]
	var x := 16.0
	for it in items:
		var r := Rect2(x, y, CELL, CELL)
		draw_set_transform(Vector2(x, y) * 0.4, 0.0, Vector2(0.6, 0.6))
		match it[0]:
			"fire": _icon_fire(r, 0.0, 1.0)
			"ember": _icon_ember(r)
			"heat": _icon_heat(Rect2(r.position + Vector2(8, 10), r.size), 3, 1.6)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_txt(it[1], Vector2(x + 30, y + 22), 14, C_DIM)
		x += 34 + font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14
	draw_circle(Vector2(28, y + 50), 8, C_WARN)
	_txt("!", Vector2(18, y + 57), 16, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 20)
	_txt("다음 박자에 붙는 칸", Vector2(46, y + 56), 14, C_DIM)
	for k in 3:
		draw_circle(Vector2(218 + k * 8, y + 50), 2.5, C_EMBER)
	_txt("문틈 점이 밖으로 = 숨죽은 방", Vector2(246, y + 56), 14, C_DIM)
	for k in 3:
		draw_circle(Vector2(22 + k * 8, y + 82), 2.5, C_WARN)
	for k in 3:
		draw_line(Vector2(50 + k * 7, y + 74), Vector2(44 + k * 7, y + 90), C_WARN, 2)
	_txt("점이 안으로 + 빗금 = 열면 역류(빗금 칸을 피할 것)", Vector2(76, y + 88), 14, C_DIM)
	_txt("행동 2번마다 불이 한 박자 움직인다 · 사람을 업으면 한 칸에 2행동", Vector2(0, y + 118), 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, W)


func _star(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + k * PI / 5
		pts.append(c + Vector2(cos(a), sin(a)) * (s if k % 2 == 0 else s * 0.45))
	draw_colored_polygon(pts, col)


func _draw_result() -> void:
	var fade := 1.0
	for f in _fx_of("result"):
		fade = f["t"] / f["d"]
	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.05, 0.09, 0.95 * fade))
	if fade < 1.0:
		return
	for i in 3:
		_star(Vector2(190 + i * 80, 250), 30, C_FIRE_HI if i < result_stars else Color("2a3644"))
	var title := "전원 구조!"
	if result_cause == "dead":
		title = "순직"
	elif result_cause == "limit":
		title = "시간 초과"
	elif result_stars == 2:
		title = "한 명을 남겼다"
	elif result_stars == 1:
		title = "일부 구조"
	elif result_stars == 0:
		title = "아무도 구하지 못했다"
	_txt(title, Vector2(0, 340), 40, C_WARN if result_cause == "dead" else C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, W)
	if result_cause == "dead":
		var why := {"fire": "불 위에 서 있었다", "backdraft": "역류에 맞았다", "collapse": "방이 무너졌다", "air": "공기가 떨어졌다"}
		_txt(why.get(rules.hurt_cause, ""), Vector2(0, 380), 20, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, W)
	_txt("구한 사람  %d / %d" % [saved, rules.victims.size()], Vector2(150, 450), 24, C_TEXT)
	_txt("쓴 행동  %d     쓴 물  %d" % [clock, water0 - water], Vector2(150, 492), 22, C_TEXT)
	_txt("남은 체력", Vector2(150, 534), 22, C_TEXT)
	for i in Rules.P_HP:
		_heart(Vector2(270 + i * 26, 526), 9, C_WARN if i < hp else Color("3a2530"))
	var last := building_index + 1 >= buildings.size()
	var a := 0.55 + 0.45 * sin(clk * 3.0)
	_txt("화면을 눌러 처음으로" if last else "화면을 눌러 다음 건물", Vector2(0, 640), 24, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, W)


# ---------------------------------------------------------------- 테스트 인터페이스 (FIRST_BUILD.md)

func debug_cell(p: Vector2i) -> Dictionary:
	var out := {"kind": "#", "fire": 0, "heat": 0, "fuel": 0, "ash": false, "rubble": false, "furn": false}
	if rules == null or p.x < 0 or p.x >= Rules.W or p.y < 0 or p.y >= Rules.H:
		return out
	var c := p.y * Rules.W + p.x
	out["kind"] = rules.kind[c]
	if rules.kind[c] == ".":
		out["fire"] = rules.fire[c]
		out["heat"] = rules.heat[c]
		out["fuel"] = rules.fuel[c]
		out["ash"] = rules.ash[c]
		out["rubble"] = rules.rubble[c]
		out["furn"] = rules.furn[c]
	return out


func debug_door(p: Vector2i) -> Dictionary:
	if rules == null:
		return {}
	var c := p.y * Rules.W + p.x
	if not rules.door.has(c):
		return {}
	var d: Dictionary = rules.door[c]
	return {"open": d["open"], "hp": maxi(0, int(d["hp"])), "burnt": d["burnt"], "sign": rules.door_sign(c)}


func debug_room(id: int) -> Dictionary:
	if rules == null or id < 0 or id >= rules.rooms.size():
		return {}
	var r: Dictionary = rules.rooms[id]
	return {"air": r["air"], "full": r["full"], "gas": r["gas"], "smolder": r["smolder"], "front": r["front"], "hp": maxi(0, int(r["hp"])),
		"collapsed": r["collapsed"], "sealed": rules.sealed(r), "smoke": rules.smoke_map()[id]}


func debug_tap(p: Vector2) -> void:
	_press(p)
	_release(p)


func debug_swipe(from: Vector2, to: Vector2) -> void:
	_press(from)
	_release(to)


func debug_press(id: String) -> void:
	_skip_fx()
	_button(id)


func debug_act(action: String) -> bool:
	return _do(action)


func debug_load(json_text: String) -> void:
	buildings = [json_text]
	custom = true
	_start_building(0)
