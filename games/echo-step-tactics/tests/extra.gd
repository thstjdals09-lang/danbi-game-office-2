extends SceneTree
## 빌드실이 덧붙인 검사: 실제 입력 경로(debug_swipe/debug_press/debug_tap)로 무작위 입력을 넣어
## 스크립트 오류 없이 상태가 항상 유효한지 본다. 그리기도 함께 돌도록 여러 프레임에 나눠 넣는다.
## tools/smoke.py 가 smoke.gd 다음에 실행한다.

const INPUTS_PER_FRAME := 6
const FRAMES := 300

var game: Node
var frame := 0
var rng := RandomNumberGenerator.new()
var failures: Array[String] = []
var runs_finished := 0
var wins := 0


func _initialize() -> void:
	rng.seed = 20261001
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func check(ok: bool, label: String) -> void:
	if not ok and failures.size() < 10:
		failures.append("%s (frame %d, floor %d, turn %d)" % [label, frame, game.floor_index, game.turn])


func random_input() -> void:
	if game.state != game.State.PLAY:
		if game.state == game.State.RESULT:
			runs_finished += 1
			if game.result_won:
				wins += 1
		game.debug_tap(Vector2(270, 480))
		return
	var r := rng.randi_range(0, 9)
	if r == 0:
		game.debug_press("wait")
	elif r <= 2:
		game.debug_press("slash")
	elif r == 3:
		game.debug_swipe(Vector2(270, 820), Vector2(270 + rng.randf_range(-15, 15), 820 + rng.randf_range(-15, 15)))  # 짧은 밀기(취소)
	else:
		var from := Vector2(rng.randf_range(60, 480), rng.randf_range(140, 900))
		var dir: Vector2 = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][rng.randi_range(0, 3)]
		game.debug_swipe(from, from + dir * rng.randf_range(30, 120))


func invariants() -> void:
	check(game.state in [game.State.TITLE, game.State.PLAY, game.State.RESULT], "state 가 유효하지 않음")
	check(game.hp >= 0 and game.hp <= 5, "hp 범위 밖: %d" % game.hp)
	check(game.floor_index >= 0 and game.floor_index < game.floor_count, "floor_index 범위 밖")
	check(game.turn >= 0 and game.turn <= 60, "turn 범위 밖: %d" % game.turn)
	check(game.footprints.size() <= 3, "발자국이 3개를 넘음")
	var p: Vector2i = game.player
	check(p.x >= 0 and p.x < 7 and p.y >= 0 and p.y < 7, "플레이어가 보드 밖")
	var seen := {}
	for e in game.enemies:
		var c: Vector2i = e["pos"]
		check(c.x >= 0 and c.x < 7 and c.y >= 0 and c.y < 7, "적이 보드 밖")
		check(not seen.has(c), "적이 같은 칸에 겹침")
		check(c != p, "적과 플레이어가 같은 칸")
		check(e["intent"] in ["move", "hit", "aim", "none"], "의도 값이 유효하지 않음")
		seen[c] = true
	if game.state == game.State.PLAY:
		check(game.hp > 0, "PLAY 인데 hp 0")
	for k in ["stomp", "slash", "friendly"]:
		check(game.kills[k] >= 0, "kills 음수")


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame <= FRAMES:
		for i in INPUTS_PER_FRAME:
			random_input()
			invariants()
		return false
	check(runs_finished >= 5, "무작위 입력으로 끝난 런이 5개 미만: %d" % runs_finished)
	for f in failures:
		printerr("SMOKE FAIL extra ", f)
	print("extra: 입력 %d번, 끝난 런 %d개(승리 %d)" % [(FRAMES - 2) * INPUTS_PER_FRAME, runs_finished, wins])
	print("SMOKE %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
	return false
