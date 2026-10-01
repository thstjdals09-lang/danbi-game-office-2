extends Node2D
## 메아리 발자국 — 상태, 입력, 그리기, 연출.
## 규칙은 scripts/rules.gd 가 계산하고, 여기서는 그 결과(events)를 화면에 재생한다.
## 기준: design/FIRST_BUILD.md (테스트 인터페이스), design/SCREENS.md (화면).

enum State { TITLE, PLAY, RESULT }

const Rules := preload("res://scripts/rules.gd")
const Content := preload("res://scripts/content.gd")

const W := 540.0
const H := 960.0
const CELL := 68.0
const BOARD := Vector2(32, 120)          # 보드 왼쪽 위(7×68 = 476px, y 120~596)
const SWIPE_MIN := 24.0                  # SCREENS.md: 24px 이상 밀어야 행동
const BTN_SLASH := Rect2(50, 700, 200, 96)
const BTN_WAIT := Rect2(290, 700, 200, 96)

# 한 턴 연출 시간표(초). 합이 0.9를 넘지 않는다.
const T_MOVE := 0.12                     # 플레이어 이동/베기
const T_ECHO := 0.14                     # 메아리 재생
const T_STOP := 0.08                     # 명중 히트스톱
const T_ENEMY := 0.26                    # 적 행동
const T_END := 0.20                      # 증원 등장, 여운
const T_SHAKE := 0.2
const T_POPUP := 0.7
const T_HURT := 0.3
const T_BANNER := 0.8

const C_BG := Color("0b1220")
const C_PANEL := Color("111c30")
const C_GRID := Color("2a3b57")
const C_WALL := Color("3d4f6e")
const C_TEXT := Color("edf4ff")
const C_MUTED := Color("8fa3bf")
const C_PLAYER := Color("ffffff")
const C_ECHO := Color("67d9eb")
const C_ENEMY := Color("f08a5d")
const C_DANGER := Color("f3c86a")
const C_HURT := Color("ff5d73")
const C_GOOD := Color("55d6a8")

# ---------------------------------------------------------------- 테스트 인터페이스 (FIRST_BUILD.md)

var state: int = State.TITLE
var floor_index := 0
var floor_count := 3
var kills := {"stomp": 0, "slash": 0, "friendly": 0}
var last_action := ""
var result_won := false

var turn: int:
	get:
		return rules.turn if rules != null else 0
var hp: int:
	get:
		return rules.hp if rules != null else Rules.HP_MAX
var player: Vector2i:
	get:
		return rules.player if rules != null else Vector2i(3, 6)
var echo_active: bool:
	get:
		return rules != null and rules.has_echo()
var echo_pos: Vector2i:
	get:
		return rules.echo_pos() if rules != null else Vector2i(-1, -1)
var enemies: Array:
	get:
		return rules.enemies if rules != null else []
var spawns_pending: int:
	get:
		return rules.spawns.size() if rules != null else 0
var footprints: Array:
	get:
		return rules.footprints() if rules != null else []

# ---------------------------------------------------------------- 내부 상태

var rules: RefCounted = null
var floors: Array = []
var floor_names: Array = []
var font: Font
var clock := 0.0

var slash_mode := false
var pressing := false
var press_pos := Vector2.ZERO
var drag_pos := Vector2.ZERO

var anim: Dictionary = {}                # 진행 중인 턴 연출 {"snap", "events", "t", "dur", ...}
var popups: Array = []                   # {"text", "pos", "t0", "color"}
var fragments: Array = []                # {"pos", "t0", "kind"}
var ripples: Array = []                  # {"pos", "t0"}
var hurt_t0 := -10.0
var shake_t0 := -10.0
var banner_t0 := -10.0
var banner_text := ""
var defeat_cause := ""
var reached_floor := 0


func _ready() -> void:
	font = load("res://assets/fonts/NotoSansKR-Medium.ttf")


func _process(delta: float) -> void:
	clock += delta
	if not anim.is_empty():
		anim["t"] += delta
		if anim["t"] >= anim["dur"]:
			anim = {}
	queue_redraw()


