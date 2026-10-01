extends Node2D
## 같은 하루 — 첫 빌드(기획 v1). 상태·입력·그리기·실시간.
## 규칙은 scripts/rules.gd (design/sim/sim.py Day 대응), 콘텐츠는 scripts/content.gd.
## 규칙은 틱이 넘어가는 순간 끝까지 계산되고, 화면은 그 결과를 보간해 보여 줄 뿐이다. 입력을 막는 연출은 없다.

enum State { TITLE, DAY, NOTEBOOK, RESULT }

const Rules := preload("res://scripts/rules.gd")
const Content := preload("res://scripts/content.gd")

const W := 540.0
const H := 960.0
const TAP_RADIUS := 36.0                  # 장소 탭 대상: 지름 72px
const TAP_SLOP := 24.0
const SLEEP_HOLD := 0.6
const BAND_X0 := 40.0
const BAND_X1 := 500.0
const BAND_Y := 30.0
const PANEL := Rect2(8, 572, 524, 276)
const BTN_Y := 858.0
const BTN_H := 90.0
const BTN_W := 120.0
const BTN_GAP := 12.0
const BTN_IDS: Array[String] = ["notebook", "fast", "clear", "sleep"]
const NB_TICK_W := 24.0
const NB_X := 70.0
const NB_ROW_Y := 150.0
const NB_ROW_H := 84.0
const NB_CLOSE := Rect2(396, 20, 128, 56)
const PLACE_POS := {
	"inn": Vector2(446, 330), "bakery": Vector2(400, 482), "plaza": Vector2(270, 306), "post": Vector2(404, 150),
	"smithy": Vector2(132, 482), "tower": Vector2(136, 150), "dock": Vector2(70, 322),
}
const SMOKE_AT := {"C_smoke": "bakery"}      # 먼 신호가 지도에서 보이는 자리

const C_PAPER := Color("e9dfc6")
const C_PAPER2 := Color("ddd0b0")
const C_INK := Color("2f2a24")
const C_DIM := Color("8d826e")
const C_RED := Color("c2452d")
const C_BLUE := Color("3b6ea5")
const C_GREEN := Color("4d8a4f")
const C_GOLD := Color("c79a2e")

var state: State = State.TITLE
var font: Font
var rules: RefCounted
var fast := false
var acc := 0.0                             # 틱 사이에 쌓인 실시간

var loop: int:
	get: return rules.loop
var tick: int:
	get: return rules.tick
var place: String:
	get: return rules.place
var walk_from: String:
	get: return rules.walk_from
var walk_to: String:
	get: return rules.walk_to
var walk_left: int:
	get: return rules.walk_left
var acting: String:
	get: return rules.acting
var items: Array:
	get: return rules.items
var flags: Array:
	get: return rules.sorted_flags()
var notes: Array:
	get: return rules.notes
var new_notes: Array:
	get: return rules.new_notes
var done: Array:
	get: return rules.done
var queue: Array:
	get: return rules.queue
var choices: Array:
	get: return rules.choices() if state == State.DAY else []
var late_choices: Array:
	get: return rules.late_choices() if state == State.DAY else []
var last_missed: String:
	get: return rules.last_missed
var solved: bool:
	get: return rules.solved
var result_solved: bool:
	get: return rules.result_solved
var result_new: Array:
	get: return rules.result_new
var result_late: Array:
	get: return rules.result_late

# 화면
var clk := 0.0
var pressing := false
var press_pos := Vector2.ZERO
var sleep_holding := false
var sleep_t := 0.0
var walk_u0 := 0.0                         # 걷기 시작한 순간이 그 틱의 어디였는가(0~1)
var fx: Array = []
var feed_text := ""
var feed_ttl := 0.0
var hint_text := ""
var hint_ttl := 0.0
var nb_scroll := 0.0
var nb_sel := ""
var nb_dragging := false
var missed_shown := false                  # "놓쳤다" 줄은 다음 입력까지 보인다


func _ready() -> void:
	font = load("res://assets/fonts/NotoSansKR-Medium.ttf")
	debug_reset()


