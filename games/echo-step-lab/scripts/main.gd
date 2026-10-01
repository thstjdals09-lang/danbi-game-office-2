extends Node2D
## 메아리 발자국 — 상태, 입력, 그리기, 연출.
## 규칙은 scripts/rules.gd 가 계산하고, 여기서는 그 결과(events)를 화면에 재생한다.
## 기준: design/FIRST_BUILD.md + BUILD_2.md + BUILD_3.md + BUILD_4.md (테스트 인터페이스, 연출 배선표), design/SCREENS.md (화면).

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
const BTN_REWIND := Rect2(180, 812, 180, 52)   # 베기·대기보다 작게, 그 아래

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
const T_FLASH := 0.3                     # 칼이 없을 때 베기를 누르면: 버튼 흔들림, 칼이 실린 발자국 깜빡임
const T_GLOW := 0.5                      # 층 클리어: 발자국이 빛나며 사라짐

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
const C_SHIELD := Color("ffe9c2")
# 4차 질감: 세로 그라데이션 배경, 체크 무늬 타일, 높이가 있는 벽
const C_BG_TOP := Color("060b16")
const C_BG_BOT := Color("182742")
const C_TILE_A := Color("15223a")
const C_TILE_B := Color("1d2e4d")
const C_WALL_TOP := Color("52698f")
const C_WALL_FRONT := Color("2a3955")
const C_BORDER := Color("31486d")
# 4차 화면 흔들림(px). BUILD_4.md 연출 배선표
const SHAKE_KILL := 4.0
const SHAKE_CRUSH := 5.0
const SHAKE_COMBO := 6.0
const SHAKE_HURT := 6.0
const SHAKE_BLAST := 8.0

# ---------------------------------------------------------------- 테스트 인터페이스 (FIRST_BUILD.md, BUILD_2.md·BUILD_3.md 추가분)

var state: int = State.TITLE
var floor_index := 0
var floor_count := 10
var kills := {"stomp": 0, "slash": 0, "friendly": 0, "crush": 0}
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
var sword_wait: int:
	get:
		return rules.sword_wait() if rules != null and state == State.PLAY else 0
var bombs: Array:
	get:
		return rules.bombs if rules != null else []
var rewinds_left: int:
	get:
		return rewinds if state == State.PLAY else 0
# 4차: 마지막으로 확정한 행동(또는 되감기)의 연출. 행동을 확정하는 순간 정해지고 그리기와 무관하게 읽힌다
var last_fx: Array = []
var last_shake := 0.0
var last_anim_duration := 0.0

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
var sword_flash_t0 := -10.0
var rewinds := 0                         # 이 층에서 남은 되감기
var undo: Dictionary = {}                # 마지막 행동 직전의 {"rules": 규칙 상태, "last_action"}. 비어 있으면 되감을 것이 없다
var rewind_t0 := -10.0                   # 되감기 번쩍임
var rewind_shake_t0 := -10.0             # 쓸 수 없을 때 버튼 흔들림
var blasts: Array = []                   # {"cells", "pos", "t0"} 폭발 연출
var banner_pre := ""                     # 층 안내 앞에 먼저 보여 줄 글자(체험 구간 끝)
# 4차 연출(전부 표시일 뿐, 규칙과 무관)
var board_off := Vector2.ZERO            # 보드 흔들림. 보드를 그리는 동안의 그리기 변환에만 쓴다(입력 좌표와 무관)
var shakes: Array = []                   # {"t0", "px", "dur"}
var parts: Array = []                    # 보드 위 조각 {"pos","vel","grav","t0","life","color","size","spin"}
var ui_parts: Array = []                 # 보드 밖(위 띠) 조각. 흔들리지 않는다
var rings: Array = []                    # 충격 고리 {"pos","t0","color"}
var glints: Array = []                   # 처치 칸의 잔광 {"cell","t0"}
var streaks: Array = []                  # 밀치기 궤적 {"from","to","t0"}
var arcs: Array = []                     # 칼 궤적(호) {"pos","dir","t0","color"}
var sweep_t0 := -10.0                    # 층 클리어: 보드를 훑는 띠
var combo_t0 := -10.0
var combo_text := ""
var glows: Array = []                    # {"pos", "t0"} 층 클리어 때 빛나며 사라지는 발자국
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
			# 연출이 제 시간에 끝났을 때도 다음 층 안내를 띄운다(전에는 입력으로 넘길 때만 떴다)
			var after: bool = anim.get("banner_after", false)
			anim = {}
			if after:
				_show_banner()
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
					if sword_wait > 0:
						slash_mode = false       # 칼이 없으면 켜지지 않는다(SCREENS.md 2차)
						sword_flash_t0 = clock
					else:
						slash_mode = not slash_mode
				elif BTN_WAIT.has_point(press_pos) and BTN_WAIT.has_point(pos):
					_do_action("W")
				elif BTN_REWIND.has_point(press_pos) and BTN_REWIND.has_point(pos):
					_do_rewind()
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
	kills = {"stomp": 0, "slash": 0, "friendly": 0, "crush": 0}
	last_action = ""
	result_won = false
	defeat_cause = ""
	reached_floor = 0
	slash_mode = false
	anim = {}
	popups.clear()
	fragments.clear()
	ripples.clear()
	glows.clear()
	blasts.clear()
	_clear_fx()
	last_fx = []
	last_shake = 0.0
	last_anim_duration = 0.0
	_load_floor(0, Rules.HP_MAX)
	state = State.PLAY
	_show_banner()


func _load_floor(index: int, start_hp: int) -> void:
	floor_index = index
	rules = Rules.new()
	rules.setup(floors[index], start_hp, kills)
	rewinds = 1                          # 되감기는 층마다 1회
	undo = {}


## 되감기: 마지막으로 확정한 행동 직전으로 전부 되돌린다. 불가능하면 false(버튼이 흔들린다)
func _do_rewind() -> bool:
	if state != State.PLAY or rules == null or undo.is_empty() or rewinds < 1:
		rewind_shake_t0 = clock
		return false
	anim = {}                            # 연출 없이 그 상태를 바로 그린다
	popups.clear()
	fragments.clear()
	ripples.clear()
	blasts.clear()
	_clear_fx()
	last_fx = ["rewind_flash"]
	last_shake = 0.0
	last_anim_duration = 0.0
	hurt_t0 = -10.0
	rules.restore(undo["rules"])
	last_action = undo["last_action"]
	undo = {}
	rewinds -= 1
	slash_mode = false
	rewind_t0 = clock
	popups.append({"text": "되감기", "pos": _cell_center(rules.player), "t0": clock, "color": C_ECHO})
	return true


func _clear_fx() -> void:
	shakes.clear()
	parts.clear()
	ui_parts.clear()
	rings.clear()
	glints.clear()
	streaks.clear()
	arcs.clear()
	sweep_t0 = -10.0
	combo_t0 = -10.0


## BUILD_4.md 연출 배선표: 규칙의 사건 → 연출 이름과 화면 흔들림. 검사는 이 결과를 본다
func _compute_fx(events: Array) -> void:
	var fx: Array = []
	var shake := 0.0
	var kill_count := 0
	var add := func(n: String) -> void:
		if not fx.has(n):
			fx.append(n)
	for e in events:
		match e["type"]:
			"move":
				add.call("step")
			"slash":
				add.call("slash_arc")
			"echo":
				if Rules.is_move(e["act"]):
					add.call("echo_stomp")
				elif Rules.is_slash(e["act"]):
					add.call("echo_slash_arc")
			"kill":
				kill_count += 1
				add.call("kill_shards")
				add.call("afterglow")
				shake = maxf(shake, SHAKE_KILL)
			"push":
				add.call("push_streak")
			"crush":
				add.call("crush_shake")
				shake = maxf(shake, SHAKE_CRUSH)
			"deflect":
				add.call("deflect_sparks")
			"throw":
				add.call("bomb_throw")
			"explode":
				add.call("blast_embers")
				shake = maxf(shake, SHAKE_BLAST)
			"hurt":
				add.call("hurt_heart")
				shake = maxf(shake, SHAKE_HURT)
			"clear":
				add.call("floor_sweep")
				if floor_index + 1 >= floor_count:
					add.call("confetti")
	if kill_count >= 2:
		fx.append("combo_%d" % kill_count)
		shake = maxf(shake, SHAKE_COMBO)
	last_fx = fx
	last_shake = shake


