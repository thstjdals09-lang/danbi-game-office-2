extends SceneTree
## 빌드실이 덧붙인 검사: 실제 입력 경로(debug_tap/debug_press)와 실시간(debug_step)으로 무작위 입력을 넣어
## 스크립트 오류 없이 상태가 항상 유효한지 본다. 그리기도 함께 돌도록 여러 프레임에 나눠 넣는다.
## tools/smoke.py 가 smoke.gd 다음에 실행한다.

const INPUTS_PER_FRAME := 10
const FRAMES := 240
const PLACES: Array[String] = ["inn", "bakery", "plaza", "post", "smithy", "tower", "dock"]
const ACTIONS: Array[String] = ["wood_take", "wood_give", "slip"]

var game: Node
var frame := 0
var rng := RandomNumberGenerator.new()
var failures: Array[String] = []
var days := 0
var solved_days := 0
var acts_done := 0
var notebooks := 0
var queued := 0
var missed := 0
var max_notes := 0


func _initialize() -> void:
	rng.seed = 20261001
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func check(ok: bool, label: String) -> void:
	if not ok and failures.size() < 10:
		failures.append("%s (frame %d, loop %d, tick %d)" % [label, frame, game.loop, game.tick])


func random_input() -> void:
	match game.state:
		game.State.TITLE:
			game.debug_tap(Vector2(270, 480))
			check(game.state == game.State.DAY and game.loop == 1 and game.tick == 0, "타이틀에서 탭하면 첫 아침")
			return
		game.State.RESULT:
			days += 1
			if game.result_solved:
				solved_days += 1
			check(not game.result_solved or game.solved, "풀린 하루면 도장")
			var l: int = game.loop
			var n: int = game.notes.size()
			game.debug_step(3.0)
			check(game.state == game.State.RESULT, "결과 화면에서는 시간이 가지 않는다")
			game.debug_tap(Vector2(270, 480))
			check(game.state == game.State.DAY and game.loop == l + 1 and game.tick == 0 and game.place == "inn", "다음 아침")
			check(game.items.is_empty() and game.flags.is_empty() and game.queue.is_empty() and game.notes.size() == n, "표지·소지품은 사라지고 수첩은 남는다")
			return
		game.State.NOTEBOOK:
			var t: int = game.tick
			game.debug_step(2.5)
			check(game.tick == t, "수첩이 열려 있으면 시간이 멈춘다")
			game.debug_tap(Vector2(200 + rng.randi() % 200, 200 + rng.randi() % 200))     # 칸을 눌러 본다
			check(game.state == game.State.NOTEBOOK, "칸을 눌러도 수첩 화면")
			game.debug_press("close")
			check(game.state == game.State.DAY, "닫으면 하루로")
			return
	var roll := rng.randf()
	var q0: int = game.queue.size()
	var done0: int = game.done.size()
	var missed0: String = game.last_missed
	if roll < 0.30:
		var pl := PLACES[rng.randi() % PLACES.size()]
		game.debug_tap(game.debug_place_pos(pl) + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)))
	elif roll < 0.50:
		var c: Array = game.choices
		if not c.is_empty():
			game.debug_press("choice:" + str(c[rng.randi() % c.size()]))
		else:
			game.debug_press("choice:" + ACTIONS[rng.randi() % ACTIONS.size()])       # 없는 선택지: 아무 일도 없어야 한다
			check(game.queue.size() == q0 and game.acting == "" or not game.choices.is_empty() or game.acting != "", "없는 선택지는 무시")
	elif roll < 0.53:
		game.debug_press("notebook")
		notebooks += 1
	elif roll < 0.56:
		game.debug_press("clear")
		check(game.queue.is_empty(), "예약 지우기")
	elif roll < 0.565:
		game.debug_press("sleep")
	elif roll < 0.62:
		game.debug_press("fast_down")
		game.debug_step(rng.randf_range(0.2, 3.0))
		game.debug_press("fast_up")
	else:
		game.debug_step(rng.randf_range(0.3, 5.0))
	if game.queue.size() > q0:
		queued += 1
	acts_done += maxi(0, game.done.size() - done0)
	if game.last_missed != missed0 and game.last_missed != "":
		missed += 1
	max_notes = maxi(max_notes, game.notes.size())
	# 불변식
	check(game.tick >= 0 and game.tick <= 89, "틱 0~89")
	check(game.items.size() <= 2, "소지품 2개까지")
	check(game.queue.size() <= 3, "예약 3개까지")
	if game.state == game.State.DAY:
		check((game.place == "") == (game.walk_left > 0), "걷는 중 ⇔ 장소 없음")
		check(game.place == "" or PLACES.has(game.place), "서 있는 장소는 지도 위")
		check(game.walk_left == 0 or (PLACES.has(game.walk_to) and PLACES.has(game.walk_from)), "걷는 중이면 출발·목적 장소")
		check(not (game.walk_left > 0 and game.acting != ""), "걸으면서 행동하지 않는다")
		for c in game.choices:
			check(ACTIONS.has(c), "선택지는 행동 id")
		check(game.late_choices.is_empty() or (game.place != "" and game.acting == ""), "늦은 선택지는 한가하게 서 있을 때만")
	var f: Array = game.flags
	var sorted: Array = f.duplicate()
	sorted.sort()
	check(f == sorted, "표지는 글자순")
	check(not f.has("bread") or not f.has("burnt"), "빵은 구워지거나 타거나 둘 중 하나")
	check(not f.has("lunch") or (f.has("wood") and f.has("order") and f.has("inn_bread")), "점심은 장작·쪽지·배달이 다 있어야")
	check(not f.has("order") or game.notes.has("N_slipfall"), "쪽지는 떨어지는 걸 본 사람만 줍는다")
	var uniq := {}
	for n in game.notes:
		uniq[n] = true
	check(uniq.size() == game.notes.size(), "수첩에 같은 사실이 두 번 적히지 않는다")
	for n in game.new_notes:
		check(game.notes.has(n), "새로 안 것은 수첩에 있다")
	for d in game.done:
		check(ACTIONS.has(d), "한 일은 행동 id")


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame < 3 + FRAMES:
		for i in INPUTS_PER_FRAME:
			random_input()
		return false
	check(days >= 5, "하루가 5번 넘게 끝남(%d)" % days)
	check(acts_done >= 5, "끼어들기가 5번 넘게 끝남(%d)" % acts_done)
	check(queued >= 20, "예약이 20번 넘게 됨(%d)" % queued)
	check(max_notes >= 5, "수첩에 5개 넘게 적힘(%d)" % max_notes)
	print("extra: 하루 %d(풀린 날 %d), 끼어들기 %d, 예약 %d, 놓친 예약 %d, 수첩 열기 %d, 수첩 %d개" % [days, solved_days, acts_done, queued, missed, notebooks, max_notes])
	for f in failures:
		printerr("SMOKE FAIL ", f)
	print("SMOKE %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
	return false