func _process(delta: float) -> void:
	clk += delta
	for f in fx:
		f["t"] += delta
	fx = fx.filter(func(f): return f["t"] < f["d"])
	feed_ttl = maxf(0.0, feed_ttl - delta)
	hint_ttl = maxf(0.0, hint_ttl - delta)
	if sleep_holding and state == State.DAY:
		sleep_t += delta
		if sleep_t >= SLEEP_HOLD:
			sleep_holding = false
			_sleep()
	_advance(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
	elif event is InputEventScreenDrag and state == State.NOTEBOOK:
		nb_scroll = clampf(nb_scroll - event.relative.x, 0.0, _nb_max_scroll())
		if event.relative.length() > 2.0:
			nb_dragging = true


# ---------------------------------------------------------------- 시간

func _tick_len() -> float:
	return rules.fast_seconds if fast else rules.tick_seconds


## 실시간이 흐른다. DAY 에서만 쌓인다. debug_step 과 _process 가 같은 길.
func _advance(seconds: float) -> void:
	if state != State.DAY:
		return
	acc += seconds
	while state == State.DAY and acc >= _tick_len():
		acc -= _tick_len()
		_tick()


func _tick() -> void:
	rules.tick_once()
	_after_rules()
	_add_fx("tick", 0.2, {})
	if rules.over:
		_to_result()


func _after_rules() -> void:
	for e in rules.ev:
		match e["e"]:
			"note":
				_add_fx("newnote", 1.6, {"id": e["id"]})
			"walk":
				walk_u0 = clampf(acc / _tick_len(), 0.0, 0.95)
				feed_ttl = 0.0
			"flag":
				if rules.goal.has(e["id"]) and _goal_now():
					_add_fx("goal", 4.0, {})
			"arrive":
				_add_fx("arrive", 0.15, {})
			"act_done":
				feed_text = str(rules.act[e["id"]]["text"])
				feed_ttl = 5.0
				_add_fx("react", 1.2, {"npc": rules.act[e["id"]]["npc"]})
			"missed":
				_add_fx("missed", 0.3, {})
				missed_shown = true
	rules.ev = []


## 이번 하루에 목표 표지가 전부 섰는가(표시용. 도장은 하루가 끝날 때 찍힌다).
func _goal_now() -> bool:
	for f in rules.goal:
		if not rules.flags.has(f):
			return false
	return not rules.goal.is_empty()


func _start_day() -> void:
	missed_shown = false
	rules.start_day()
	state = State.DAY
	acc = 0.0
	fast = false
	sleep_holding = false
	feed_ttl = 0.0
	fx.clear()
	_after_rules()


func _sleep() -> void:
	if state != State.DAY:
		return
	rules.end_day()
	_to_result()


func _to_result() -> void:
	state = State.RESULT
	fast = false
	sleep_holding = false
	_add_fx("dusk", 0.4, {})
	if rules.result_solved:
		_add_fx("stamp", 0.5, {})


# ---------------------------------------------------------------- 입력 (실제 터치와 debug_* 가 같은 길)

func _press(p: Vector2) -> void:
	pressing = true
	press_pos = p
	nb_dragging = false
	if state == State.DAY:
		var id := _button_at(p)
		if id == "fast":
			fast = true
		elif id == "sleep":
			sleep_holding = true
			sleep_t = 0.0


func _release(p: Vector2) -> void:
	if not pressing:
		return
	pressing = false
	if fast:
		fast = false
	if sleep_holding:
		sleep_holding = false
		if sleep_t < SLEEP_HOLD:
			_hint("길게 눌러 잠들기")
		return
	if p.distance_to(press_pos) > TAP_SLOP or nb_dragging:
		return
	_tap(press_pos)


func _tap(p: Vector2) -> void:
	match state:
		State.TITLE:
			_start_day()
		State.RESULT:
			_start_day()
		State.NOTEBOOK:
			if NB_CLOSE.has_point(p) or p.y >= BTN_Y:
				_button("close")
			else:
				_nb_tap(p)
		State.DAY:
			var id := _button_at(p)
			if id != "":
				if id == "notebook" or id == "clear":
					_button(id)
				return
			for c in _choice_layout():
				if (c["rect"] as Rect2).has_point(p):
					if c["kind"] == "choice":
						_choose(c["id"])
					elif c["kind"] == "late":
						_hint("늦었다 — %s까지" % _deadline(c["id"]))
					return
			var pl := _place_at(p)
			if pl != "":
				_go(pl)


func _go(pl: String) -> bool:
	if state != State.DAY:
		return false
	var okay: bool = rules.go(pl)
	if okay:
		missed_shown = false
		_after_rules()
		_add_fx("flag", 0.25, {"place": pl})
	else:
		_add_fx("shake", 0.25, {"place": pl})
		if pl == rules.place or pl == rules.end_place():
			_hint("이미 여기다")
		elif rules.busy() and rules.queue.size() >= rules.max_queue:
			_hint("예약은 %d개까지" % rules.max_queue)
		elif rules.places.has(pl):
			_hint("오늘 안에 못 닿는다")
	return okay


func _choose(id: String) -> bool:
	if state != State.DAY:
		return false
	var okay: bool = rules.choose(id)
	if okay:
		missed_shown = false
		_after_rules()
	return okay


func _button(id: String) -> void:
	match id:
		"notebook":
			if state == State.DAY:
				state = State.NOTEBOOK
				fast = false
				nb_sel = str(rules.new_notes[-1]) if not rules.new_notes.is_empty() else (str(rules.notes[-1]) if not rules.notes.is_empty() else "")
				var first: int = rules.tick
				for n in rules.notes:
					var o: Dictionary = rules.scene_of(n)
					if not o.is_empty():
						first = mini(first, int(o["t0"]))
				nb_scroll = clampf(first * NB_TICK_W - 24.0, 0.0, _nb_max_scroll())      # 가장 이른 장면부터 보이게
		"close":
			if state == State.NOTEBOOK:
				state = State.DAY
		"fast_down":
			if state == State.DAY:
				fast = true
		"fast_up":
			fast = false
		"sleep":
			_sleep()
		"clear":
			if state == State.DAY:
				rules.clear_queue()
		_:
			if id.begins_with("choice:"):
				_choose(id.substr(7))


func _button_rect(i: int) -> Rect2:
	return Rect2(BTN_GAP + i * (BTN_W + BTN_GAP), BTN_Y, BTN_W, BTN_H)


func _button_at(p: Vector2) -> String:
	for i in BTN_IDS.size():
		if _button_rect(i).has_point(p):
			return BTN_IDS[i]
	return ""


func _place_pos(pl: String) -> Vector2:
	if PLACE_POS.has(pl):
		return PLACE_POS[pl]
	var i: int = rules.places.find(pl)       # 기본 콘텐츠에 없는 장소(장면용): 원 위에 늘어놓는다
	var n: int = maxi(1, rules.places.size())
	return Vector2(270, 320) + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * 150.0


func _place_at(p: Vector2) -> String:
	var best := ""
	var best_d := TAP_RADIUS
	for pl in rules.places:
		var d := p.distance_to(_place_pos(pl))
		if d <= best_d:
			best = pl
			best_d = d
	return best


## 장면 창의 단추 배치. 그리기와 입력이 같이 쓴다. kind: queued(예약됨) / choice / late
func _choice_layout() -> Array:
	var out: Array = []
	if state != State.DAY:
		return out
	for i in rules.queue.size():
		if rules.act.has(rules.queue[i]):
			out.append({"kind": "queued", "id": rules.queue[i], "n": i + 1})
	for id in rules.choices():
		out.append({"kind": "choice", "id": id})
	for id in rules.late_choices():
		out.append({"kind": "late", "id": id})
	for i in out.size():
		out[i]["rect"] = Rect2(16 + (i % 2) * 258, 716 + (i / 2) * 62, 250, 56)
	return out


func _hint(s: String) -> void:
	hint_text = s
	hint_ttl = 1.8


func _add_fx(k: String, d: float, data: Dictionary) -> void:
	var f := data.duplicate()
	f["k"] = k
	f["t"] = 0.0
	f["d"] = d
	fx.append(f)


func _fx_of(k: String) -> Array:
	return fx.filter(func(f): return f["k"] == k)


func _clock_text(t: int) -> String:
	var m := 6 * 60 + t * 8
	return "%02d:%02d" % [m / 60, m % 60]


func _deadline(id: String) -> String:
	var t1 := int(rules.act[id]["t1"])
	return "%d틱(%s)" % [t1, _clock_text(t1)]


# ---------------------------------------------------------------- 그리기

func _txt(s: String, p: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, p, s, align, width, size, col)


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), C_PAPER)
	for i in 24:      # 수첩 종이의 줄
		draw_line(Vector2(0, 40 + i * 40), Vector2(W, 40 + i * 40), Color(C_PAPER2, 0.55), 1)
	match state:
		State.TITLE:
			_draw_title()
		State.DAY:
			_draw_day()
		State.NOTEBOOK:
			_draw_notebook()
		State.RESULT:
			_draw_result()


