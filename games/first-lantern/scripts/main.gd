extends Node2D
## First Lantern — 꺼지기 전에 등불을 눌러 밝히는 한 손가락 게임.
## 단비의 게임회사2 파이프라인(빌드 → CI → Web → 플레이테스트) 시험용.

enum State { TITLE, PLAY, RESULT }

const W := 540.0
const H := 960.0
const ROUND_SECONDS := 45.0
const LIVES := 3
const LANTERN_LIFE := 1.8
const HIT_RADIUS := 64.0
const BEST_PATH := "user://best.save"

const C_BG := Color("07111e")
const C_TEXT := Color("edf4ff")
const C_MUTED := Color("8fa3bf")
const C_WARM := Color("f3c86a")
const C_LIT := Color("55d6a8")
const C_MISS := Color("ff7d8e")

var state: State = State.TITLE
var score := 0
var best := 0
var lives := LIVES
var time_left := ROUND_SECONDS
var spawn_timer := 0.0
var lanterns: Array[Dictionary] = []  # {pos, age, lit, lit_age}
var sparks: Array[Dictionary] = []    # {pos, age, color}
var rng := RandomNumberGenerator.new()
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	rng.randomize()
	best = _load_best()


func _process(delta: float) -> void:
	if state == State.PLAY:
		_update_play(delta)
	for s in sparks:
		s.age += delta
	sparks = sparks.filter(func(s): return s.age < 0.5)
	queue_redraw()


func _update_play(delta: float) -> void:
	time_left -= delta
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_lantern(Vector2(rng.randf_range(70, W - 70), rng.randf_range(170, H - 140)))
		# 시간이 갈수록 빨라진다: 0.9초 → 0.38초
		var progress := 1.0 - time_left / ROUND_SECONDS
		spawn_timer = lerpf(0.9, 0.38, progress)

	var keep: Array[Dictionary] = []
	for l in lanterns:
		l.age += delta
		if l.lit:
			l.lit_age += delta
			if l.lit_age < 0.35:
				keep.append(l)
		elif l.age >= LANTERN_LIFE:
			_miss(l.pos)
		else:
			keep.append(l)
	lanterns = keep

	if lives <= 0 or time_left <= 0.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tap(event.position)


func _tap(pos: Vector2) -> void:
	match state:
		State.TITLE, State.RESULT:
			_start()
		State.PLAY:
			var target := -1
			var nearest := HIT_RADIUS
			for i in lanterns.size():
				var l: Dictionary = lanterns[i]
				if l.lit:
					continue
				var d := pos.distance_to(l.pos)
				if d <= nearest:
					nearest = d
					target = i
			if target >= 0:
				lanterns[target].lit = true
				score += 1
				sparks.append({"pos": lanterns[target].pos, "age": 0.0, "color": C_LIT})


func _start() -> void:
	state = State.PLAY
	score = 0
	lives = LIVES
	time_left = ROUND_SECONDS
	spawn_timer = 0.3
	lanterns.clear()
	sparks.clear()


func _spawn_lantern(pos: Vector2) -> Dictionary:
	var l := {"pos": pos, "age": 0.0, "lit": false, "lit_age": 0.0}
	lanterns.append(l)
	return l


func _miss(pos: Vector2) -> void:
	lives -= 1
	sparks.append({"pos": pos, "age": 0.0, "color": C_MISS})


func _finish() -> void:
	state = State.RESULT
	lanterns.clear()
	if score > best:
		best = score
		_save_best(best)


func _load_best() -> int:
	if not FileAccess.file_exists(BEST_PATH):
		return 0
	var f := FileAccess.open(BEST_PATH, FileAccess.READ)
	return f.get_32() if f else 0


func _save_best(value: int) -> void:
	var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
	if f:
		f.store_32(value)


# ---------- 그리기 ----------

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), C_BG)
	match state:
		State.TITLE:
			_text("FIRST LANTERN", Vector2(0, 360), 44, C_WARM)
			_text("꺼지기 전에 등불을 눌러 밝히세요", Vector2(0, 430), 22, C_TEXT)
			_text("세 번 놓치면 끝 · 45초", Vector2(0, 468), 18, C_MUTED)
			_draw_lantern(Vector2(W / 2, 580), 0.4, false, 0.0)
			_text("화면을 눌러 시작", Vector2(0, 720), 22, C_TEXT)
			if best > 0:
				_text("최고 기록 %d" % best, Vector2(0, 760), 18, C_MUTED)
		State.PLAY:
			for l in lanterns:
				_draw_lantern(l.pos, l.age / LANTERN_LIFE, l.lit, l.lit_age)
			_draw_hud()
		State.RESULT:
			_text("밤이 끝났어요", Vector2(0, 360), 36, C_TEXT)
			_text("밝힌 등불 %d" % score, Vector2(0, 440), 30, C_WARM)
			_text("최고 기록 %d" % best, Vector2(0, 484), 20, C_MUTED)
			_text("화면을 눌러 다시", Vector2(0, 640), 22, C_TEXT)
	for s in sparks:
		var t: float = s.age / 0.5
		var c: Color = s.color
		c.a = 1.0 - t
		draw_arc(s.pos, 30.0 + 50.0 * t, 0, TAU, 40, c, 4.0)


func _draw_hud() -> void:
	draw_string(font, Vector2(28, 64), "%d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, C_WARM)
	draw_string(font, Vector2(0, 64), "%d" % ceili(time_left), HORIZONTAL_ALIGNMENT_RIGHT, W - 28, 28, C_MUTED)
	for i in LIVES:
		var c := C_WARM if i < lives else Color(C_MUTED, 0.3)
		draw_circle(Vector2(W / 2 - 30 + i * 30, 52), 9, c)


func _draw_lantern(pos: Vector2, life: float, lit: bool, lit_age: float) -> void:
	if lit:
		var g := 1.0 - lit_age / 0.35
		draw_circle(pos, 40 + 30 * (1.0 - g), Color(C_LIT, 0.25 * g))
		draw_circle(pos, 26, Color(C_LIT, g))
		return
	# 불빛은 켜졌다가 수명 끝으로 갈수록 흐려진다
	var glow := clampf(1.0 - life, 0.0, 1.0)
	draw_circle(pos, 54, Color(C_WARM, 0.10 * glow))
	draw_circle(pos, 36, Color(C_WARM, 0.25 * glow))
	draw_circle(pos, 24, Color(C_WARM, 0.35 + 0.65 * glow))
	draw_arc(pos, 44, -PI / 2, -PI / 2 + TAU * glow, 40, Color(C_TEXT, 0.5), 3.0)


func _text(s: String, pos: Vector2, size: int, color: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, W, size, color)


# ---------- 테스트용 훅 (tests/smoke.gd) ----------

func debug_tap(pos: Vector2) -> void:
	_tap(pos)


func debug_spawn(pos: Vector2) -> void:
	spawn_timer = 99.0
	_spawn_lantern(pos)
