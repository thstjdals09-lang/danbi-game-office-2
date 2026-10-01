extends SceneTree
## 빌드실이 덧붙인 검사: 실제 입력 경로(debug_swipe/debug_press/debug_tap)로 무작위 입력을 넣어
## 스크립트 오류 없이 상태가 항상 유효한지 본다. 그리기도 함께 돌도록 여러 프레임에 나눠 넣는다.
## tools/smoke.py 가 smoke.gd 다음에 실행한다.

const Content := preload("res://scripts/content.gd")

const INPUTS_PER_FRAME := 6
const FRAMES := 300

var game: Node
var frame := 0
var rng := RandomNumberGenerator.new()
var failures: Array[String] = []
var runs_finished := 0
var wins := 0
var shield_runs := 0
var seen := {"sword_out": 0, "shield_hurt": 0, "crush": 0}


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
		# 2차: 세 번에 한 번은 방패병 층(4·5층)에서 바로 시작해 새 규칙이 무작위 입력에 걸리게 한다
		if runs_finished % 3 == 2:
			shield_runs += 1
			game.debug_load_floors([Content.FLOORS[3], Content.FLOORS[4]])
		else:
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
		# 2차: 종류·체력·바라보는 방향
		check(e["kind"] in ["W", "A", "S"], "적 종류가 유효하지 않음")
		check(e["hp"] >= 1 and e["hp"] <= (2 if e["kind"] == "S" else 1), "적 체력 범위 밖: %s %d" % [e["kind"], e["hp"]])
		check(e["face"] in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)], "face 가 네 방향이 아님")
		if e["intent"] == "hit":
			check(e["face"] == e["dir"], "치려는 적이 그쪽을 보고 있지 않음")
		if e["kind"] == "S" and e["hp"] == 1:
			seen_count("shield_hurt")
		seen[c] = true
	if game.state == game.State.PLAY:
		check(game.hp > 0, "PLAY 인데 hp 0")
	for k in ["stomp", "slash", "friendly", "crush"]:
		check(game.kills[k] >= 0, "kills 음수")
	if game.kills["crush"] > 0:
		seen_count("crush")
	# 2차 칼 하나: sword_wait 는 0~3이고, "발자국에 칼이 있다" ⇔ "칼이 없다"
	var sw: int = game.sword_wait
	check(sw >= 0 and sw <= 3, "sword_wait 범위 밖: %d" % sw)
	if game.state == game.State.PLAY:
		var slashes := 0
		for f in game.footprints:
			if String(f["act"]).begins_with("S"):
				slashes += 1
				check(sw == f["in"], "sword_wait(%d)가 칼이 실린 발자국의 남은 턴(%d)과 다름" % [sw, f["in"]])
		check(slashes <= 1, "칼이 실린 발자국이 둘 이상(칼은 하나)")
		check((slashes == 1) == (sw > 0), "발자국의 칼과 sword_wait 가 어긋남")
		if sw > 0:
			seen_count("sword_out")
			var t: int = game.turn
			check(not game.debug_act("SU") and not game.debug_act("SR") and not game.debug_act("SD") and not game.debug_act("SL"), "칼이 없는데 베기가 받아들여짐")
			check(game.turn == t, "거절된 베기가 턴을 씀")


func seen_count(key: String) -> void:
	seen[key] += 1


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
	check(shield_runs >= 2, "방패병 층에서 시작한 런이 2개 미만: %d" % shield_runs)
	check(seen["sword_out"] > 0, "칼이 없는 상태를 한 번도 지나가지 않음")
	print("extra: 방패병 층 런 %d개, 칼 없는 상태 %d번, 다친 방패병 %d번, 으깨기 본 입력 %d번" % [shield_runs, seen["sword_out"], seen["shield_hurt"], seen["crush"]])
	for f in failures:
		printerr("SMOKE FAIL extra ", f)
	print("extra: 입력 %d번, 끝난 런 %d개(승리 %d)" % [(FRAMES - 2) * INPUTS_PER_FRAME, runs_finished, wins])
	print("SMOKE %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
	return false