func _show_banner() -> void:
	banner_t0 = clock
	var floor_name: String = floor_names[floor_index] if floor_index < floor_names.size() else ""
	banner_text = "%d층" % (floor_index + 1) + ((" 「%s」" % floor_name) if floor_name != "" else "")
	# 기본 캠페인에서 5층을 깨고 6층에 들어설 때: 체험 구간 끝 안내를 먼저 보여 준다
	banner_pre = "체험 구간 끝 — 여기부터 본편" if floors == Content.FLOORS and floor_index == Content.DEMO_FLOORS else ""


## 행동 하나를 확정한다. 규칙 상태는 여기서 즉시 끝까지 갱신되고, 연출은 그 뒤를 따라간다.
func _do_action(act: String) -> bool:
	if state != State.PLAY or rules == null:
		return false
	if not rules.can_act(act):
		if Rules.is_slash(act) and rules.sword_wait() > 0:
			sword_flash_t0 = clock       # 칼이 없다: 버튼이 흔들리고 칼이 실린 발자국이 깜빡인다
		else:
			shake_t0 = clock
		return false
	_finish_anim()
	var snap := _snapshot()
	undo = {"rules": rules.snapshot(), "last_action": last_action}
	var events: Array = rules.step(act)
	last_action = act
	_compute_fx(events)
	_begin_anim(snap, events)
	last_anim_duration = anim["dur"]
	if rules.outcome != "":
		undo = {}                        # 층을 깼거나 게임이 끝난 행동은 되돌릴 수 없다

	match rules.outcome:
		"clear":
			reached_floor = floor_index + 1
			# 층 클리어: 남아 있던 발자국이 빛나며 사라진다
			for f in rules.footprints():
				glows.append({"pos": _cell_rect(f["pos"]).position + Vector2(16, 16), "t0": clock + anim["t_enemy"]})
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
				defeat_cause = "%d턴, %s" % [rules.turn, {"A": "궁수의 화살", "S": "방패병의 치기", "bomb": "폭탄의 폭발"}.get(by, "졸개의 치기")]
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
		"bombs": rules.bombs.duplicate(true),
	}


func _begin_anim(snap: Dictionary, events: Array) -> void:
	var echo_kill := false           # 메아리의 일격이 명중했는가(처치·밀치기·으깨기) → 히트스톱
	for e in events:
		if (e["type"] == "kill" and e["src"] != "friendly") or e["type"] == "push":
			echo_kill = true
	var t_echo := T_MOVE
	var t_enemy := t_echo + T_ECHO + (T_STOP if echo_kill else 0.0)
	var t_end := t_enemy + T_ENEMY
	var t_hit := t_echo + T_ECHO
	anim = {"snap": snap, "events": events, "t": 0.0, "dur": t_end + T_END,
		"t_echo": t_echo, "t_enemy": t_enemy, "t_end": t_end, "post": rules, "banner_after": false}
	# 글자·조각·고리는 시계 기준으로 따로 흐른다(연출을 넘겨도 잠깐 남는다)
	var shake_at := clock            # 가장 큰 흔들림 하나가 시작할 시각
	var kill_at := clock
	var kill_count := 0
	for e in events:
		match e["type"]:
			"move":
				_burst(_cell_center(e["from"]) + Vector2(0, 16), clock, 3, Color(C_MUTED, 0.6), 34.0, 0.3, 6.0, Vector2.UP, PI * 0.8)
			"slash":
				arcs.append({"pos": _cell_center(e["pos"]), "dir": Vector2(e["dir"]), "t0": clock, "color": C_PLAYER})
			"echo":
				if Rules.is_move(e["act"]):
					rings.append({"pos": _cell_center(e["pos"]), "t0": clock + t_hit, "color": C_ECHO})
			"echo_slash":
				arcs.append({"pos": _cell_center(e["pos"]), "dir": Vector2(e["target"] - e["pos"]), "t0": clock + t_echo, "color": C_ECHO})
			"kill":
				var friendly: bool = e["src"] == "friendly"
				var at: float = clock + (t_enemy + T_ENEMY * 0.6 if friendly else t_hit)
				if e["src"] == "crush":
					at = clock + t_enemy     # 으깨기: 막힌 쪽으로 밀리다 납작해진 뒤에 흩어진다
				if e.get("blast", false):
					at = clock + t_end       # 폭발에 휘말림
				_burst(_cell_center(e["pos"]), at, 10, C_ENEMY, 130.0, 0.45, 13.0)
				rings.append({"pos": _cell_center(e["pos"]), "t0": at, "color": C_TEXT})
				glints.append({"cell": e["pos"], "t0": at})
				var label: String = {"friendly": "오사!", "stomp": "밟기!", "slash": "베기!", "crush": "으깨기!"}[e["src"]]
				popups.append({"text": label, "pos": _cell_center(e["pos"]), "t0": at, "color": C_GOOD})
				kill_count += 1
				kill_at = maxf(kill_at, at)
				if last_shake <= SHAKE_COMBO:
					shake_at = at
			"push":
				# 처치가 아니어도 명중 글자는 뜬다
				popups.append({"text": "밟기!" if e["src"] == "stomp" else "베기!", "pos": _cell_center(e["from"]), "t0": clock + t_hit, "color": C_GOOD})
				streaks.append({"from": _cell_center(e["from"]), "to": _cell_center(e["to"]), "t0": clock + t_hit})
			"crush":
				if is_equal_approx(last_shake, SHAKE_CRUSH):
					shake_at = clock + t_enemy
			"explode":
				blasts.append({"cells": e["cells"], "pos": e["pos"], "t0": clock + t_end})
				popups.append({"text": "쾅!", "pos": _cell_center(e["pos"]), "t0": clock + t_end, "color": C_TEXT})
				for c in e["cells"]:
					_burst(_cell_center(c), clock + t_end, 4, C_DANGER, 60.0, 0.5, 7.0, Vector2.UP, PI * 0.5, -40.0)
				shake_at = clock + t_end
			"deflect":
				popups.append({"text": "튕김", "pos": _cell_center(e["pos"]), "t0": clock + t_hit, "color": C_SHIELD})
				_burst(_cell_center(e["pos"]) + Vector2(e["face"]) * 24, clock + t_hit, 5, C_SHIELD, 110.0, 0.3, 6.0, Vector2(e["face"]), PI * 0.6)
			"block":
				ripples.append({"pos": _cell_center(e["pos"]), "t0": clock + t_enemy + T_ENEMY * 0.6})
				popups.append({"text": "막음", "pos": _cell_center(e["pos"]), "t0": clock + t_enemy + T_ENEMY * 0.6, "color": C_ECHO})
			"hurt":
				hurt_t0 = clock + t_enemy + T_ENEMY * 0.6
				# 잃은 하트가 깨진다(위 띠, 흔들리지 않는 좌표)
				_burst(_heart_pos(e["hp"]), hurt_t0, 6, C_HURT, 70.0, 0.4, 6.0, Vector2.ZERO, TAU, 120.0, true)
				if last_shake < SHAKE_BLAST:
					shake_at = hurt_t0
			"clear":
				sweep_t0 = clock + t_enemy
				popups.append({"text": "층 클리어!", "pos": BOARD + Vector2(CELL, CELL) * Rules.N * 0.5, "t0": clock + t_enemy, "color": C_TEXT, "big": true})
	if kill_count >= 2:
		combo_text = "%d연속!" % kill_count
		combo_t0 = kill_at
	if last_shake > 0.0:
		shakes.append({"t0": shake_at, "px": last_shake, "dur": 0.25 if last_shake >= SHAKE_BLAST else 0.15})