func _draw_title() -> void:
	_txt("같은 하루", Vector2(0, 250), 56, C_INK, HORIZONTAL_ALIGNMENT_CENTER, W)
	_txt("마을은 3분마다 아침으로 돌아간다.", Vector2(0, 318), 22, C_INK, HORIZONTAL_ALIGNMENT_CENTER, W)
	_txt("나만 기억한다.", Vector2(0, 352), 22, C_RED, HORIZONTAL_ALIGNMENT_CENTER, W)
	# 바늘이 거꾸로 도는 시계
	var c := Vector2(270, 480)
	draw_arc(c, 62, 0, TAU, 48, C_INK, 4)
	for k in 12:
		var a := TAU * k / 12.0
		draw_line(c + Vector2(cos(a), sin(a)) * 52, c + Vector2(cos(a), sin(a)) * 60, C_INK, 2)
	var ang := -clk * 1.2 - PI / 2
	draw_line(c, c + Vector2(cos(ang), sin(ang)) * 46, C_RED, 4)
	draw_line(c, c + Vector2(cos(ang / 12.0), sin(ang / 12.0)) * 30, C_INK, 5)
	draw_circle(c, 5, C_INK)
	draw_arc(c, 76, PI * 0.15, PI * 0.85, 24, C_DIM, 2)
	draw_colored_polygon(PackedVector2Array([c + Vector2(72, 20), c + Vector2(60, 44), c + Vector2(84, 42)]), C_DIM)
	_txt("화면을 눌러 첫 아침", Vector2(0, 660), 26, Color(C_INK, 0.55 + 0.45 * sin(clk * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, W)
	_txt("서서 지켜보면 수첩에 적힌다 · 적힌 것이 새 선택지를 연다", Vector2(0, 720), 15, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, W)


func _band_x(t: float) -> float:
	return lerpf(BAND_X0, BAND_X1, t / float(rules.T))


func _initial(npc: String) -> String:
	return str(rules.npc_name.get(npc, "?")).substr(0, 1)


func _draw_band() -> void:
	draw_line(Vector2(BAND_X0, BAND_Y), Vector2(BAND_X1, BAND_Y), C_INK, 3)
	for k in 13:
		var x := _band_x(rules.T * k / 12.0)
		draw_line(Vector2(x, BAND_Y - (7 if k % 3 == 0 else 4)), Vector2(x, BAND_Y + (7 if k % 3 == 0 else 4)), C_INK, 2)
	_txt("06", Vector2(8, BAND_Y + 6), 15, C_DIM)
	_txt("18", Vector2(508, BAND_Y + 6), 15, C_DIM)
	_txt("정오", Vector2(_band_x(rules.T / 2.0) - 20, BAND_Y + 24), 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 40)
	# 아는 장면의 표식
	var last_mark_x := -100.0
	for n in rules.notes:
		var o: Dictionary = rules.scene_of(n)
		if o.is_empty():
			continue
		var x := _band_x(float(o["t0"]) + 0.5)
		var isnew: bool = rules.new_notes.has(n)
		draw_line(Vector2(x, BAND_Y - 12), Vector2(x, BAND_Y - 4), C_RED if isnew else C_BLUE, 3)
		if x - last_mark_x >= 14.0:      # 글자가 겹치면 눈금만
			_txt(_initial(o["who"]), Vector2(x - 8, BAND_Y - 13), 10, C_RED if isnew else C_BLUE, HORIZONTAL_ALIGNMENT_CENTER, 16)
			last_mark_x = x
	# 바늘
	var frac := clampf(acc / _tick_len(), 0.0, 1.0) if state == State.DAY else 0.0
	var nx := _band_x(rules.tick + frac)
	var bump := 0.0
	for f in _fx_of("tick"):
		bump = 3.0 * (1.0 - f["t"] / f["d"])
	draw_colored_polygon(PackedVector2Array([Vector2(nx - 7, BAND_Y - 16 - bump), Vector2(nx + 7, BAND_Y - 16 - bump), Vector2(nx, BAND_Y - 2)]), C_RED)
	draw_line(Vector2(nx, BAND_Y - 2), Vector2(nx, BAND_Y + 10), C_RED, 2)
	if fast:
		_txt("▶▶", Vector2(nx + 8, BAND_Y - 6), 13, C_RED)
		draw_colored_polygon(PackedVector2Array([Vector2(nx + 10, BAND_Y - 16), Vector2(nx + 10, BAND_Y - 4), Vector2(nx + 19, BAND_Y - 10)]), C_RED)
		draw_colored_polygon(PackedVector2Array([Vector2(nx + 20, BAND_Y - 16), Vector2(nx + 20, BAND_Y - 4), Vector2(nx + 29, BAND_Y - 10)]), C_RED)


func _draw_stamp(c: Vector2, on: bool, scale := 1.0) -> void:
	var r := Rect2(c - Vector2(62, 14) * scale, Vector2(124, 28) * scale)
	if on:
		draw_rect(r, Color(C_RED, 0.12))
		draw_rect(r, C_RED, false, 3)
		_txt("식은 화덕", Vector2(r.position.x + 8 * scale, r.position.y + 20 * scale), int(15 * scale), C_RED)
		var k := r.position + Vector2(96, 15) * scale
		draw_line(k, k + Vector2(6, 6) * scale, C_RED, 3)
		draw_line(k + Vector2(6, 6) * scale, k + Vector2(18, -8) * scale, C_RED, 3)
	else:
		draw_rect(r, C_DIM, false, 1.5)
		_txt("식은 화덕", Vector2(r.position.x + 8 * scale, r.position.y + 20 * scale), int(15 * scale), C_DIM)
		_txt("?", Vector2(r.position.x + 98 * scale, r.position.y + 21 * scale), int(16 * scale), C_DIM)


func _draw_day() -> void:
	_draw_band()
	_txt("%d번째 하루" % rules.loop, Vector2(16, 82), 18, C_INK)
	_txt("%s (%d틱)" % [_clock_text(rules.tick), rules.tick], Vector2(150, 82), 20, C_INK)
	_draw_stamp(Vector2(456, 76), rules.solved or _goal_now())
	_draw_map()
	_draw_panel()
	_draw_buttons()
	for f in _fx_of("goal"):
		var a := clampf(minf(f["t"] * 4.0, (f["d"] - f["t"]) * 2.0), 0.0, 1.0)
		draw_rect(Rect2(60, 96, 420, 44), Color(C_RED, 0.92 * a))
		_txt("%s — 점심이 차려졌다" % str(rules.goal_name).get_slice(" — ", 0), Vector2(60, 125), 20, Color(C_PAPER, a), HORIZONTAL_ALIGNMENT_CENTER, 420)


func _shape(pl: String, c: Vector2, col: Color, fill: Color) -> void:
	match pl:
		"inn":      # 지붕 달린 사각형
			draw_rect(Rect2(c + Vector2(-24, -10), Vector2(48, 34)), fill)
			draw_rect(Rect2(c + Vector2(-24, -10), Vector2(48, 34)), col, false, 3)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-32, -10), c + Vector2(32, -10), c + Vector2(0, -34)]), col)
		"bakery":   # 굴뚝 있는 사각형
			draw_rect(Rect2(c + Vector2(-26, -14), Vector2(52, 38)), fill)
			draw_rect(Rect2(c + Vector2(-26, -14), Vector2(52, 38)), col, false, 3)
			draw_rect(Rect2(c + Vector2(8, -34), Vector2(12, 20)), col)
		"plaza":    # 원
			draw_circle(c, 30, fill)
			draw_arc(c, 30, 0, TAU, 40, col, 3)
			draw_arc(c, 12, 0, TAU, 20, col, 2)
		"post":     # 봉투 무늬 사각형
			draw_rect(Rect2(c + Vector2(-28, -18), Vector2(56, 38)), fill)
			draw_rect(Rect2(c + Vector2(-28, -18), Vector2(56, 38)), col, false, 3)
			draw_line(c + Vector2(-28, -18), c + Vector2(0, 4), col, 2)
			draw_line(c + Vector2(28, -18), c + Vector2(0, 4), col, 2)
		"smithy":   # 모루
			draw_colored_polygon(PackedVector2Array([c + Vector2(-32, -18), c + Vector2(32, -18), c + Vector2(16, 0), c + Vector2(22, 20), c + Vector2(-22, 20), c + Vector2(-16, 0)]), fill)
			draw_polyline(PackedVector2Array([c + Vector2(-32, -18), c + Vector2(32, -18), c + Vector2(16, 0), c + Vector2(22, 20), c + Vector2(-22, 20), c + Vector2(-16, 0), c + Vector2(-32, -18)]), col, 3)
		"tower":    # 높은 삼각형
			draw_colored_polygon(PackedVector2Array([c + Vector2(-22, 24), c + Vector2(22, 24), c + Vector2(0, -38)]), fill)
			draw_polyline(PackedVector2Array([c + Vector2(-22, 24), c + Vector2(22, 24), c + Vector2(0, -38), c + Vector2(-22, 24)]), col, 3)
			draw_circle(c + Vector2(0, 6), 5, col)
		"dock":     # 물결선 위의 반원
			draw_arc(c + Vector2(0, 6), 26, PI, TAU, 24, col, 3)
			draw_line(c + Vector2(-26, 6), c + Vector2(26, 6), col, 3)
			for k in 4:
				draw_arc(c + Vector2(-24 + k * 16, 20), 8, 0, PI, 8, C_BLUE, 2)
		_:
			draw_circle(c, 28, fill)
			draw_arc(c, 28, 0, TAU, 40, col, 3)


