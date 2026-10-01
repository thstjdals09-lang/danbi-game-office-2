extends SceneTree
## 빌드실이 덧붙인 검사: 실제 입력 경로(debug_swipe/debug_press/debug_tap)로 무작위 입력을 넣어
## 스크립트 오류 없이 상태가 항상 유효한지 본다. 그리기도 함께 돌도록 여러 프레임에 나눠 넣는다.
## tools/smoke.py 가 smoke.gd 다음에 실행한다.

const INPUTS_PER_FRAME := 8
const FRAMES := 260
const BUTTONS: Array[String] = ["water", "close", "carry", "wait", "retreat"]

var game: Node
var frame := 0
var rng := RandomNumberGenerator.new()
var failures: Array[String] = []
var results := {"retreat": 0, "dead": 0, "limit": 0}
var buildings_seen := {}
var actions := 0
var rejected := 0


func _initialize() -> void:
	rng.seed = 20261001
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func check(ok: bool, label: String) -> void:
	if not ok and failures.size() < 10:
		failures.append("%s (frame %d, building %d, clock %d)" % [label, frame, game.building_index, game.clock])


func random_input() -> void:
	if game.state != game.State.PLAY:
		if game.state == game.State.RESULT:
			results[game.result_cause] = int(results.get(game.result_cause, 0)) + 1
			check(game.result_stars >= 0 and game.result_stars <= 3, "별 0~3")
			check(game.result_cause != "dead" or game.result_stars == 0, "순직이면 별 0")
			var before: int = game.clock
			game.debug_swipe(Vector2(270, 300), Vector2(270, 220))
			check(game.state != game.State.RESULT or game.clock == before, "결과 화면에서 행동이 진행되지 않는다")
			if game.state == game.State.RESULT:
				game.debug_tap(Vector2(270, 480))
		else:
			game.debug_tap(Vector2(270, 480))
		return
	buildings_seen[game.building_index] = true
	var clock0: int = game.clock
	var roll := rng.randf()
	if roll < 0.62:
		var d: Vector2 = [Vector2(0, -60), Vector2(60, 0), Vector2(0, 60), Vector2(-60, 0)][rng.randi() % 4]
		# 위쪽으로 가는 쪽을 조금 더 자주(출구가 아래라 안으로 들어가게)
		if rng.randf() < 0.25:
			d = Vector2(0, -60)
		game.debug_swipe(Vector2(270, 300), Vector2(270, 300) + d)
	elif roll < 0.66:
		game.debug_swipe(Vector2(270, 300), Vector2(280, 306))     # 짧은 밀기: 아무 일도 없어야 한다
		check(game.clock == clock0, "24px 미만 밀기는 무시")
	else:
		var id := BUTTONS[rng.randi() % BUTTONS.size()]
		if id == "retreat" and rng.randf() < 0.7:
			id = "wait"
		game.debug_press(id)
	if game.clock > clock0:
		actions += 1
	else:
		rejected += 1
	# 불변식
	check(game.hp >= 0 and game.hp <= 4, "체력 0~4")
	check(game.water >= 0, "물 0 이상")
	check(game.clock >= clock0 and game.clock - clock0 <= 4, "한 입력은 0~4행동")
	check(game.beat == game.clock / 2, "박자 = 행동 수 / 2")
	check(game.clock <= 600, "행동 상한 600")
	check(game.mode == "" or game.mode == "water" or game.mode == "close", "방향 대기 값")
	var carried := 0
	var saved := 0
	for v in game.victims:
		check(v["breath"] >= 0 and v["breath"] <= 12, "숨 0~12")
		check(v["state"] in ["in", "carried", "saved", "dead"], "사람 상태")
		check(v["state"] != "dead" or true, "")
		if v["state"] == "carried":
			carried += 1
			check(v["pos"] == game.pos, "업힌 사람의 칸 = 소방관 칸")
		if v["state"] == "saved":
			saved += 1
	check(carried == (1 if game.carrying else 0), "업힌 사람은 0명 또는 1명")
	check(saved == game.saved, "구조 수")
	var cell: Dictionary = game.debug_cell(game.pos)
	check(cell["kind"] in [".", "D", "E"] and not cell["furn"], "소방관은 걸을 수 있는 칸에 있다")
	for p in game.forecast:
		var fc: Dictionary = game.debug_cell(p)
		check(fc["kind"] == "." and fc["fire"] == 0 and fc["fuel"] > 0, "예보 칸은 아직 불이 아닌, 탈 것이 남은 바닥")
	if game.state == game.State.RESULT:
		check(game.result_cause in ["retreat", "dead", "limit"], "결과 원인")
		check((game.result_cause == "dead") == (game.hp == 0), "체력 0 ⇔ 순직")


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame < 3 + FRAMES:
		for i in INPUTS_PER_FRAME:
			random_input()
		return false
	check(actions > 300, "행동이 300번 넘게 진행됨(%d)" % actions)
	check(rejected > 50, "거절된 입력도 섞임(%d)" % rejected)
	check(int(results["dead"]) + int(results["retreat"]) + int(results["limit"]) >= 3, "출동이 3번 넘게 끝남")
	check(buildings_seen.size() >= 2, "건물이 2채 넘게 나옴")
	print("extra: 행동 %d, 거절 %d, 결과 %s, 건물 %s" % [actions, rejected, results, buildings_seen.keys()])
	for f in failures:
		printerr("SMOKE FAIL ", f)
	print("SMOKE %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
	return false
