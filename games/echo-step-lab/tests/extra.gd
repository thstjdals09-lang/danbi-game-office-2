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
var main_runs := 0
var fx_seen := {}
const FX_NAMES := ["step", "slash_arc", "echo_stomp", "echo_slash_arc", "kill_shards", "afterglow", "push_streak", "crush_shake",
	"deflect_sparks", "bomb_throw", "blast_embers", "hurt_heart", "floor_sweep", "confetti", "rewind_flash"]
var seen := {"sword_out": 0, "shield_hurt": 0, "crush": 0, "bomb": 0, "bomb_intent": 0, "rewind": 0}


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
		elif runs_finished % 3 == 1:
			# 3차: 본편 층(6~10층) 가운데 둘에서 시작해 폭탄병이 무작위 입력에 걸리게 한다
			main_runs += 1
			var a := 5 + (main_runs % 5)
			game.debug_load_floors([Content.FLOORS[a], Content.FLOORS[5 + ((a - 4) % 5)]])
		else:
			game.debug_tap(Vector2(270, 480))
		return
	var r := rng.randi_range(0, 10)
	if r == 10:
		# 3차 되감기: 성공하면 정확히 한 턴 전이어야 하고, 실패하면 아무것도 바뀌지 않아야 한다
		var t0: int = game.turn
		var left: int = game.rewinds_left
		var f0: int = game.floor_index
		game.debug_press("rewind")
		if game.rewinds_left == left - 1:
			seen_count("rewind")
			check(game.turn == t0 - 1 and game.floor_index == f0, "되감기가 한 턴 전이 아님: %d → %d" % [t0, game.turn])
		else:
			check(game.turn == t0 and game.rewinds_left == left, "실패한 되감기가 상태를 바꿈")
	elif r == 0:
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
		check(e["intent"] in ["move", "hit", "aim", "bomb", "none"], "의도 값이 유효하지 않음")
		# 2차: 종류·체력·바라보는 방향
		check(e["kind"] in ["W", "A", "S", "B"], "적 종류가 유효하지 않음")
		# 3차 폭탄병: 쿨다운 0~3, 던지기 의도면 대상 칸이 보드 안이고 쿨다운 0, 폭탄병은 치지 않는다
		check(e["cool"] >= 0 and e["cool"] <= 3 and (e["kind"] == "B" or e["cool"] == 0), "쿨다운 범위 밖")
		if e["intent"] == "bomb":
			seen_count("bomb_intent")
			var tg: Vector2i = e["target"]
			check(e["kind"] == "B" and e["cool"] == 0 and tg.x >= 0 and tg.x < 7 and tg.y >= 0 and tg.y < 7, "던지기 의도가 유효하지 않음")
			if game.state == game.State.PLAY:
				check(tg == p, "던지기 대상이 지금의 플레이어 칸이 아님")
		else:
			check(e["target"] == Vector2i(-1, -1), "던지기가 아닌데 target 이 있음")
		if e["kind"] == "B":
			check(e["intent"] != "hit", "폭탄병이 치려 함")
		check(e["hp"] >= 1 and e["hp"] <= (2 if e["kind"] == "S" else 1), "적 체력 범위 밖: %s %d" % [e["kind"], e["hp"]])
		check(e["face"] in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)], "face 가 네 방향이 아님")
		if e["intent"] == "hit":
			check(e["face"] == e["dir"], "치려는 적이 그쪽을 보고 있지 않음")
		if e["kind"] == "S" and e["hp"] == 1:
			seen_count("shield_hurt")
		seen[c] = true
	if game.state == game.State.PLAY:
		check(game.hp > 0, "PLAY 인데 hp 0")
	# 3차 폭탄: 턴이 끝난 뒤 남아 있는 폭탄의 남은 턴은 항상 1, 칸은 보드 안. 되감기 횟수는 0~1
	for b in game.bombs:
		seen_count("bomb")
		var bp: Vector2i = b["pos"]
		check(b["fuse"] == 1, "남은 턴이 1이 아닌 폭탄이 남아 있음: %d" % b["fuse"])
		check(bp.x >= 0 and bp.x < 7 and bp.y >= 0 and bp.y < 7, "폭탄이 보드 밖")
	check(game.rewinds_left >= 0 and game.rewinds_left <= 1, "rewinds_left 범위 밖")
	# 4차 연출: 이름은 배선표에 있는 것만, 흔들림은 정해진 값만, 한 턴 연출은 0.9초 이하. 연출 이름과 흔들림이 서로 맞아야 한다
	check(game.last_anim_duration >= 0.0 and game.last_anim_duration <= 0.9001, "연출 길이가 0.9초를 넘음: %.2f" % game.last_anim_duration)
	check(game.last_shake in [0.0, 4.0, 5.0, 6.0, 8.0], "흔들림 값이 배선표에 없음: %.1f" % game.last_shake)
	var want_shake := 0.0
	for n in game.last_fx:
		fx_seen[n] = fx_seen.get(n, 0) + 1
		check(n in FX_NAMES or String(n).begins_with("combo_"), "배선표에 없는 연출 이름: %s" % n)
		want_shake = maxf(want_shake, {"kill_shards": 4.0, "crush_shake": 5.0, "hurt_heart": 6.0, "blast_embers": 8.0}.get(n, 6.0 if String(n).begins_with("combo_") else 0.0))
	check(is_equal_approx(game.last_shake, want_shake), "연출 목록과 흔들림이 어긋남: %s → %.1f" % [str(game.last_fx), game.last_shake])
	check(game.last_fx.has("afterglow") == game.last_fx.has("kill_shards"), "kill_shards 와 afterglow 는 함께 나와야 함")
	if game.last_fx.has("rewind_flash"):
		check(game.last_fx.size() == 1 and game.last_anim_duration == 0.0, "되감기 뒤에는 rewind_flash 하나뿐이어야 함")
	if game.state == game.State.PLAY and game.turn == 0:
		check(game.bombs.is_empty(), "턴 0인데 폭탄이 놓여 있음")  # 되감기로 턴 0에 돌아온 경우 rewinds_left 는 0일 수 있다
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
	check(main_runs >= 2 and seen["bomb"] > 0 and seen["bomb_intent"] > 0, "폭탄병·폭탄을 지나가지 않음")
	check(seen["rewind"] > 0, "되감기가 한 번도 성공하지 않음")
	var missing: Array = []
	for n in FX_NAMES:
		if n != "confetti" and not fx_seen.has(n):
			missing.append(n)
	check(missing.is_empty(), "무작위 입력이 한 번도 지나가지 않은 연출: %s" % str(missing))
	print("extra: 지나간 연출 %d종 %s" % [fx_seen.size(), str(fx_seen)])
	print("extra: 본편 층 런 %d개, 던지기 의도 %d번, 놓인 폭탄 %d번, 되감기 성공 %d번" % [main_runs, seen["bomb_intent"], seen["bomb"], seen["rewind"]])
	print("extra: 방패병 층 런 %d개, 칼 없는 상태 %d번, 다친 방패병 %d번, 으깨기 본 입력 %d번" % [shield_runs, seen["sword_out"], seen["shield_hurt"], seen["crush"]])
	for f in failures:
		printerr("SMOKE FAIL extra ", f)
	print("extra: 입력 %d번, 끝난 런 %d개(승리 %d)" % [(FRAMES - 2) * INPUTS_PER_FRAME, runs_finished, wins])
	print("SMOKE %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
	return false