func _me_pos() -> Vector2:
	if rules.walk_left <= 0 or rules.walk_from == "":
		return _place_pos(rules.place) + Vector2(44, 8)
	var pts: Array = rules.path(rules.walk_from, rules.walk_to)
	var total := float(rules.walk_total)
	var frac := clampf(acc / _tick_len(), 0.0, 1.0)
	var elapsed: float = total - float(rules.walk_left) + frac
	var u: float = elapsed
	if elapsed < 1.0 and walk_u0 < 1.0:
		u = clampf((elapsed - walk_u0) / (1.0 - walk_u0), 0.0, 1.0)       # 틱 중간에 출발했으면 남은 시간에 맞춰 걷는다
	for i in pts.size() - 1:
		var seg := float(rules.dist[pts[i]][pts[i + 1]])
		if u <= seg or i == pts.size() - 2:
			var a := _place_pos(pts[i]) + (Vector2(44, 8) if i == 0 else Vector2.ZERO)
			var b := _place_pos(pts[i + 1]) + (Vector2(44, 8) if i == pts.size() - 2 else Vector2.ZERO)
			return a.lerp(b, clampf(u / seg, 0.0, 1.0))
		u -= seg
	return _place_pos(rules.walk_to)


func _draw_flag(p: Vector2, label: String, col: Color) -> void:
	draw_line(p, p + Vector2(0, -30), col, 3)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -30), p + Vector2(22, -23), p + Vector2(0, -16)]), col)
	if label != "":
		_txt(label, Vector2(p.x + 3, p.y - 18), 12, C_PAPER)