func _finish_anim() -> void:
	if anim.is_empty():
		return
	if anim.get("banner_after", false):
		_show_banner()
	anim = {}
	# 아직 시작하지 않은 글자·조각은 지금 바로 보이게 당긴다
	for list in [popups, ripples, glows, blasts, parts, ui_parts, rings, glints, streaks, arcs, shakes]:
		for q in list:
			if q["t0"] > clock:
				q["t0"] = clock
	if hurt_t0 > clock:
		hurt_t0 = clock
	if sweep_t0 > clock:
		sweep_t0 = clock
	if combo_t0 > clock:
		combo_t0 = clock


## 조각 여러 개를 한 번에. 방향과 속도는 번호로 정해진다(난수를 쓰지 않아 같은 입력이면 같은 화면)
func _burst(pos: Vector2, t0: float, n: int, color: Color, speed: float, life: float, size: float,
		dir := Vector2.ZERO, spread := TAU, grav := 0.0, ui := false) -> void:
	var base := dir.angle() if dir != Vector2.ZERO else 0.3
	for i in n:
		var ang := base + spread * ((i + 0.5) / n - 0.5)
		var vel := Vector2.from_angle(ang) * speed * (0.7 + 0.2 * (i % 3))
		var q := {"pos": pos, "vel": vel, "grav": grav, "t0": t0, "life": life, "color": color,
			"size": size * (0.8 + 0.15 * (i % 3)), "spin": 7.0 * (1 if i % 2 == 0 else -1)}
		if ui:
			ui_parts.append(q)
		else:
			parts.append(q)


## 위 띠의 i번째 하트 자리(0부터). 체력이 hp가 됐다면 깨지는 하트는 hp번째
func _heart_pos(i: int) -> Vector2:
	return Vector2(W - 28 - 5 * 30 + 15, 56) + Vector2(i * 30, 0)


## 지금의 보드 흔들림(가장 센 것 하나). 그리기 변환에만 쓴다
func _shake_offset() -> Vector2:
	var best := Vector2.ZERO
	var best_px := 0.0
	for sh in shakes:
		var st: float = clock - sh["t0"]
		if st < 0.0 or st >= sh["dur"]:
			continue
		var amp: float = sh["px"] * (1.0 - st / sh["dur"])
		if amp > best_px:
			best_px = amp
			best = Vector2(sin(st * 95.0), cos(st * 78.0)) * amp
	shakes = shakes.filter(func(x): return clock - x["t0"] < x["dur"])
	return best


## pos 를 중심으로 sc 만큼 늘이거나 줄여 그리게 한다(보드 흔들림과 함께)
func _push_scale(pos: Vector2, sc: Vector2) -> void:
	draw_set_transform(board_off + pos * (Vector2.ONE - sc), 0.0, sc)


func _pop_scale() -> void:
	draw_set_transform(board_off, 0.0, Vector2.ONE)


func _breathe(period: float, amp: float, phase := 0.0) -> float:
	return 1.0 + amp * sin(TAU * clock / period + phase)


func _cell_center(c: Vector2i) -> Vector2:
	return BOARD + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(BOARD + Vector2(c) * CELL, Vector2(CELL, CELL))


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	# 배경: 위(어두움) → 아래(조금 밝음) 세로 그라데이션
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([C_BG_TOP, C_BG_TOP, C_BG_BOT, C_BG_BOT]))
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
	_draw_backdrop(0.25)
	_draw_dust()
	_text("메아리 발자국", 300, 46, C_TEXT)
	_text("지금의 한 걸음이", 366, 22, C_MUTED)
	_text("3턴 뒤의 칼이 된다", 396, 22, C_MUTED)
	# 움직이는 그림: 내가 한 칸씩 걷고, 메아리가 3박자 뒤에 같은 길을 따라 걷는다(4초 주기, 8걸음)
	var y := 500.0
	var beat := fposmod(clock, 4.0) / 0.5
	var step := int(beat)
	var k := clampf((beat - step) / 0.3, 0.0, 1.0)
	var xs := func(i: float) -> float: return 86.0 + 52.0 * i
	draw_line(Vector2(60, y + 34), Vector2(W - 60, y + 34), C_BORDER, 2.0)
	var me := Vector2(xs.call(maxf(0.0, step - 1 + k)), y)
	if step >= 3:
		var echo := Vector2(xs.call(step - 4 + k), y)
		_draw_echo(echo, 1.0)
		_text("메아리", 558, 14, C_ECHO, echo.x - 50, 100)
	for i in 3:
		var at := step - 3 + i       # 메아리가 앞으로 밟을 칸: ①이 가장 가까운 미래
		if at >= 0 and at < step:
			_draw_footprint(Vector2(xs.call(at), y), i + 1, "", true, false, _footprint_pulse(i + 1))
	_draw_player(me, false, false, true, Vector2.ONE * _breathe(1.4, 0.04))
	_text("나", 558, 14, C_TEXT, me.x - 50, 100)
	_text("화면을 눌러 시작", 680, 24, Color(C_TEXT, 0.6 + 0.4 * absf(sin(clock * 2.2))))


## 타이틀·결과 화면의 뒤: 옅은 체크 무늬
func _draw_backdrop(alpha: float) -> void:
	for yy in 15:
		for xx in 8:
			if (xx + yy) % 2 == 0:
				draw_rect(Rect2(xx * CELL - 2, yy * CELL - 30, CELL, CELL), Color(C_TILE_B, alpha))


## 느린 먼지 입자 12개. 위치는 시계와 번호의 함수(난수 없음)
func _draw_dust() -> void:
	for i in 12:
		var speed := 6.0 + (i % 4) * 2.0
		var px := fposmod(i * 97.3 + 31.0, W) + sin(clock * 0.4 + i) * 10.0
		var py := H - fposmod(clock * speed + i * 83.0, H)
		draw_circle(Vector2(px, py), 2.0 + (i % 3), Color(C_TEXT, 0.10 + 0.05 * (i % 3)))


func _footprint_pulse(order: int) -> float:
	if order == 1:
		return 1.0 + 0.18 * absf(sin(TAU * clock / 0.7))
	if order == 2:
		return 1.0 + 0.07 * absf(sin(TAU * clock / 0.7))
	return 1.0