# ---------------------------------------------------------------- 입력 (실제 터치와 debug_* 가 같은 함수를 쓴다)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
	elif event is InputEventScreenDrag:
		_drag(event.position)


func _press(pos: Vector2) -> void:
	# FIRST_BUILD.md "연출 중 입력": 새로 누르면 연출을 즉시 끝내고 그 입력은 정상 처리한다
	_finish_anim()
	pressing = true
	press_pos = pos
	drag_pos = pos


func _drag(pos: Vector2) -> void:
	if pressing:
		drag_pos = pos


func _release(pos: Vector2) -> void:
	if not pressing:
		return
	pressing = false
	match state:
		State.TITLE, State.RESULT:
			_start_run(Content.FLOORS, Content.FLOOR_NAMES)
		State.PLAY:
			var act := _gesture_action(press_pos, pos)
			if act == "":
				if BTN_SLASH.has_point(press_pos) and BTN_SLASH.has_point(pos):
					slash_mode = not slash_mode
				elif BTN_WAIT.has_point(press_pos) and BTN_WAIT.has_point(pos):
					_do_action("W")
				return
			if _do_action(act) and Rules.is_slash(act):
				slash_mode = false


## 누른 곳과 뗀 곳으로 행동을 정한다. 24px 미만이면 ""(탭 또는 취소).
func _gesture_action(from: Vector2, to: Vector2) -> String:
	var d := to - from
	if d.length() < SWIPE_MIN:
		return ""
	var dir := ""
	if absf(d.x) > absf(d.y):
		dir = "R" if d.x > 0 else "L"
	else:
		dir = "D" if d.y > 0 else "U"
	return ("S" + dir) if slash_mode else dir


# ---------------------------------------------------------------- 런과 층

func _start_run(run_floors: Array, names: Array) -> void:
	floors = run_floors
	floor_names = names
	floor_count = floors.size()
	floor_index = 0
	kills = {"stomp": 0, "slash": 0, "friendly": 0}
	last_action = ""
	result_won = false
	defeat_cause = ""
	reached_floor = 0
	slash_mode = false
	anim = {}
	popups.clear()
	fragments.clear()
	ripples.clear()
	_load_floor(0, Rules.HP_MAX)
	state = State.PLAY
	_show_banner()


func _load_floor(index: int, start_hp: int) -> void:
	floor_index = index
	rules = Rules.new()
	rules.setup(floors[index], start_hp, kills)


func _show_banner() -> void:
	banner_t0 = clock
	var floor_name: String = floor_names[floor_index] if floor_index < floor_names.size() else ""
	banner_text = "%d층" % (floor_index + 1) + ((" 「%s」" % floor_name) if floor_name != "" else "")


## 행동 하나를 확정한다. 규칙 상태는 여기서 즉시 끝까지 갱신되고, 연출은 그 뒤를 따라간다.
func _do_action(act: String) -> bool:
	if state != State.PLAY or rules == null:
		return false
	if not rules.can_act(act):
		shake_t0 = clock
		return false
	_finish_anim()
	var snap := _snapshot()
	var events: Array = rules.step(act)
	last_action = act
	_begin_anim(snap, events)

	match rules.outcome:
		"clear":
			reached_floor = floor_index + 1
			if floor_index + 1 >= floor_count:
				result_won = true
				state = State.RESULT
			else:
				_load_floor(floor_index + 1, mini(Rules.HP_MAX, rules.hp + 1))
				anim["banner_after"] = true
		"dead", "timeout":
			reached_floor = floor_index
			result_won = false
			state = State.RESULT
			if rules.outcome == "timeout":
				defeat_cause = "60턴 안에 층을 비우지 못함"
			else:
				var by := ""
				for e in events:
					if e["type"] == "hurt":
						by = e["by"]
				defeat_cause = "%d턴, %s" % [rules.turn, "궁수의 화살" if by == "A" else "졸개의 치기"]
	return true


# ---------------------------------------------------------------- 연출 데이터