func _draw_map() -> void:
	# 길과 걸리는 틱 수
	for e in rules.edges:
		var a := _place_pos(e[0])
		var b := _place_pos(e[1])
		draw_line(a, b, Color(C_INK, 0.55), 6)
		var m := (a + b) / 2.0
		draw_circle(m, 11, C_PAPER)
		_txt("%d" % int(e[2]), Vector2(m.x - 10, m.y + 5), 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 20)
	# 걷는 길의 점선, 목적지와 예약 깃발
	var from: String = rules.place
	if rules.walk_left > 0:
		_dotted(rules.walk_from, rules.walk_to)
		from = rules.walk_to
	for q in rules.queue:
		if rules.places.has(q):
			_dotted(from, q)
			from = q
	# 장소
	for pl in rules.places:
		var c := _place_pos(pl)
		var here: bool = pl == rules.place
		for f in _fx_of("shake"):
			if f["place"] == pl:
				c.x += sin(f["t"] / f["d"] * TAU * 2.0) * 5.0
		_shape(pl, c, C_INK, Color("f4ecd8") if here else C_PAPER2)
		_txt(str(rules.place_name[pl]), Vector2(c.x - 40, c.y + 46), 15, C_INK, HORIZONTAL_ALIGNMENT_CENTER, 80)
	# 먼 신호(지금 내 자리에서 보이는 것)
	for o in rules.scenes_here():
		if SMOKE_AT.has(o["note"]):
			var c := _place_pos(SMOKE_AT[o["note"]]) + Vector2(14, -38)
			for k in 4:
				var ph := fmod(clk * 0.5 + k * 0.25, 1.0)
				draw_circle(c + Vector2(sin(ph * 5.0 + k) * 6.0, -ph * 44.0), 7.0 + ph * 9.0, Color(0.1, 0.1, 0.1, 0.75 * (1.0 - ph)))
	if rules.walk_left > 0:
		_draw_flag(_place_pos(rules.walk_to) + Vector2(-34, 6), "", C_RED)
	var qn := 0
	for q in rules.queue:
		qn += 1
		if rules.places.has(q):
			_draw_flag(_place_pos(q) + Vector2(-34 + (qn - 1) * 3, 6), "%d" % qn, C_BLUE)
	# 주민: 내 장소에 있으면 진한 원, 아니면 본 적 있는 (주민, 지금 틱)의 자리에 옅은 원
	for i in rules.npcs.size():
		var n: String = rules.npcs[i]
		var loc: String = rules.npc_loc(n, rules.tick)
		var solid: bool = loc != "" and loc == rules.place
		var at: String = loc if solid else rules.expected(n)
		if at == "":
			continue
		var c := _place_pos(at) + Vector2(-30 + i * 20, -52)
		if solid:
			draw_circle(c, 13, C_INK)
			draw_circle(c, 11, Color("f7f1e1"))
			_txt(_initial(n), Vector2(c.x - 10, c.y + 6), 15, C_INK, HORIZONTAL_ALIGNMENT_CENTER, 20)
			for f in _fx_of("react"):
				if f["npc"] == n:
					_txt("!", Vector2(c.x - 6, c.y - 16 - 6.0 * sin(PI * f["t"] / f["d"])), 22, C_RED, HORIZONTAL_ALIGNMENT_CENTER, 12)
		else:
			draw_arc(c, 12, 0, TAU, 20, Color(C_INK, 0.4), 2)
			_txt(_initial(n), Vector2(c.x - 10, c.y + 5), 13, Color(C_INK, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 20)
	# 나
	var me := _me_pos()
	draw_circle(me, 13, C_INK)
	draw_circle(me, 9, C_RED)
	if rules.acting != "":
		draw_arc(me, 18, -PI / 2, -PI / 2 + TAU * clampf(acc / _tick_len(), 0.0, 1.0), 20, C_RED, 3)


func _dotted(a: String, b: String) -> void:
	if a == "" or b == "" or a == b:
		return
	var pts: Array = rules.path(a, b)
	for i in pts.size() - 1:
		var p := _place_pos(pts[i])
		var q := _place_pos(pts[i + 1])
		var n := int(p.distance_to(q) / 14.0)
		for k in n:
			draw_circle(p.lerp(q, (k + 0.5) / n), 3, C_RED)


func _pencil(p: Vector2, col: Color) -> void:
	draw_line(p + Vector2(0, 12), p + Vector2(10, 0), col, 4)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 15), p + Vector2(2, 13), p + Vector2(-1, 10)]), col)