func _draw_result() -> void:
	_draw_backdrop(0.25)
	if result_won:
		# 색종이: 24조각이 돌면서 떨어진다(시계의 함수)
		for i in 24:
			var cx := fposmod(i * 71.7 + 20.0, W) + sin(clock * 1.3 + i) * 14.0
			var cy := fposmod(clock * (70.0 + (i % 5) * 18.0) + i * 53.0, H)
			draw_set_transform(Vector2(cx, cy), clock * (2.0 + i % 3) + i, Vector2.ONE)
			draw_rect(Rect2(-5, -3, 10, 6), Color([C_ECHO, C_GOOD, C_DANGER, C_TEXT][i % 4], 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(60, 250, W - 120, 510), Color(C_PANEL, 0.82))
	draw_rect(Rect2(60, 250, W - 120, 510), C_BORDER, false, 1.5)
	var title := "런 승리!" if result_won else ("메아리가 무너졌다 (60턴)" if rules != null and rules.outcome == "timeout" else "쓰러졌다")
	_text(title, 320, 40, C_GOOD if result_won else C_HURT)
	_text("도달  %d / %d층" % [reached_floor, floor_count], 400, 24, C_TEXT)
	_text("처치  밟기 %d · 베기 %d" % [kills["stomp"], kills["slash"]], 444, 20, C_TEXT)
	_text("오사 %d · 으깨기 %d" % [kills["friendly"], kills["crush"]], 474, 20, C_TEXT)
	_text("남은 체력", 530, 18, C_MUTED)
	_draw_hearts(Vector2(W / 2 - 2 * 30, 562), maxi(hp, 0))
	if not result_won and defeat_cause != "":
		_text(defeat_cause, 630, 18, C_DANGER)
	_text("화면을 눌러 다시", 720, 24, Color(C_TEXT, 0.6 + 0.4 * absf(sin(clock * 2.2))))


func _draw_play() -> void:
	var animating := not anim.is_empty()
	var view := _anim_view() if animating else _static_view()
	_draw_dust()

	# 위 띠(패널). 흔들리지 않는다
	draw_rect(Rect2(14, 28, W - 28, 54), Color(C_PANEL, 0.85))
	draw_rect(Rect2(14, 28, W - 28, 54), C_BORDER, false, 1.5)
	_text("%d/%d층" % [view["floor_index"] + 1, floor_count], 64, 22, C_TEXT, 28, 140, HORIZONTAL_ALIGNMENT_LEFT)
	_text("턴 %d/%d" % [view["turn"], Rules.TURN_LIMIT], 64, 22, C_MUTED, 170, 150, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_hearts(Vector2(W - 28 - 5 * 30 + 15, 56), view["hp"])

	# ---- 여기부터 보드: 화면 흔들림은 보드와 그 위의 것만 흔든다(그리기 변환. 입력 좌표와 무관) ----
	board_off = _shake_offset()
	_pop_scale()
	var board_rect := Rect2(BOARD, Vector2(CELL, CELL) * Rules.N)
	draw_rect(Rect2(board_rect.position + Vector2(-4, 6), board_rect.size + Vector2(8, 6)), Color(0, 0, 0, 0.4))
	draw_rect(board_rect.grow(4), C_BORDER)
	for ty in Rules.N:
		for tx in Rules.N:
			var tr := Rect2(BOARD + Vector2(tx, ty) * CELL, Vector2(CELL, CELL))
			draw_rect(tr, C_TILE_A if (tx + ty) % 2 == 0 else C_TILE_B)
			draw_rect(tr.grow(-3), Color(1, 1, 1, 0.035), false, 1.0)
	for w in view["walls"]:
		# 벽: 윗면(밝게) + 앞면(어둡게). 으깨기를 막은 벽은 잠깐 흔들린다
		var wob := Vector2.ZERO
		if view["wobble"] == w:
			wob = Vector2(sin(clock * 90.0) * 2.0, 0)
		var wr := _cell_rect(w).grow(-2)
		wr.position += wob
		draw_rect(Rect2(wr.position, Vector2(wr.size.x, wr.size.y * 0.72)), C_WALL_TOP)
		draw_rect(Rect2(wr.position + Vector2(0, wr.size.y * 0.72), Vector2(wr.size.x, wr.size.y * 0.28)), C_WALL_FRONT)
		draw_rect(Rect2(wr.position, Vector2(wr.size.x, wr.size.y * 0.72)).grow(-5), Color(1, 1, 1, 0.06), false, 1.0)

	# 처치 칸의 잔광
	for gl in glints:
		var gt: float = clock - gl["t0"]
		if gt >= 0.0 and gt < 0.4:
			draw_rect(_cell_rect(gl["cell"]).grow(-2), Color(C_TEXT, 0.35 * (1.0 - gt / 0.4)))
	glints = glints.filter(func(x): return clock - x["t0"] <= 0.4)

	# 조준 사선(흐르는 빗금), 위험 칸 "!"(깜빡임)
	for e in view["enemies"]:
		if view["show_intents"] and e["intent"] == "aim" and e["alpha"] > 0.5:
			_draw_aim_ray(e["cell"], e["dir"], view)
	if view["show_intents"]:
		var blink := 0.775 + 0.225 * sin(TAU * clock / 0.5)
		for c in view["danger"]:
			var r := _cell_rect(c)
			draw_string(font, r.position + Vector2(CELL - 20, 22), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(C_DANGER, blink))

	# 폭탄: 놓인 폭탄과 던질 자리. 범위 5칸에는 남은 턴 숫자(아래에서 맨 위에 그린다)
	var marks: Dictionary = {}           # 칸 -> 터질 때까지 내 행동 수(작은 쪽)
	var throw_targets: Array = []
	for b in view["bombs"]:
		_draw_bomb(_cell_center(b["pos"]), 1.0, b["fuse"] <= 1)
		for c in rules.blast_cells(b["pos"]):
			draw_rect(_cell_rect(c).grow(-3), Color(C_DANGER, 0.10 + 0.04 * sin(clock * 6.0)))
			marks[c] = mini(marks.get(c, 9), b["fuse"])
	if view["show_intents"]:
		for e in view["enemies"]:
			if e["intent"] == "bomb" and e["alpha"] > 0.5:
				_draw_dashed_line(e["pos"], _cell_center(e["target"]), Color(C_ENEMY, 0.9))
				throw_targets.append(e["target"])
				for c in rules.blast_cells(e["target"]):
					marks[c] = mini(marks.get(c, 9), Rules.BOMB_FUSE)

	# 증원 예고(천천히 도는 점선 원)
	for s in view["spawns"]:
		var left: int = maxi(1, int(s[0]) - view["turn"])
		_draw_dashed_circle(_cell_center(s[2]), 22, Color(C_ENEMY, 0.8), 2.0, clock * TAU / 3.0)
		draw_string(font, _cell_center(s[2]) + Vector2(-20, 7), str(left), HORIZONTAL_ALIGNMENT_CENTER, 40, 18, C_ENEMY)

	# 적 의도(이동 화살표, 치기 주먹)와 적. 으깨지는 적은 메아리 위에 그리려고 뒤로 미룬다
	var on_top: Array = []
	for e in view["enemies"]:
		if e["alpha"] <= 0.0:
			continue
		if view["show_intents"]:
			if e["intent"] == "move":
				var bob := Vector2(e["dir"]) * 3.0 * sin(TAU * clock / 0.8 + e["id"])
				_draw_arrow(_cell_center(e["cell"]) + bob, _cell_center(e["cell"] + e["dir"]) + bob, Color(C_ENEMY, 0.9))
			elif e["intent"] == "hit":
				_draw_fist(e["cell"] + e["dir"])
		if e["squash"] > 0.0:
			on_top.append(e)
		else:
			_draw_enemy_live(e, view["show_intents"])

	# 화살, 날아가는 폭탄
	for s in view["shots"]:
		draw_line(s["from"], s["to"], C_DANGER, 3.0)
		_draw_arrow_head(s["to"], (s["to"] - s["from"]).normalized(), C_DANGER)

	# 메아리(잔상 → 본체), 플레이어
	for g in view["echo_trail"]:
		_draw_echo(g["pos"], g["alpha"], 1.0)
	if view["echo_alpha"] > 0.0:
		_draw_echo(view["echo_px"], view["echo_alpha"], view["echo_scale"])
	for e in on_top:
		_draw_enemy_live(e, false)
	var shake := 0.0
	if clock - shake_t0 < T_SHAKE:
		shake = sin((clock - shake_t0) * 60.0) * 5.0
	var psc: Vector2 = view["player_scale"] * _breathe(1.4, 0.04)
	_draw_player(view["player_px"] + Vector2(shake, 0), view["hp"] <= 1, clock - hurt_t0 >= 0.0 and clock - hurt_t0 < T_HURT, view["sword"], psc)
	for f in view["flying"]:
		_draw_bomb(f, 1.0, false)

	# 발자국 ①②③ (플레이어·메아리 위에 그려 숫자가 가리지 않게). ①이 가장 크게 맥동한다
	var flash_t := clock - sword_flash_t0
	var sword_flash := flash_t >= 0.0 and flash_t < T_FLASH
	var stack: Dictionary = {}
	for f in view["footprints"]:
		var n: int = stack.get(f["pos"], 0)
		stack[f["pos"]] = n + 1
		var offset: Vector2 = [Vector2(16, 16), Vector2(44, 16), Vector2(16, 44)][mini(n, 2)]
		_draw_footprint(_cell_rect(f["pos"]).position + offset, f["in"], f["act"], false, sword_flash, _footprint_pulse(f["in"]))

	# 던질 자리의 폭탄 표시: 플레이어 위에, 오른쪽 위로 비켜 그려 가리지 않게
	for tc in throw_targets:
		_draw_bomb(_cell_center(tc) + Vector2(15, -15), 0.9, false)

	# 폭발 범위의 숫자(플레이어·발자국 위에 그려 가리지 않게): 칸 오른쪽 아래의 작은 딱지
	for c in marks:
		var mp := _cell_rect(c).position + Vector2(CELL - 12, CELL - 12)
		draw_circle(mp, 10, C_DANGER)
		draw_string(font, mp + Vector2(-10, 6), str(marks[c]), HORIZONTAL_ALIGNMENT_CENTER, 20, 16, C_BG)

	_draw_preview()
	_draw_effects()

	# 되감은 직후: 보드가 메아리 색으로 옅게 번쩍인다
	var rt := clock - rewind_t0
	if rt >= 0.0 and rt < 0.2:
		draw_rect(board_rect, Color(C_ECHO, 0.25 * (1.0 - rt / 0.2)))
	# 층 클리어: 보드를 위에서 아래로 훑는 밝은 띠
	var sw := clock - sweep_t0
	if sw >= 0.0 and sw < 0.35:
		var sy := board_rect.position.y + (board_rect.size.y - 46.0) * (sw / 0.35)
		draw_rect(Rect2(board_rect.position.x, sy, board_rect.size.x, 46), Color(C_TEXT, 0.30 * (1.0 - sw / 0.35) + 0.08))
	board_off = Vector2.ZERO
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ---- 보드 끝. 아래는 흔들리지 않는다 ----

	# 위 띠의 조각(깨지는 하트)
	_draw_parts(ui_parts)
	ui_parts = ui_parts.filter(func(x): return clock - x["t0"] <= x["life"])

	# 아래 띠(패널), 버튼, 안내
	draw_rect(Rect2(14, 614, W - 28, 40), Color(C_PANEL, 0.7))
	_text("처치  밟기 %d · 베기 %d · 오사 %d · 으깨기 %d" % [kills["stomp"], kills["slash"], kills["friendly"], kills["crush"]], 640, 18, C_MUTED)
	var wait_turns := sword_wait
	if wait_turns > 0:
		# 칼이 없다: 돌아올 때까지 남은 턴. 눌렀다면 좌우로 짧게 흔들린다
		var bx := sin(flash_t * 60.0) * 6.0 if sword_flash else 0.0
		_draw_sword_button(Rect2(BTN_SLASH.position + Vector2(bx, 0), BTN_SLASH.size), wait_turns)
	else:
		_draw_button(BTN_SLASH, "베기 ▶ 방향을 미세요" if slash_mode else "베기", slash_mode)
	_draw_button(BTN_WAIT, "대기", false)
	var hint := "아무 곳이나 밀어서 이동"
	if wait_turns > 0:
		hint = "칼은 메아리가 휘두른 뒤 돌아옵니다"
	elif slash_mode:
		hint = "베기를 켜고 밀면 그 방향을 벱니다"
	_text(hint, 898, 18, C_MUTED)
	# 되감기 버튼: 남은 횟수. 쓸 수 없으면(이미 썼거나 되돌릴 턴이 없음) 어둡게
	var can_rewind := rewinds > 0 and not undo.is_empty() and state == State.PLAY
	var rs := clock - rewind_shake_t0
	var rx := sin(rs * 60.0) * 6.0 if rs >= 0.0 and rs < T_SHAKE else 0.0
	_draw_small_button(Rect2(BTN_REWIND.position + Vector2(rx, 0), BTN_REWIND.size), "되감기 %d" % (rewinds if state == State.PLAY else 0), can_rewind)

	# 연속 처치: 보드 위쪽 가운데의 큰 글자
	var ct := clock - combo_t0
	if ct >= 0.0 and ct < 0.7:
		var cs := int(44.0 + 14.0 * maxf(0.0, 1.0 - ct / 0.15))
		_text(combo_text, 190, cs, Color(C_GOOD, 1.0 - maxf(0.0, (ct - 0.4) / 0.3)))

	# 층 안내
	var bt := clock - banner_t0
	var pre := T_BANNER if banner_pre != "" else 0.0   # 체험 구간 끝 안내가 있으면 그것을 먼저
	if bt >= 0.0 and bt < pre and not animating:
		var pa := 1.0 - 0.5 * bt / pre
		draw_rect(Rect2(0, 318, W, 84), Color(0, 0, 0, 0.7 * pa))
		_text(banner_pre, 370, 26, Color(C_GOOD, pa))
	elif bt >= pre and bt < pre + T_BANNER and not animating:
		var a := 1.0 - (bt - pre) / T_BANNER
		draw_rect(Rect2(0, 318, W, 84), Color(0, 0, 0, 0.55 * a))
		_text(banner_text, 374, 34, Color(C_TEXT, a))


## 적 하나: 숨쉬기(적마다 박자가 어긋남)와, 치려는 적의 들썩임을 얹어 그린다
func _draw_enemy_live(e: Dictionary, idle: bool) -> void:
	var pos: Vector2 = e["pos"]
	var sc := 1.0
	if idle:
		sc = _breathe(1.6, 0.03, e["id"] * 1.3)
		if e["intent"] == "hit":
			pos += Vector2(e["dir"]) * 2.0 * absf(sin(TAU * clock / 0.8))
	if e["squash"] <= 0.0:
		_draw_shadow(pos + Vector2(0, 24), 19.0, Color(0, 0, 0, 0.3 * e["alpha"]))
	_push_scale(pos, Vector2(sc, sc))
	_draw_enemy(pos, e["kind"], e["dir"] if e["intent"] == "aim" else Vector2i(0, 1), e["alpha"], e["hp"], e["face"], e["flash"], e["squash"])
	_pop_scale()


func _draw_parts(list: Array) -> void:
	for q in list:
		var qt: float = clock - q["t0"]
		if qt < 0.0 or qt > q["life"]:
			continue
		var k: float = qt / q["life"]
		var pos: Vector2 = q["pos"] + q["vel"] * qt + Vector2(0, q["grav"] * qt * qt)
		var sz: float = q["size"] * (1.0 - 0.6 * k)
		var col: Color = q["color"]
		col.a *= 1.0 - k
		draw_set_transform(board_off + pos, q["spin"] * qt, Vector2.ONE)
		draw_rect(Rect2(-sz / 2, -sz / 2, sz, sz), col)
	draw_set_transform(board_off, 0.0, Vector2.ONE)


## 연출이 없을 때: 규칙의 현재 상태 그대로
func _static_view() -> Dictionary:
	var es: Array = []
	for e in rules.enemies:
		es.append({"id": e["id"], "kind": e["kind"], "cell": e["pos"], "pos": _cell_center(e["pos"]), "intent": e["intent"], "dir": e["dir"], "alpha": 1.0,
			"hp": e["hp"], "face": e["face"], "flash": false, "squash": 0.0, "target": e["target"]})
	return {
		"floor_index": floor_index, "turn": rules.turn, "hp": rules.hp, "walls": rules.walls.keys(),
		"enemies": es, "show_intents": true, "danger": rules.danger_cells().keys(), "spawns": rules.spawns,
		"footprints": rules.footprints(), "shots": [],
		"echo_alpha": 0.55 if rules.has_echo() else 0.0, "echo_px": _cell_center(rules.echo_pos()),
		"player_px": _cell_center(rules.player), "player_cell": rules.player,
		"blocked_echo": rules.next_echo_pos().x >= 0, "echo_cell": rules.next_echo_pos(),
		"sword": rules.sword_wait() == 0,
		"bombs": rules.bombs,
		"player_scale": Vector2.ONE, "echo_scale": 1.0, "echo_trail": [], "flying": [], "wobble": Rules.NO_CELL,
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
		# 칼: 이번 턴에 벴으면 손에서 떠났고, 메아리가 벤 턴이 끝나야 돌아온다
		"sword": post.sword_wait() == 0 and t >= t_end if post.turn == snap["turn"] + 1 else true,
		"bombs": snap["bombs"],              # 턴 시작 때의 폭탄. 이번 턴에 던진 것은 아래에서 더한다
		"player_scale": Vector2.ONE, "echo_scale": 1.0, "echo_trail": [], "flying": [], "wobble": Rules.NO_CELL,
	}
	var blast_killed: Dictionary = {}       # 적 id -> true (폭발에 휘말림, 턴 끝에 사라진다)

	var t_hit := t_echo + T_ECHO      # 메아리의 일격이 닿는 순간
	var moved: Dictionary = {}        # 적 id -> 도착 칸 (적 행동 단계의 이동)
	var pushed: Dictionary = {}       # 적 id -> 밀려난 칸 (메아리 단계)
	var crushed: Dictionary = {}      # 적 id -> 막힌 방향
	var deflected: Dictionary = {}    # 적 id -> true (방패가 튕김)
	var new_hp: Dictionary = {}       # 적 id -> [바뀌는 시각, 체력]
	var echo_killed: Dictionary = {}  # 적 id -> 사라지는 시각 (메아리 처치·으깨기)
	var shot_killed: Dictionary = {}  # 적 id -> true (오사)
	for e in events:
		match e["type"]:
			"move":
				view["player_px"] = _cell_center(e["from"]).lerp(_cell_center(e["to"]), k_move)
				# 이동 방향으로 늘어났다가(가는 동안) 도착해서 눌린다
				var mdir: Vector2i = e["to"] - e["from"]
				var st := 0.0
				if t < T_MOVE:
					st = 0.15 * sin(PI * k_move)
				elif t < T_MOVE + 0.08:
					st = -0.15 * (1.0 - (t - T_MOVE) / 0.08)
				view["player_scale"] = Vector2(1.0 + st, 1.0 - st * 0.6) if mdir.x != 0 else Vector2(1.0 - st * 0.6, 1.0 + st)
			"slash":
				pass  # 칼 궤적은 arcs 가 그린다(호)
			"echo":
				var from_px: Vector2 = _cell_center(snap["echo_pos"]) if snap["echo"] else _cell_center(e["pos"])
				view["echo_px"] = from_px.lerp(_cell_center(e["pos"]), k_echo)
				# 명중 순간에는 불투명해진다
				var hit := t >= t_echo + T_ECHO and t < t_enemy and t_enemy - t_echo > T_ECHO
				view["echo_alpha"] = 1.0 if hit else (0.55 if snap["echo"] else 0.55 * k_echo)
				view["echo_cell"] = e["pos"]
				view["blocked_echo"] = true
				if Rules.is_move(e["act"]) and t >= t_echo:
					# 밟기 동작: 위에서 내려찍는다(1.35 → 1.0). 뒤에 잔상 3개
					view["echo_scale"] = 1.35 - 0.35 * k_echo
					if t < t_hit:
						for gi in range(1, 4):
							var gk := k_echo - 0.2 * gi
							if gk > 0.0:
								view["echo_trail"].append({"pos": from_px.lerp(_cell_center(e["pos"]), gk), "alpha": 0.4 - 0.1 * gi})
			"echo_slash":
				pass  # 메아리의 칼 궤적도 arcs 가 그린다
			"kill":
				if e.get("blast", false):
					blast_killed[e["id"]] = true
				elif e["src"] == "friendly":
					shot_killed[e["id"]] = true
				else:
					echo_killed[e["id"]] = t_enemy if e["src"] == "crush" else t_hit
			"push":
				pushed[e["id"]] = e["to"]
				new_hp[e["id"]] = [t_hit, e["hp"]]
			"crush":
				crushed[e["id"]] = e["dir"]
				if t >= t_hit and t < t_enemy + 0.1:
					view["wobble"] = e["pos"] + e["dir"]   # 막은 칸(벽이면 흔들린다)
			"deflect":
				deflected[e["id"]] = true
			"arrow_hit":
				new_hp[e["id"]] = [t_enemy + T_ENEMY * 0.6, e["hp"]]
			"blast_hit":
				new_hp[e["id"]] = [t_end, e["hp"]]
			"throw":
				# 폭탄이 폭탄병에서 대상 칸으로 포물선을 그리며 날아가(적 행동 구간) 턴 끝에 놓인다
				if t >= t_enemy and t < t_end:
					var fp := _cell_center(e["from"]).lerp(_cell_center(e["to"]), k_enemy)
					view["flying"].append(fp + Vector2(0, -46.0 * sin(PI * k_enemy)))
				elif t >= t_end:
					view["bombs"] = view["bombs"] + [{"pos": e["to"], "fuse": 1}]
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
		var id: int = e["id"]
		var cell: Vector2i = e["pos"]
		var px := _cell_center(cell)
		var alpha := 1.0
		var ehp: int = e["hp"]
		var squash := 0.0
		if new_hp.has(id) and t >= new_hp[id][0]:
			ehp = new_hp[id][1]
		if pushed.has(id):
			# 히트스톱 동안 일격 방향으로 한 칸 미끄러진다
			var k_push := clampf((t - t_hit) / T_STOP, 0.0, 1.0)
			px = px.lerp(_cell_center(pushed[id]), k_push)
			if t >= t_hit:
				cell = pushed[id]
		if crushed.has(id) and t >= t_hit:
			# 으깨기: 막힌 쪽으로 반 칸 가다 납작해진다
			squash = clampf((t - t_hit) / T_STOP, 0.0, 1.0)
			px += Vector2(crushed[id]) * CELL * 0.3 * squash
			ehp = 1
		if echo_killed.has(id) and t >= echo_killed[id]:
			alpha = 0.0
		if moved.has(id):
			px = px.lerp(_cell_center(moved[id]), k_enemy)
		if shot_killed.has(id) and t >= t_enemy + T_ENEMY * 0.6:
			alpha = 0.0
		if blast_killed.has(id) and t >= t_end:
			alpha = 0.0
		view["enemies"].append({"id": id, "kind": e["kind"], "cell": cell, "pos": px, "intent": e["intent"], "dir": e["dir"], "alpha": alpha,
			"hp": ehp, "face": e["face"], "flash": deflected.has(id) and t >= t_hit and t < t_hit + 0.2, "squash": squash, "target": e["target"]})
	# 이번 턴에 터진 폭탄은 폭발 시각(t_end)부터 그리지 않는다
	if t >= t_end:
		var exploded: Array = []
		for e in events:
			if e["type"] == "explode":
				exploded.append(e["pos"])
		view["bombs"] = view["bombs"].filter(func(b): return not exploded.has(b["pos"]))

	# 증원은 턴 끝에 등장
	if t >= t_end:
		for e in events:
			if e["type"] == "spawn":
				view["enemies"].append({"id": e["id"], "kind": e["kind"], "cell": e["pos"], "pos": _cell_center(e["pos"]), "intent": "none", "dir": Vector2i.ZERO, "alpha": 1.0,
					"hp": Rules.ENEMY_HP.get(e["kind"], 1), "face": Vector2i(0, 1), "flash": false, "squash": 0.0, "target": Rules.NO_CELL})
	return view


func _draw_aim_ray(from: Vector2i, dir: Vector2i, view: Dictionary) -> void:
	var occupied: Dictionary = {}
	for e in view["enemies"]:
		if e["alpha"] > 0.5:
			occupied[e["cell"]] = true
	var q := from + dir
	var last := from
	# 빗금이 화살 방향으로 흐른다(초당 24px)
	var gap := CELL / 2.0
	var flow := fposmod(clock * 24.0 * (1.0 if dir.x + dir.y > 0 else -1.0), gap)
	while Rules.inb(q) and not view["walls"].has(q) and not occupied.has(q) and not (view["blocked_echo"] and q == view["echo_cell"]):
		var r := _cell_rect(q)
		var c := flow
		while c < CELL * 2.0:
			if c > 0.0:
				var a := Vector2(minf(c, CELL), c - minf(c, CELL))
				var b := Vector2(c - minf(c, CELL), minf(c, CELL))
				draw_line(r.position + a, r.position + b, Color(C_DANGER, 0.55), 2.0)
			c += gap
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
	# 조각(처치, 먼지, 불꽃, 불씨)
	_draw_parts(parts)
	parts = parts.filter(func(x): return clock - x["t0"] <= x["life"])
	# 밀치기 궤적: 밀린 방향으로 짧은 선 3개
	for sk in streaks:
		var skt: float = clock - sk["t0"]
		if skt < 0.0 or skt > 0.25:
			continue
		var d: Vector2 = (sk["to"] - sk["from"]).normalized()
		var side := Vector2(-d.y, d.x)
		for i in 3:
			var o := side * (i - 1) * 12.0
			draw_line(sk["from"] + o - d * 6, sk["from"] + o + d * 22, Color(C_TEXT, 0.8 * (1.0 - skt / 0.25)), 3.0)
	streaks = streaks.filter(func(x): return clock - x["t0"] <= 0.25)
	# 칼 궤적: 대상 쪽으로 90° 호. 다 그린 뒤 0.15초 잔광
	for ar in arcs:
		var at: float = clock - ar["t0"]
		if at < 0.0 or at > 0.27:
			continue
		var a0: float = ar["dir"].angle()
		var k := clampf(at / 0.12, 0.0, 1.0)
		var col: Color = ar["color"]
		col.a = 1.0 if at < 0.12 else 1.0 - (at - 0.12) / 0.15
		draw_arc(ar["pos"], CELL * 0.82, a0 - PI / 4, a0 - PI / 4 + PI / 2 * k, 14, col, 6.0)
		draw_arc(ar["pos"], CELL * 0.62, a0 - PI / 4, a0 - PI / 4 + PI / 2 * k, 14, Color(col, col.a * 0.4), 3.0)
	arcs = arcs.filter(func(x): return clock - x["t0"] <= 0.27)
	# 충격 고리
	for rg in rings:
		var rgt: float = clock - rg["t0"]
		if rgt < 0.0 or rgt > 0.3:
			continue
		draw_arc(rg["pos"], 18.0 + 34.0 * rgt / 0.3, 0, TAU, 28, Color(rg["color"], 1.0 - rgt / 0.3), 4.0)
	rings = rings.filter(func(x): return clock - x["t0"] <= 0.3)
	# 막음 파문
	for rp in ripples:
		var rt: float = clock - rp["t0"]
		if rt < 0.0 or rt > 0.4:
			continue
		draw_arc(rp["pos"], 24.0 + 30.0 * rt / 0.4, 0, TAU, 32, Color(C_ECHO, 1.0 - rt / 0.4), 3.0)
	# 폭발: 범위 칸이 밝게 번쩍이고 고리가 퍼진다
	for bl in blasts:
		var blt: float = clock - bl["t0"]
		if blt < 0.0 or blt > 0.35:
			continue
		var bk := blt / 0.35
		for c in bl["cells"]:
			draw_rect(_cell_rect(c).grow(-2), Color(C_DANGER, 0.85 * (1.0 - bk)))
		draw_arc(_cell_center(bl["pos"]), 20.0 + CELL * 1.3 * bk, 0, TAU, 32, Color(C_TEXT, 1.0 - bk), 4.0)
	blasts = blasts.filter(func(x): return clock - x["t0"] <= 0.35)
	# 층 클리어: 발자국이 빛나며 사라진다
	for g in glows:
		var gt: float = clock - g["t0"]
		if gt < 0.0 or gt > T_GLOW:
			continue
		var gk := gt / T_GLOW
		draw_circle(g["pos"], 13.0 + 10.0 * gk, Color(C_ECHO, 0.5 * (1.0 - gk)))
		draw_arc(g["pos"], 13.0 + 22.0 * gk, 0, TAU, 24, Color(C_TEXT, 1.0 - gk), 3.0)
	glows = glows.filter(func(x): return clock - x["t0"] <= T_GLOW)
	# 글자("층 클리어!"는 크게)
	for q in popups:
		var pt: float = clock - q["t0"]
		if pt < 0.0 or pt > T_POPUP:
			continue
		var col: Color = q["color"]
		col.a = 1.0 - pt / T_POPUP
		var size := 34 if q.get("big", false) else 22
		draw_string(font, q["pos"] + Vector2(-120, -30 - 20 * pt / T_POPUP), q["text"], HORIZONTAL_ALIGNMENT_CENTER, 240, size, col)
	popups = popups.filter(func(x): return clock - x["t0"] <= T_POPUP)
	ripples = ripples.filter(func(x): return clock - x["t0"] <= 0.4)


func _draw_hurt_border() -> void:
	var ht := clock - hurt_t0
	if ht >= 0.0 and ht < T_HURT:
		draw_rect(Rect2(4, 4, W - 8, H - 8), Color(C_HURT, 1.0 - ht / T_HURT), false, 10.0)


func _draw_player(pos: Vector2, low: bool, broken: bool, sword := true, sc := Vector2.ONE) -> void:
	# 바닥의 그림자(크기는 그대로 두어 숨쉬기가 보이게)
	_draw_shadow(pos + Vector2(0, 23), 20.0, Color(0, 0, 0, 0.35))
	# 옅은 기운이 숨쉬기에 맞춰 커졌다 작아진다
	draw_arc(pos, 31.0 + 2.5 * sin(TAU * clock / 1.4), 0, TAU, 32, Color(C_PLAYER, 0.16), 2.0)
	_push_scale(pos, sc)
	draw_circle(pos, 22, C_PLAYER)
	if sword:
		# 칼이 손에 있다: 오른쪽 아래의 짧은 칼 선(발자국은 칸의 왼쪽 위·오른쪽 위·왼쪽 아래에 그려지므로 가리지 않는다)
		draw_line(pos + Vector2(13, 13), pos + Vector2(29, 29), C_PLAYER, 4.0)
		draw_line(pos + Vector2(12, 20), pos + Vector2(20, 12), C_PLAYER, 3.0)
	if broken:
		# 피격: 깨진 외곽선
		for i in 6:
			draw_arc(pos, 29, i * TAU / 6 + 0.15, i * TAU / 6 + 0.7, 6, C_HURT, 4.0)
	elif low:
		_draw_dashed_circle(pos, 29, C_HURT, 3.0, clock * 2.0)
	_pop_scale()


func _draw_shadow(pos: Vector2, rx: float, color: Color) -> void:
	var sh := PackedVector2Array()
	for i in 16:
		sh.append(pos + Vector2(cos(TAU * i / 16.0) * rx, sin(TAU * i / 16.0) * rx * 0.3))
	draw_colored_polygon(sh, color)


func _draw_echo(pos: Vector2, alpha: float, sc := 1.0) -> void:
	# 몸은 옅게 일렁이고 점선 외곽은 4초에 한 바퀴 돈다
	var body := (0.35 * alpha / 0.55 if alpha < 1.0 else 0.95) + 0.08 * sin(TAU * clock / 1.1) * (1.0 if alpha < 1.0 else 0.0)
	_push_scale(pos, Vector2(sc, sc))
	draw_circle(pos, 22, Color(C_ECHO, clampf(body, 0.0, 1.0)))
	_draw_dashed_circle(pos, 26, Color(C_ECHO, minf(1.0, alpha + 0.3)), 2.5, clock * TAU / 4.0)
	_pop_scale()


func _draw_dashed_circle(pos: Vector2, radius: float, color: Color, width: float, phase := 0.0) -> void:
	for i in 10:
		draw_arc(pos, radius, phase + i * TAU / 10, phase + i * TAU / 10 + TAU / 20, 5, color, width)


func _draw_enemy(pos: Vector2, kind: String, facing: Vector2i, alpha: float, ehp := 1, face := Vector2i(0, 1), flash := false, squash := 0.0) -> void:
	var col := Color(C_ENEMY, alpha)
	if kind == "W":
		draw_rect(Rect2(pos - Vector2(20, 20), Vector2(40, 40)), col)
	elif kind == "B":
		# 폭탄병: 원 + 위로 뻗은 심지 선, 끝에 작은 점 (플레이어의 흰 원과 색·심지로 구분)
		draw_circle(pos + Vector2(0, 3), 19, col)
		draw_line(pos + Vector2(0, -16), pos + Vector2(7, -27), col, 4.0)
		draw_circle(pos + Vector2(7, -27), 4.5, Color(C_DANGER, alpha))
	elif kind == "S":
		# 방패병: 정사각형 + 바라보는 쪽 변의 두꺼운 밝은 막대(방패). 으깨질 때는 막힌 방향으로 납작해진다
		var half := Vector2(20, 20)
		if squash > 0.0:
			half = Vector2(20, 20) * (1.0 - 0.45 * squash)
		draw_rect(Rect2(pos - half, half * 2), col)
		var f := Vector2(face)
		var side := Vector2(-f.y, f.x)
		var a := pos + f * 22 - side * 23
		var b := pos + f * 22 + side * 23
		draw_line(a, b, Color(C_TEXT if flash else C_SHIELD, alpha), 12.0 if flash else 8.0)
		# 남은 체력만큼 점
		for i in ehp:
			draw_circle(pos + Vector2((i - (ehp - 1) / 2.0) * 13, 0) - f * 3, 4.5, Color(C_BG, alpha))
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
## 칼이 실린 발자국(베기)은 테두리와 칼 선을 굵게. flash 면 밝게 깜빡인다(칼이 어디 있는지 가리킴)
func _draw_footprint(pos: Vector2, order: int, act: String, big: bool, flash := false, pulse := 1.0) -> void:
	var radius := (18.0 if big else 13.0) * pulse
	var sword := Rules.is_slash(act)
	var ring := C_TEXT if sword and flash else C_ECHO
	draw_circle(pos, radius, Color(C_ECHO, 0.9) if sword and flash else Color(C_BG, 0.75))
	draw_arc(pos, radius, 0, TAU, 20, ring, 4.0 if sword else 2.0)
	var size := 24 if big else 19
	draw_string(font, pos + Vector2(-radius, size * 0.36), str(order), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, size, C_TEXT)
	if sword:
		var d := Vector2(Rules.act_dir(act))
		draw_line(pos + d * radius, pos + d * (radius + 14), ring, 6.0)


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


## 놓인 폭탄(또는 던질 자리): 검은 원 + 심지
func _draw_bomb(pos: Vector2, alpha: float, hot := false) -> void:
	# 남은 턴 1이면 떨린다. 심지 끝의 불꽃은 늘 깜빡인다
	if hot:
		pos += Vector2(sin(clock * 50.0), cos(clock * 43.0)) * 1.5
	draw_circle(pos, 13, Color(C_BG, alpha))
	draw_arc(pos, 13, 0, TAU, 20, Color(C_DANGER, alpha), 3.0)
	draw_line(pos + Vector2(6, -11), pos + Vector2(12, -19), Color(C_DANGER, alpha), 3.0)
	var spark := 0.5 + 0.5 * sin(TAU * clock / 0.2)
	draw_circle(pos + Vector2(12, -19), 2.5 + 2.0 * spark, Color(C_TEXT.lerp(C_DANGER, spark), alpha))


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color) -> void:
	var n := maxi(2, int(from.distance_to(to) / 14.0))
	for i in n:
		if i % 2 == 0:
			draw_line(from.lerp(to, float(i) / n), from.lerp(to, float(i + 1) / n), color, 3.0)


func _draw_small_button(rect: Rect2, label: String, enabled: bool) -> void:
	draw_rect(rect, C_PANEL if enabled else Color(C_PANEL, 0.5))
	if enabled:
		draw_rect(rect, C_GRID, false, 2.0)
	else:
		_draw_dashed_rect(rect, C_GRID)
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y / 2 + 7), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, C_TEXT if enabled else C_MUTED)