func _snapshot() -> Dictionary:
	var es: Array = []
	for e in rules.enemies:
		es.append(e.duplicate())
	return {
		"walls": rules.walls,
		"player": rules.player,
		"echo": rules.has_echo(),
		"echo_pos": rules.echo_pos(),
		"enemies": es,
		"hp": rules.hp,
		"turn": rules.turn,
		"floor_index": floor_index,
		"danger": rules.danger_cells(),
		"spawns": rules.spawns.duplicate(true),
	}


func _begin_anim(snap: Dictionary, events: Array) -> void:
	var echo_kill := false
	for e in events:
		if e["type"] == "kill" and e["src"] != "friendly":
			echo_kill = true
	var t_echo := T_MOVE
	var t_enemy := t_echo + T_ECHO + (T_STOP if echo_kill else 0.0)
	var t_end := t_enemy + T_ENEMY
	anim = {"snap": snap, "events": events, "t": 0.0, "dur": t_end + T_END,
		"t_echo": t_echo, "t_enemy": t_enemy, "t_end": t_end, "post": rules, "banner_after": false}
	# 글자·조각·파문은 시계 기준으로 따로 흐른다(연출을 넘겨도 잠깐 남는다)
	for e in events:
		match e["type"]:
			"kill":
				var friendly: bool = e["src"] == "friendly"
				var at: float = clock + (t_enemy + T_ENEMY * 0.6 if friendly else t_echo + T_ECHO)
				fragments.append({"pos": _cell_center(e["pos"]), "t0": at, "kind": e["kind"]})
				var label := "오사!" if friendly else ("밟기!" if e["src"] == "stomp" else "베기!")
				popups.append({"text": label, "pos": _cell_center(e["pos"]), "t0": at, "color": C_GOOD})
			"block":
				ripples.append({"pos": _cell_center(e["pos"]), "t0": clock + t_enemy + T_ENEMY * 0.6})
				popups.append({"text": "막음", "pos": _cell_center(e["pos"]), "t0": clock + t_enemy + T_ENEMY * 0.6, "color": C_ECHO})
			"hurt":
				hurt_t0 = clock + t_enemy + T_ENEMY * 0.6


func _finish_anim() -> void:
	if anim.is_empty():
		return
	if anim.get("banner_after", false):
		_show_banner()
	anim = {}
	# 아직 시작하지 않은 글자·조각은 지금 바로 보이게 당긴다
	for list in [popups, fragments, ripples]:
		for p in list:
			if p["t0"] > clock:
				p["t0"] = clock
	if hurt_t0 > clock:
		hurt_t0 = clock


func _cell_center(c: Vector2i) -> Vector2:
	return BOARD + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(BOARD + Vector2(c) * CELL, Vector2(CELL, CELL))


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), C_BG)
	match state:
		State.TITLE:
			_draw_title()
		State.PLAY:
			_draw_play()
		State.RESULT:
			if anim.is_empty():
				_draw_result()
			else:
				_draw_play()
	_draw_hurt_border()