func _checkmark(p: Vector2, col: Color) -> void:
	draw_line(p + Vector2(0, 7), p + Vector2(4, 12), col, 3)
	draw_line(p + Vector2(4, 12), p + Vector2(12, 0), col, 3)


func _draw_panel() -> void:
	var rise := 0.0
	for f in _fx_of("arrive"):
		rise = 14.0 * (1.0 - f["t"] / f["d"])
	var shake := 0.0
	for f in _fx_of("missed"):
		shake = sin(f["t"] / f["d"] * TAU * 2.0) * 5.0
	var r := Rect2(PANEL.position + Vector2(shake, rise), PANEL.size)
	draw_rect(r, Color("f4ecd8"))
	draw_rect(r, C_INK, false, 2)
	var x := r.position.x + 12
	var y := r.position.y
	# 첫 줄
	if rules.walk_left > 0:
		_txt("%s으로 가는 중 — %d틱 남음" % [rules.place_name[rules.walk_to], rules.walk_left], Vector2(x, y + 28), 19, C_INK)
	else:
		var who: Array = []
		for n in rules.npcs:
			if rules.npc_loc(n, rules.tick) == rules.place:
				who.append(str(rules.npc_name[n]))
		_txt("%s — %s" % [rules.place_name.get(rules.place, rules.place), ", ".join(PackedStringArray(who)) if not who.is_empty() else "아무도 없다"], Vector2(x, y + 28), 19, C_INK)
	if not _fx_of("newnote").is_empty():
		draw_rect(Rect2(r.position.x + 396, y - 26, 122, 26), C_RED)
		_txt("새로 알았다", Vector2(r.position.x + 396, y - 7), 15, C_PAPER, HORIZONTAL_ALIGNMENT_CENTER, 122)
	# 장면 글
	var ly := y + 58
	var lines := 0
	for o in rules.scenes_here():
		if lines >= 2:
			break
		if rules.new_notes.has(o["note"]):
			_pencil(Vector2(x, ly - 14), C_RED)
		else:
			_checkmark(Vector2(x, ly - 13), C_BLUE)
		draw_multiline_string(font, Vector2(x + 22, ly), str(o["text"]), HORIZONTAL_ALIGNMENT_LEFT, 478, 16, 2, C_INK)
		ly += 22 * (2 if font.get_string_size(str(o["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 478 else 1) + 4
		lines += 1
	if rules.acting != "":
		_txt("%s…" % rules.act[rules.acting]["label"], Vector2(x, ly), 16, C_RED)
		ly += 24
	elif feed_ttl > 0.0 and lines < 2:
		draw_multiline_string(font, Vector2(x, ly), feed_text, HORIZONTAL_ALIGNMENT_LEFT, 500, 16, 2, C_GREEN)
		ly += 26
	elif lines == 0 and rules.walk_left <= 0:
		_txt("지도의 장소를 눌러 가 보세요" if rules.loop == 1 and rules.tick == 0 else "지금은 아무 일도 없다", Vector2(x, ly), 16, C_DIM)
	if missed_shown and rules.last_missed != "" and ly < y + 136:
		_txt("놓쳤다: %s" % rules.act[rules.last_missed]["label"], Vector2(x, y + 136), 15, C_RED)
	if hint_ttl > 0.0:
		_txt(hint_text, Vector2(r.position.x + 250, y + 136), 15, C_RED, HORIZONTAL_ALIGNMENT_RIGHT, 262)
	# 선택지
	var busy: bool = rules.busy()
	for c in _choice_layout():
		var b: Rect2 = c["rect"]
		b.position += Vector2(shake, rise)
		var a: Dictionary = rules.act[c["id"]]
		var know: bool = not (a["know"] as Array).is_empty()
		match c["kind"]:
			"choice":
				draw_rect(b, Color("fff8e6"))
				draw_rect(b, C_INK, false, 3)
				_txt(str(a["label"]), Vector2(b.position.x + 12, b.position.y + 35), 18, C_INK)
				var tag := "예약" if busy else ("수첩 덕분" if know else "")
				if tag != "":
					var tw := 70.0 if tag == "수첩 덕분" else 44.0
					draw_rect(Rect2(b.end.x - tw - 6, b.position.y + 6, tw, 20), C_BLUE if busy else C_GOLD)
					_txt(tag, Vector2(b.end.x - tw - 6, b.position.y + 21), 12, C_PAPER, HORIZONTAL_ALIGNMENT_CENTER, tw)
			"queued":
				draw_rect(b, Color(C_BLUE, 0.16))
				draw_rect(b, C_BLUE, false, 3)
				_txt(str(a["label"]), Vector2(b.position.x + 40, b.position.y + 35), 18, C_INK)
				draw_circle(b.position + Vector2(22, 28), 13, C_BLUE)
				_txt("%d" % c["n"], Vector2(b.position.x + 12, b.position.y + 34), 16, C_PAPER, HORIZONTAL_ALIGNMENT_CENTER, 20)
			"late":
				draw_rect(b, Color(C_DIM, 0.25))
				draw_rect(b, C_DIM, false, 2)
				_txt(str(a["label"]), Vector2(b.position.x + 12, b.position.y + 24), 16, C_DIM)
				_txt("늦었다 — %s까지" % _deadline(c["id"]), Vector2(b.position.x + 12, b.position.y + 46), 14, C_RED)
	# 소지품
	var names: Array = []
	for it in rules.items:
		names.append(str(rules.item_names.get(it, it)))
	draw_rect(Rect2(r.end.x - 132, y + 8, 122, 28), Color(C_GOLD, 0.25) if not names.is_empty() else C_PAPER2)
	draw_rect(Rect2(r.end.x - 132, y + 8, 122, 28), C_INK, false, 1.5)
	_txt("손: %s" % (", ".join(PackedStringArray(names)) if not names.is_empty() else "빈손"), Vector2(r.end.x - 132, y + 28), 16, C_INK, HORIZONTAL_ALIGNMENT_CENTER, 122)


func _draw_buttons() -> void:
	var labels := ["수첩", "흘려보내기", "예약 지우기", "잠들기"]
	var subs := ["시간이 멈춘다", "누르는 동안 4배속", "", "길게 누르기"]
	for i in 4:
		var r := _button_rect(i)
		var on := true
		var active := false
		if i == 0 and not _fx_of("newnote").is_empty():
			r.position.y -= 6.0 * absf(sin(clk * 9.0))
			active = true
		if i == 1:
			active = fast
		if i == 2:
			on = not rules.queue.is_empty()
		draw_rect(r, C_INK if active else (Color("f4ecd8") if on else C_PAPER2))
		draw_rect(r, C_INK if on else C_DIM, false, 3 if on else 1)
		var col := C_PAPER if active else (C_INK if on else C_DIM)
		_txt(labels[i], Vector2(r.position.x, r.position.y + 42), 19, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_txt(subs[i], Vector2(r.position.x, r.position.y + 68), 12, col if active else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if i == 3 and sleep_holding:
			draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(sleep_t / SLEEP_HOLD, 0.0, 1.0), r.size.y)), Color(C_RED, 0.35))
			draw_rect(r, C_RED, false, 4)


func _nb_max_scroll() -> float:
	return maxf(0.0, rules.T * NB_TICK_W - (W - NB_X - 10.0))


func _nb_rect(row: int, e: Dictionary) -> Rect2:
	var x: float = NB_X + int(e["t0"]) * NB_TICK_W - nb_scroll
	var w: float = NB_TICK_W * (int(e["t1"]) - int(e["t0"]) + 1) - 2.0
	return Rect2(x, NB_ROW_Y + row * NB_ROW_H + 8, w, NB_ROW_H - 16)


func _nb_tap(p: Vector2) -> void:
	var rows: Array = rules.timetable()
	for i in rows.size():
		for e in rows[i]["entries"]:
			if _nb_rect(i, e).grow(8).has_point(p):
				nb_sel = e["note"]
				return


func _draw_notebook() -> void:
	_txt("수첩 — 시간표", Vector2(16, 58), 28, C_INK)
	draw_rect(NB_CLOSE, Color("f4ecd8"))
	draw_rect(NB_CLOSE, C_INK, false, 3)
	_txt("닫기", Vector2(NB_CLOSE.position.x, NB_CLOSE.position.y + 37), 22, C_INK, HORIZONTAL_ALIGNMENT_CENTER, NB_CLOSE.size.x)
	_txt("%d번째 하루 · 지금 %s — 시간이 멈춰 있다" % [rules.loop, _clock_text(rules.tick)], Vector2(16, 96), 15, C_DIM)
	var rows: Array = rules.timetable()
	# 시각 눈금
	for t in range(0, rules.T + 1, 5):
		var x: float = NB_X + t * NB_TICK_W - nb_scroll
		if x < NB_X - 4 or x > W - 4:
			continue
		draw_line(Vector2(x, NB_ROW_Y - 8), Vector2(x, NB_ROW_Y + rows.size() * NB_ROW_H), Color(C_DIM, 0.5), 1)
		_txt(_clock_text(t), Vector2(x - 20, NB_ROW_Y - 14), 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 40)
	var any := false
	for i in rows.size():
		var y := NB_ROW_Y + i * NB_ROW_H
		draw_line(Vector2(0, y + NB_ROW_H), Vector2(W, y + NB_ROW_H), Color(C_INK, 0.35), 1)
		for e in rows[i]["entries"]:
			any = true
			var r := _nb_rect(i, e)
			if r.end.x < NB_X or r.position.x > W:
				continue
			var isnew: bool = rules.new_notes.has(e["note"])
			var sel: bool = nb_sel == e["note"]
			draw_rect(r, Color(C_RED, 0.25) if isnew else Color(C_BLUE, 0.22))
			draw_rect(r, C_INK if sel else (C_RED if isnew else C_BLUE), false, 4 if sel else 2)
			if isnew:
				_pencil(r.position + Vector2(8, 6), C_RED)
			else:
				_checkmark(r.position + Vector2(7, 8), C_BLUE)
			_txt("%d" % e["t0"], Vector2(r.position.x + 2, r.end.y - 6), 12, C_INK)
		draw_rect(Rect2(0, y + 1, NB_X - 6, NB_ROW_H - 2), C_PAPER)
		var c := Vector2(30, y + NB_ROW_H / 2)
		draw_circle(c, 17, C_INK)
		draw_circle(c, 15, Color("f7f1e1"))
		_txt(_initial(rows[i]["who"]), Vector2(c.x - 12, c.y + 7), 18, C_INK, HORIZONTAL_ALIGNMENT_CENTER, 24)
		_txt(str(rules.npc_name[rows[i]["who"]]), Vector2(4, y + NB_ROW_H - 6), 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 54)
	# 지금 시각의 세로 선
	var nx: float = NB_X + (rules.tick + 0.5) * NB_TICK_W - nb_scroll
	if nx >= NB_X and nx <= W:
		draw_line(Vector2(nx, NB_ROW_Y - 8), Vector2(nx, NB_ROW_Y + rows.size() * NB_ROW_H), C_RED, 2)
	_txt("← 옆으로 밀어 시각을 넘긴다 →", Vector2(0, NB_ROW_Y + rows.size() * NB_ROW_H + 26), 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, W)
	# 고른 칸의 글
	var box := Rect2(16, 540, 508, 240)
	draw_rect(box, Color("f4ecd8"))
	draw_rect(box, C_INK, false, 2)
	if not any:
		draw_multiline_string(font, Vector2(34, 600), "아직 본 것이 없다.\n어딘가에 서서 지켜보자.", HORIZONTAL_ALIGNMENT_LEFT, 470, 22, 3, C_DIM)
	else:
		var o: Dictionary = rules.scene_of(nb_sel)
		if o.is_empty():
			_txt("칸을 누르면 그 장면이 보인다", Vector2(34, 600), 18, C_DIM)
		else:
			var locs: Array = []
			for l in o["loc"]:
				locs.append(str(rules.place_name.get(l, l)))
			_txt("%s  %s" % [_clock_text(int(o["t0"])), rules.npc_name[o["who"]]], Vector2(34, 584), 22, C_INK)
			_txt("(%s) · %d~%d틱" % [", ".join(PackedStringArray(locs)), o["t0"], o["t1"]], Vector2(34, 612), 15, C_DIM)
			draw_multiline_string(font, Vector2(34, 656), str(o["text"]), HORIZONTAL_ALIGNMENT_LEFT, 470, 22, 4, C_INK)
			if rules.new_notes.has(nb_sel):
				_pencil(Vector2(470, 560), C_RED)
				_txt("오늘 적었다", Vector2(380, 760), 14, C_RED, HORIZONTAL_ALIGNMENT_RIGHT, 130)
	var cb := Rect2(BTN_GAP, BTN_Y, W - BTN_GAP * 2, BTN_H)
	draw_rect(cb, Color("f4ecd8"))
	draw_rect(cb, C_INK, false, 3)
	_txt("닫고 하루로 돌아가기", Vector2(cb.position.x, cb.position.y + 54), 22, C_INK, HORIZONTAL_ALIGNMENT_CENTER, cb.size.x)


func _draw_result() -> void:
	var dusk := 0.0
	for f in _fx_of("dusk"):
		dusk = 1.0 - f["t"] / f["d"]
	_txt("%d번째 하루 끝" % rules.loop, Vector2(0, 110), 34, C_INK, HORIZONTAL_ALIGNMENT_CENTER, W)
	var sc := 1.6
	for f in _fx_of("stamp"):
		sc = 1.6 + 1.2 * (1.0 - f["t"] / f["d"])
	_draw_stamp(Vector2(270, 190), rules.result_solved, sc)
	_txt("점심이 차려졌다" if rules.result_solved else "여관의 점심은 없었다", Vector2(0, 252), 20, C_RED if rules.result_solved else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, W)
	var y := 320.0
	_txt("오늘 새로 안 것 %d" % rules.result_new.size(), Vector2(40, y), 22, C_INK)
	y += 34
	if rules.result_new.is_empty():
		draw_multiline_string(font, Vector2(40, y), "새로 안 것이 없다 — 다른 곳, 다른 시각에 서 보자", HORIZONTAL_ALIGNMENT_LEFT, 460, 17, 2, C_DIM)
		y += 30
	var shown := 0
	for n in rules.result_new:
		if shown >= 7:
			_txt("… 그 밖에 %d개" % (rules.result_new.size() - shown), Vector2(64, y), 15, C_DIM)
			y += 26
			break
		var o: Dictionary = rules.scene_of(n)
		_pencil(Vector2(40, y - 14), C_RED)
		var s := str(o.get("text", n))
		if s.length() > 30:
			s = s.substr(0, 29) + "…"
		_txt(s, Vector2(64, y), 16, C_INK)
		y += 30
		shown += 1
	if not rules.result_late.is_empty():
		y += 18
		_txt("늦은 매듭", Vector2(40, y), 22, C_RED)
		y += 32
		for id in rules.result_late:
			_txt("%s — %s까지" % [rules.act[id]["label"], _deadline(id)], Vector2(40, y), 17, C_INK)
			y += 28
	_txt("화면을 눌러 다음 아침", Vector2(0, 880), 26, Color(C_INK, 0.55 + 0.45 * sin(clk * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, W)
	_txt("표지와 소지품은 사라지고 수첩은 남는다", Vector2(0, 914), 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, W)
	if dusk > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(0.1, 0.07, 0.05, dusk))


# ---------------------------------------------------------------- 테스트 인터페이스 (FIRST_BUILD.md)

func debug_reset() -> void:
	rules = Rules.new()
	rules.load_data(Content.CHAPTER)
	state = State.TITLE
	fast = false
	acc = 0.0
	fx.clear()


func debug_load(json: String) -> void:
	rules = Rules.new()
	rules.load_data(json)
	_start_day()


func debug_set_notes(ids: Array) -> void:
	rules.notes = ids.duplicate()


func debug_tick(n: int) -> void:
	for i in n:
		if state != State.DAY:
			return
		_tick()


func debug_step(seconds: float) -> void:
	_advance(seconds)


func debug_go(pl: String) -> bool:
	return _go(pl)


func debug_do(action: String) -> bool:
	return _choose(action)


func debug_dist(a: String, b: String) -> int:
	return int(rules.dist[a][b])


func debug_npc_place(npc: String) -> String:
	return rules.npc_loc(npc, rules.tick)


func debug_expected(npc: String) -> String:
	return rules.expected(npc)


func debug_timetable() -> Array:
	return rules.timetable()


func debug_place_pos(pl: String) -> Vector2:
	return _place_pos(pl)


func debug_tap(p: Vector2) -> void:
	_press(p)
	_release(p)


func debug_press(id: String) -> void:
	_button(id)