func _draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var step := 16.0
	var x := rect.position.x
	while x < rect.end.x:
		var x2 := minf(x + step * 0.55, rect.end.x)
		draw_line(Vector2(x, rect.position.y), Vector2(x2, rect.position.y), color, 2.0)
		draw_line(Vector2(x, rect.end.y), Vector2(x2, rect.end.y), color, 2.0)
		x += step
	var y := rect.position.y
	while y < rect.end.y:
		var y2 := minf(y + step * 0.55, rect.end.y)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, y2), color, 2.0)
		draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x, y2), color, 2.0)
		y += step


## 칼이 없을 때의 베기 버튼: 어둡게, 점선 테두리, "칼" + 돌아올 때까지 남은 턴(발자국과 같은 원 숫자)
func _draw_sword_button(rect: Rect2, wait_turns: int) -> void:
	draw_rect(rect, Color(C_PANEL, 0.5))
	var step := 16.0
	var x := rect.position.x
	while x < rect.end.x:
		var x2 := minf(x + step * 0.55, rect.end.x)
		draw_line(Vector2(x, rect.position.y), Vector2(x2, rect.position.y), C_GRID, 2.0)
		draw_line(Vector2(x, rect.end.y), Vector2(x2, rect.end.y), C_GRID, 2.0)
		x += step
	var y := rect.position.y
	while y < rect.end.y:
		var y2 := minf(y + step * 0.55, rect.end.y)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, y2), C_GRID, 2.0)
		draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x, y2), C_GRID, 2.0)
		y += step
	var c := rect.get_center()
	draw_string(font, Vector2(rect.position.x, c.y + 9), "칼", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 44, 26, C_MUTED)
	_draw_footprint(c + Vector2(26, 0), wait_turns, "SR", true)


# ---------------------------------------------------------------- 입력 흉내 (tests/)

func debug_tap(pos: Vector2) -> void:
	_press(pos)
	_release(pos)


func debug_swipe(from: Vector2, to: Vector2) -> void:
	_press(from)
	_drag(to)
	_release(to)


func debug_press(id: String) -> void:
	var rect: Rect2 = {"slash": BTN_SLASH, "rewind": BTN_REWIND}.get(id, BTN_WAIT)
	debug_tap(rect.get_center())


func debug_rewind() -> bool:
	return _do_rewind()


func debug_act(action: String) -> bool:
	return _do_action(action)


func debug_load_floors(new_floors: Array) -> void:
	_start_run(new_floors, [])