func _text(s: String, y: float, size: int, color: Color, x := 0.0, width := W, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	draw_string(font, Vector2(x, y), s, align, width, size, color)


func _draw_title() -> void:
	_text("메아리 발자국", 300, 46, C_TEXT)
	_text("지금의 한 걸음이", 366, 22, C_MUTED)
	_text("3턴 뒤의 칼이 된다", 396, 22, C_MUTED)
	# 게임 안과 같은 모양: 플레이어 원 뒤로 발자국 ③②①과 메아리
	var y := 500.0
	_draw_echo(Vector2(120, y), 1.0)
	_draw_footprint(Vector2(205, y), 1, "", true)
	_draw_footprint(Vector2(275, y), 2, "", true)
	_draw_footprint(Vector2(345, y), 3, "", true)
	_draw_player(Vector2(420, y), false, false)
	_text("메아리", 548, 14, C_ECHO, 70, 100)
	_text("나", 548, 14, C_TEXT, 370, 100)
	_text("화면을 눌러 시작", 680, 24, C_TEXT)


func _draw_result() -> void:
	var title := "런 승리!" if result_won else ("메아리가 무너졌다 (60턴)" if rules != null and rules.outcome == "timeout" else "쓰러졌다")
	_text(title, 300, 40, C_GOOD if result_won else C_HURT)
	_text("도달  %d / %d층" % [reached_floor, floor_count], 400, 24, C_TEXT)
	_text("처치  밟기 %d · 베기 %d · 오사 %d" % [kills["stomp"], kills["slash"], kills["friendly"]], 444, 20, C_TEXT)
	_text("남은 체력", 500, 18, C_MUTED)
	_draw_hearts(Vector2(W / 2 - 2 * 34, 532), maxi(hp, 0))
	if not result_won and defeat_cause != "":
		_text(defeat_cause, 600, 18, C_DANGER)
	_text("화면을 눌러 다시", 720, 24, C_TEXT)


func _draw_play() -> void:
	var animating := not anim.is_empty()
	var view := _anim_view() if animating else _static_view()

	# 위 띠
	_text("%d/%d층" % [view["floor_index"] + 1, floor_count], 64, 22, C_TEXT, 28, 140, HORIZONTAL_ALIGNMENT_LEFT)
	_text("턴 %d/%d" % [view["turn"], Rules.TURN_LIMIT], 64, 22, C_MUTED, 170, 150, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_hearts(Vector2(W - 28 - 5 * 30 + 15, 56), view["hp"])

	# 보드
	draw_rect(Rect2(BOARD, Vector2(CELL, CELL) * Rules.N), C_PANEL)
	for i in Rules.N + 1:
		draw_line(BOARD + Vector2(i * CELL, 0), BOARD + Vector2(i * CELL, Rules.N * CELL), C_GRID, 1.0)
		draw_line(BOARD + Vector2(0, i * CELL), BOARD + Vector2(Rules.N * CELL, i * CELL), C_GRID, 1.0)
	for w in view["walls"]:
		draw_rect(_cell_rect(w).grow(-2), C_WALL)

	# 조준 사선(빗금), 위험 칸 "!"
	for e in view["enemies"]:
		if view["show_intents"] and e["intent"] == "aim" and e["alpha"] > 0.5:
			_draw_aim_ray(e["cell"], e["dir"], view)
	if view["show_intents"]:
		for c in view["danger"]:
			var r := _cell_rect(c)
			draw_string(font, r.position + Vector2(CELL - 20, 22), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_DANGER)

	# 증원 예고
	for s in view["spawns"]:
		var left: int = maxi(1, int(s[0]) - view["turn"])
		_draw_dashed_circle(_cell_center(s[2]), 22, Color(C_ENEMY, 0.8), 2.0)
		draw_string(font, _cell_center(s[2]) + Vector2(-20, 7), str(left), HORIZONTAL_ALIGNMENT_CENTER, 40, 18, C_ENEMY)

	# 적 의도(이동 화살표, 치기 주먹)와 적
	for e in view["enemies"]:
		if e["alpha"] <= 0.0:
			continue
		if view["show_intents"]:
			if e["intent"] == "move":
				_draw_arrow(_cell_center(e["cell"]), _cell_center(e["cell"] + e["dir"]), Color(C_ENEMY, 0.9))
			elif e["intent"] == "hit":
				_draw_fist(e["cell"] + e["dir"])
		_draw_enemy(e["pos"], e["kind"], e["dir"] if e["intent"] == "aim" else Vector2i(0, 1), e["alpha"])

	# 화살
	for s in view["shots"]:
		draw_line(s["from"], s["to"], C_DANGER, 3.0)
		_draw_arrow_head(s["to"], (s["to"] - s["from"]).normalized(), C_DANGER)

	# 메아리, 플레이어
	if view["echo_alpha"] > 0.0:
		_draw_echo(view["echo_px"], view["echo_alpha"])
	if view.has("echo_slash"):
		draw_line(view["echo_slash"][0], view["echo_slash"][1], C_ECHO, 5.0)
	var shake := 0.0
	if clock - shake_t0 < T_SHAKE:
		shake = sin((clock - shake_t0) * 60.0) * 5.0
	_draw_player(view["player_px"] + Vector2(shake, 0), view["hp"] <= 1, clock - hurt_t0 >= 0.0 and clock - hurt_t0 < T_HURT)
	if view.has("slash_line"):
		draw_line(view["slash_line"][0], view["slash_line"][1], C_PLAYER, 4.0)

	# 발자국 ①②③ (플레이어·메아리 위에 그려 숫자가 가리지 않게)
	var stack: Dictionary = {}
	for f in view["footprints"]:
		var n: int = stack.get(f["pos"], 0)
		stack[f["pos"]] = n + 1
		var offset: Vector2 = [Vector2(16, 16), Vector2(44, 16), Vector2(16, 44)][mini(n, 2)]
		_draw_footprint(_cell_rect(f["pos"]).position + offset, f["in"], f["act"], false)

	_draw_preview()
	_draw_effects()

	# 아래 띠, 버튼, 안내
	_text("처치  밟기 %d · 베기 %d · 오사 %d" % [kills["stomp"], kills["slash"], kills["friendly"]], 640, 18, C_MUTED)
	_draw_button(BTN_SLASH, "베기 ▶ 방향을 미세요" if slash_mode else "베기", slash_mode)
	_draw_button(BTN_WAIT, "대기", false)
	_text("베기를 켜고 밀면 그 방향을 벱니다" if slash_mode else "아무 곳이나 밀어서 이동", 850, 18, C_MUTED)

	# 층 안내
	var bt := clock - banner_t0
	if bt >= 0.0 and bt < T_BANNER and not animating:
		var a := 1.0 - bt / T_BANNER
		draw_rect(Rect2(0, 318, W, 84), Color(0, 0, 0, 0.55 * a))
		_text(banner_text, 374, 34, Color(C_TEXT, a))


## 연출이 없을 때: 규칙의 현재 상태 그대로
func _static_view() -> Dictionary:
	var es: Array = []
	for e in rules.enemies:
		es.append({"kind": e["kind"], "cell": e["pos"], "pos": _cell_center(e["pos"]), "intent": e["intent"], "dir": e["dir"], "alpha": 1.0})
	return {
		"floor_index": floor_index, "turn": rules.turn, "hp": rules.hp, "walls": rules.walls.keys(),
		"enemies": es, "show_intents": true, "danger": rules.danger_cells().keys(), "spawns": rules.spawns,
		"footprints": rules.footprints(), "shots": [],
		"echo_alpha": 0.55 if rules.has_echo() else 0.0, "echo_px": _cell_center(rules.echo_pos()),
		"player_px": _cell_center(rules.player), "player_cell": rules.player,
		"blocked_echo": rules.next_echo_pos().x >= 0, "echo_cell": rules.next_echo_pos(),
	}


## 연출 중: 행동 직전 상태(snap)에서 events 를 시간표대로 재생한 모습
func _anim_view() -> Dictionary:
	var snap: Dictionary = anim["snap"]
	var events: Array = anim["events"]
	var post: RefCounted = anim["post"]
	var t: float = anim["t"]
	var t_echo: float = anim["t_echo"]
	var t_enemy: float = anim["t_enemy"]
	var t_end: float = anim["t_end"]
	var k_move := clampf(t / T_MOVE, 0.0, 1.0)
	var k_echo := clampf((t - t_echo) / T_ECHO, 0.0, 1.0)
	var k_enemy := clampf((t - t_enemy) / T_ENEMY, 0.0, 1.0)

	var view := {
		"floor_index": snap["floor_index"], "turn": snap["turn"] + 1, "hp": snap["hp"], "walls": snap["walls"].keys(),
		"enemies": [], "show_intents": t < t_end, "danger": snap["danger"].keys(), "spawns": snap["spawns"],
		"footprints": post.footprints() if post.turn == snap["turn"] + 1 else [], "shots": [],
		"echo_alpha": 0.0, "echo_px": Vector2.ZERO, "player_px": _cell_center(snap["player"]),
		"player_cell": post.player if post.turn == snap["turn"] + 1 else snap["player"],
		"blocked_echo": false, "echo_cell": Vector2i(-1, -1),
	}

	var moved: Dictionary = {}      # 적 id -> 도착 칸
	var echo_killed: Dictionary = {}  # 칸 -> true (메아리 처치)
	var shot_killed: Dictionary = {}
	for e in events:
		match e["type"]:
			"move":
				view["player_px"] = _cell_center(e["from"]).lerp(_cell_center(e["to"]), k_move)
			"slash":
				if t < T_MOVE + 0.08:
					var c := _cell_center(e["pos"])
					view["slash_line"] = [c, c + Vector2(e["dir"]) * CELL * 0.9 * maxf(k_move, 0.3)]
			"echo":
				var from_px: Vector2 = _cell_center(snap["echo_pos"]) if snap["echo"] else _cell_center(e["pos"])
				view["echo_px"] = from_px.lerp(_cell_center(e["pos"]), k_echo)
				# 명중 순간에는 불투명해진다
				var hit := t >= t_echo + T_ECHO and t < t_enemy and t_enemy - t_echo > T_ECHO
				view["echo_alpha"] = 1.0 if hit else (0.55 if snap["echo"] else 0.55 * k_echo)
				view["echo_cell"] = e["pos"]
				view["blocked_echo"] = true
			"echo_slash":
				if t >= t_echo and t < t_enemy:
					var c2 := _cell_center(e["pos"])
					view["echo_slash"] = [c2, c2.lerp(_cell_center(e["target"]), maxf(k_echo, 0.3))]
			"kill":
				if e["src"] == "friendly":
					shot_killed[e["pos"]] = true
				else:
					echo_killed[e["pos"]] = true
			"enemy_move":
				moved[e["id"]] = e["to"]
			"shot":
				if t >= t_enemy and t < t_end:
					var a := _cell_center(e["from"])
					view["shots"].append({"from": a, "to": a.lerp(_cell_center(e["to"]), k_enemy)})
			"hurt":
				if t >= t_enemy + T_ENEMY * 0.6:
					view["hp"] = e["hp"]

	if not snap["echo"] and view["echo_alpha"] == 0.0:
		pass
	elif view["echo_alpha"] == 0.0 and snap["echo"]:
		view["echo_alpha"] = 0.55
		view["echo_px"] = _cell_center(snap["echo_pos"])

	for e in snap["enemies"]:
		var cell: Vector2i = e["pos"]
		var px := _cell_center(cell)
		var alpha := 1.0
		if echo_killed.has(cell) and not moved.has(e["id"]) and t >= t_echo + T_ECHO:
			alpha = 0.0
		if moved.has(e["id"]):
			px = px.lerp(_cell_center(moved[e["id"]]), k_enemy)
			if shot_killed.has(moved[e["id"]]) and t >= t_enemy + T_ENEMY * 0.6:
				alpha = 0.0
		elif shot_killed.has(cell) and t >= t_enemy + T_ENEMY * 0.6:
			alpha = 0.0
		view["enemies"].append({"kind": e["kind"], "cell": cell, "pos": px, "intent": e["intent"], "dir": e["dir"], "alpha": alpha})

	# 증원은 턴 끝에 등장
	if t >= t_end:
		for e in events:
			if e["type"] == "spawn":
				view["enemies"].append({"kind": e["kind"], "cell": e["pos"], "pos": _cell_center(e["pos"]), "intent": "none", "dir": Vector2i.ZERO, "alpha": 1.0})
	return view


func _draw_aim_ray(from: Vector2i, dir: Vector2i, view: Dictionary) -> void:
	var occupied: Dictionary = {}
	for e in view["enemies"]:
		if e["alpha"] > 0.5:
			occupied[e["cell"]] = true
	var q := from + dir
	var last := from
	while Rules.inb(q) and not view["walls"].has(q) and not occupied.has(q) and not (view["blocked_echo"] and q == view["echo_cell"]):
		var r := _cell_rect(q)
		for i in range(1, 4):
			var o := CELL * i / 4.0
			draw_line(r.position + Vector2(o, 0), r.position + Vector2(0, o), Color(C_DANGER, 0.55), 2.0)
			draw_line(r.position + Vector2(CELL, o), r.position + Vector2(o, CELL), Color(C_DANGER, 0.55), 2.0)
		last = q
		if q == view["player_cell"]:
			break
		q += dir
	if last != from:
		_draw_arrow_head(_cell_center(last) - Vector2(dir) * CELL * 0.42, Vector2(dir), C_DANGER)


func _draw_preview() -> void:
	if not pressing or state != State.PLAY or rules == null or not anim.is_empty():
		return
	var act := _gesture_action(press_pos, drag_pos)
	if act == "" or not rules.can_act(act):
		return
	var target: Vector2i = rules.strike_cell_of(act)
	var r := _cell_rect(target).grow(-6)
	if Rules.is_move(act):
		draw_rect(r, C_PLAYER, false, 3.0)
	else:
		draw_line(_cell_center(rules.player), _cell_center(target), C_PLAYER, 4.0)
	# 3턴 뒤 메아리의 타격 칸: 점선 X와 ③
	var c := _cell_center(target)
	for k in 3:
		var a := 8.0 + k * 9.0
		draw_line(c + Vector2(-a - 5, -a - 5), c + Vector2(-a, -a), C_ECHO, 3.0)
		draw_line(c + Vector2(a + 5, a + 5), c + Vector2(a, a), C_ECHO, 3.0)
		draw_line(c + Vector2(a + 5, -a - 5), c + Vector2(a, -a), C_ECHO, 3.0)
		draw_line(c + Vector2(-a - 5, a + 5), c + Vector2(-a, a), C_ECHO, 3.0)
	_draw_footprint(_cell_rect(target).position + Vector2(16, 16), 3, act if Rules.is_slash(act) else "", false)


func _draw_effects() -> void:
	# 처치 조각
	for f in fragments:
		var ft: float = clock - f["t0"]
		if ft < 0.0 or ft > 0.4:
			continue
		var k := ft / 0.4
		for i in 4:
			var ang := PI / 4 + i * PI / 2
			var p: Vector2 = f["pos"] + Vector2(cos(ang), sin(ang)) * (10.0 + 34.0 * k)
			draw_rect(Rect2(p - Vector2(7, 7) * (1.0 - k * 0.5), Vector2(14, 14) * (1.0 - k * 0.5)), Color(C_ENEMY, 1.0 - k))
	# 막음 파문
	for rp in ripples:
		var rt: float = clock - rp["t0"]
		if rt < 0.0 or rt > 0.4:
			continue
		draw_arc(rp["pos"], 24.0 + 30.0 * rt / 0.4, 0, TAU, 32, Color(C_ECHO, 1.0 - rt / 0.4), 3.0)
	# 글자
	for p in popups:
		var pt: float = clock - p["t0"]
		if pt < 0.0 or pt > T_POPUP:
			continue
		var col: Color = p["color"]
		col.a = 1.0 - pt / T_POPUP
		draw_string(font, p["pos"] + Vector2(-60, -30 - 20 * pt / T_POPUP), p["text"], HORIZONTAL_ALIGNMENT_CENTER, 120, 22, col)
	popups = popups.filter(func(x): return clock - x["t0"] <= T_POPUP)
	fragments = fragments.filter(func(x): return clock - x["t0"] <= 0.4)
	ripples = ripples.filter(func(x): return clock - x["t0"] <= 0.4)


func _draw_hurt_border() -> void:
	var ht := clock - hurt_t0
	if ht >= 0.0 and ht < T_HURT:
		draw_rect(Rect2(4, 4, W - 8, H - 8), Color(C_HURT, 1.0 - ht / T_HURT), false, 10.0)


func _draw_player(pos: Vector2, low: bool, broken: bool) -> void:
	draw_circle(pos, 22, C_PLAYER)
	if broken:
		# 피격: 깨진 외곽선
		for i in 6:
			draw_arc(pos, 29, i * TAU / 6 + 0.15, i * TAU / 6 + 0.7, 6, C_HURT, 4.0)
	elif low:
		_draw_dashed_circle(pos, 29, C_HURT, 3.0)


func _draw_echo(pos: Vector2, alpha: float) -> void:
	draw_circle(pos, 22, Color(C_ECHO, 0.35 * alpha / 0.55 if alpha < 1.0 else 0.95))
	_draw_dashed_circle(pos, 26, Color(C_ECHO, minf(1.0, alpha + 0.3)), 2.5)


func _draw_dashed_circle(pos: Vector2, radius: float, color: Color, width: float) -> void:
	for i in 10:
		draw_arc(pos, radius, i * TAU / 10, i * TAU / 10 + TAU / 20, 5, color, width)


func _draw_enemy(pos: Vector2, kind: String, facing: Vector2i, alpha: float) -> void:
	var col := Color(C_ENEMY, alpha)
	if kind == "W":
		draw_rect(Rect2(pos - Vector2(20, 20), Vector2(40, 40)), col)
	else:
		# 궁수: 꼭짓점이 조준 방향을 가리키는 삼각형
		var f := Vector2(facing)
		var side := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([pos + f * 24, pos - f * 18 + side * 22, pos - f * 18 - side * 22]), col)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var dir := (to - from).normalized()
	var a := from + dir * 26
	var b := from + dir * (CELL * 0.72)
	draw_line(a, b, color, 3.0)
	_draw_arrow_head(b, dir, color)


func _draw_arrow_head(tip: Vector2, dir: Vector2, color: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip + dir * 8, tip - dir * 4 + side * 8, tip - dir * 4 - side * 8]), color)


## 치기 의도: 대상 칸에 굵은 테두리 + 주먹
func _draw_fist(cell: Vector2i) -> void:
	if not Rules.inb(cell):
		return
	var r := _cell_rect(cell).grow(-3)
	draw_rect(r, C_HURT, false, 4.0)
	var c := r.position + Vector2(16, 16)
	draw_rect(Rect2(c - Vector2(9, 6), Vector2(18, 14)), C_HURT)
	for i in 4:
		draw_circle(c + Vector2(-7.5 + i * 5, -7), 2.8, C_HURT)


## 발자국: 작은 원 안의 숫자. 베기였으면 벨 방향으로 짧은 선
func _draw_footprint(pos: Vector2, order: int, act: String, big: bool) -> void:
	var radius := 18.0 if big else 13.0
	draw_circle(pos, radius, Color(C_BG, 0.75))
	draw_arc(pos, radius, 0, TAU, 20, C_ECHO, 2.0)
	var size := 24 if big else 19
	draw_string(font, pos + Vector2(-radius, size * 0.36), str(order), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, size, C_TEXT)
	if Rules.is_slash(act):
		var d := Vector2(Rules.act_dir(act))
		draw_line(pos + d * radius, pos + d * (radius + 12), C_ECHO, 3.0)


func _draw_hearts(pos: Vector2, filled: int) -> void:
	for i in Rules.HP_MAX:
		_draw_heart(pos + Vector2(i * 30, 0), 11.0, i < filled)


func _draw_heart(center: Vector2, size: float, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var x := 16.0 * pow(sin(a), 3)
		var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
		pts.append(center + Vector2(x, y) * size / 16.0)
	if filled:
		draw_colored_polygon(pts, C_HURT)
	else:
		pts.append(pts[0])
		draw_polyline(pts, C_MUTED, 2.0)


func _draw_button(rect: Rect2, label: String, active: bool) -> void:
	draw_rect(rect, Color(C_ECHO, 0.22) if active else C_PANEL)
	draw_rect(rect, C_ECHO if active else C_GRID, false, 5.0 if active else 2.0)
	var size := 18 if label.length() > 4 else 26
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y / 2 + size * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, C_TEXT)


# ---------------------------------------------------------------- 입력 흉내 (tests/)

func debug_tap(pos: Vector2) -> void:
	_press(pos)
	_release(pos)


func debug_swipe(from: Vector2, to: Vector2) -> void:
	_press(from)
	_drag(to)
	_release(to)


func debug_press(id: String) -> void:
	var rect := BTN_SLASH if id == "slash" else BTN_WAIT
	debug_tap(rect.get_center())


func debug_act(action: String) -> bool:
	return _do_action(action)


func debug_load_floors(new_floors: Array) -> void:
	_start_run(new_floors, [])
