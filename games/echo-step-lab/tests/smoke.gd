extends SceneTree
## 메아리 발자국 — 첫 빌드 검사 (기획실 작성, 기획 v1)
## design/spec.json 의 must_work M1~M12 를 design/FIRST_BUILD.md "테스트 인터페이스"만 써서 확인한다.
## 기대값은 design/first_build_replay.py (기준 구현 design/sim/sim.py)로 계산했다.
## 빌드실은 이 파일을 바꾸지 않는다. 틀렸다고 판단되면 반송한다.
## 실행: python tools/smoke.py games/echo-step-tactics

const F1 := "U SU SL SL R U R SR SU SR W"
const F2 := "L L U SU R L SL SR SR SR SR SU"
const F3 := "U R SU SR SU SU SU SU SR SR SR U"

var game: Node
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		run_all()
		for f in failures:
			printerr("SMOKE FAIL ", f)
		print("SMOKE %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
		quit(0 if failures.is_empty() else 1)
	return false


func run_all() -> void:
	m1_title_starts_floor_one()
	m9_golden_replay()
	m12_touch_input()
	m2_illegal_actions()
	m3_echo_delay_and_footprints()
	m4_stomp()
	m5_slash()
	m6_wolf_hit_and_dodge()
	m7_archer_and_echo_block()
	m8_friendly_fire()
	m11_pressure_and_turn_limit()
	m10_defeat_and_restart()


# ---------------------------------------------------------------- 도우미

func check(id: String, ok: bool, label: String) -> void:
	print("[%s] %s %s" % [id, "ok  " if ok else "FAIL", label])
	if not ok:
		failures.append("%s %s" % [id, label])


func V(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


func load_floor(walls: Array, start: Vector2i, enemies: Array, spawns: Array = []) -> void:
	game.debug_load_floors([{"walls": walls, "start": start, "enemies": enemies, "spawns": spawns}])


## 공백으로 구분한 행동을 차례로 확정한다. 하나라도 거절되면 false.
func acts(seq: String) -> bool:
	var all_ok := true
	for a in seq.split(" ", false):
		if not game.debug_act(a):
			all_ok = false
	return all_ok


func waits(n: int) -> void:
	for i in n:
		game.debug_act("W")


func fp_is(i: int, pos: Vector2i, act: String, turns: int) -> bool:
	if game.footprints.size() <= i:
		return false
	var f: Dictionary = game.footprints[i]
	return f["pos"] == pos and f["act"] == act and f["in"] == turns


func kills_are(stomp: int, slash: int, friendly: int) -> bool:
	return game.kills["stomp"] == stomp and game.kills["slash"] == slash and game.kills["friendly"] == friendly


# ---------------------------------------------------------------- 검사

func m1_title_starts_floor_one() -> void:
	check("M1", game.state == game.State.TITLE, "실행 직후 타이틀")
	game.debug_tap(Vector2(270, 480))
	check("M1", game.state == game.State.PLAY, "탭하면 플레이")
	check("M1", game.floor_index == 0 and game.floor_count == 3 and game.turn == 0, "1층, 전체 3층, 턴 0")
	check("M1", game.hp == 5 and game.player == V(3, 6), "체력 5, 시작 칸 (3,6)")
	check("M1", game.enemies.size() == 2 and game.spawns_pending == 1, "1층 적 2, 증원 예고 1")
	var e: Dictionary = game.enemies[0]
	check("M1", e["id"] == 0 and e["kind"] == "W" and e["pos"] == V(3, 0), "적 0번은 졸개 (3,0)")
	check("M1", e["intent"] == "move" and e["dir"] == V(0, 1), "졸개 (3,0)의 공개된 의도: 아래로 이동")
	check("M1", game.footprints.is_empty() and not game.echo_active, "턴 0에는 발자국·메아리 없음")


func m9_golden_replay() -> void:
	# M1 직후: 기본 3개 층의 새 런, 1층 턴 0
	check("M9", acts(F1), "1층 정답 11행동이 모두 가능한 행동")
	check("M9", game.state == game.State.PLAY and game.floor_index == 1 and game.turn == 0, "1층 클리어 → 2층 턴 0")
	check("M9", game.hp == 5 and game.player == V(3, 6), "2층 시작: 체력 5(최대), 시작 칸")
	check("M9", kills_are(0, 3, 0), "1층 처치: 베기 3")
	check("M9", not game.echo_active and game.footprints.is_empty(), "새 층에서 메아리·발자국 초기화")
	check("M9", acts(F2), "2층 정답 12행동이 모두 가능한 행동")
	check("M9", game.state == game.State.PLAY and game.floor_index == 2 and game.turn == 0, "2층 클리어 → 3층 턴 0")
	check("M9", kills_are(1, 6, 0), "2층까지 처치: 밟기 1, 베기 6")
	check("M9", acts(F3), "3층 정답 12행동이 모두 가능한 행동")
	check("M9", game.state == game.State.RESULT and game.result_won, "3층 클리어 → 결과 화면, 승리")
	check("M9", game.hp == 5 and kills_are(1, 11, 0), "승리 시 체력 5, 처치 밟기 1 · 베기 11 · 오사 0")


func m12_touch_input() -> void:
	# M9 직후: 결과 화면(승리). 탭하면 1층부터 새 런
	game.debug_tap(Vector2(270, 480))
	check("M12", game.state == game.State.PLAY and game.floor_index == 0 and game.turn == 0 and kills_are(0, 0, 0), "승리 결과에서 탭 → 1층 새 런")
	game.debug_swipe(Vector2(270, 820), Vector2(270, 812))
	check("M12", game.turn == 0 and game.player == V(3, 6), "24px 미만으로 밀면 아무 일도 없음")
	game.debug_swipe(Vector2(270, 820), Vector2(270, 760))
	check("M12", game.player == V(3, 5) and game.turn == 1 and game.last_action == "U", "위로 밀면 위로 이동")
	game.debug_press("slash")
	game.debug_swipe(Vector2(270, 820), Vector2(270, 760))
	check("M12", game.player == V(3, 5) and game.turn == 2 and game.last_action == "SU", "베기를 켜고 위로 밀면 위로 베기(제자리)")
	game.debug_swipe(Vector2(200, 820), Vector2(260, 824))
	check("M12", game.player == V(4, 5) and game.turn == 3 and game.last_action == "R", "베기는 한 번 쓰면 꺼진다 → 오른쪽으로 밀면 이동")
	game.debug_press("wait")
	check("M12", game.player == V(4, 5) and game.turn == 4 and game.last_action == "W", "대기 버튼으로 한 턴")


func m2_illegal_actions() -> void:
	load_floor([V(3, 5)], V(3, 6), [["A", V(2, 6)]])
	check("M2", game.state == game.State.PLAY and game.floor_index == 0 and game.floor_count == 1 and game.turn == 0 and game.hp == 5, "debug_load_floors: 1개 층 새 런")
	check("M2", not game.debug_act("U"), "벽으로 이동 불가")
	check("M2", not game.debug_act("SU"), "벽으로 베기 불가")
	check("M2", not game.debug_act("D"), "보드 밖으로 이동 불가")
	check("M2", not game.debug_act("SD"), "보드 밖으로 베기 불가")
	check("M2", not game.debug_act("L"), "적이 있는 칸으로 이동 불가")
	check("M2", game.turn == 0 and game.player == V(3, 6) and game.last_action == "", "거절된 행동은 턴을 쓰지 않는다")
	check("M2", game.debug_act("SL") and game.turn == 1 and game.player == V(3, 6), "적이 있는 칸으로 베기는 가능(제자리)")
	check("M2", game.debug_act("R") and game.turn == 2 and game.player == V(4, 6), "빈 칸으로 이동 가능")


func m3_echo_delay_and_footprints() -> void:
	# 벽에 갇혀 움직이지 못하는 졸개 하나
	load_floor([V(1, 0), V(0, 1)], V(3, 6), [["W", V(0, 0)]])
	check("M3", game.enemies[0]["intent"] == "none" and game.enemies[0]["dir"] == Vector2i.ZERO, "길이 없는 졸개는 의도 없음")
	acts("U")
	check("M3", game.footprints.size() == 1 and fp_is(0, V(3, 5), "U", 3), "1턴 뒤 발자국 1개: (3,5) U, 3턴 뒤")
	acts("U U")
	check("M3", game.turn == 3 and not game.echo_active, "3턴까지 메아리 없음")
	check("M3", game.footprints.size() == 3 and fp_is(0, V(3, 5), "U", 1) and fp_is(1, V(3, 4), "U", 2) and fp_is(2, V(3, 3), "U", 3), "3턴 뒤 발자국 ①(3,5) ②(3,4) ③(3,3)")
	acts("SL")
	check("M3", game.turn == 4 and game.echo_active and game.echo_pos == V(3, 5), "4턴째에 메아리가 1턴째 칸 (3,5)에 나타남")
	check("M3", game.player == V(3, 3) and fp_is(0, V(3, 4), "U", 1) and fp_is(2, V(3, 3), "SL", 3), "발자국이 한 칸씩 당겨지고 베기 SL이 ③으로 들어감")


func m4_stomp() -> void:
	load_floor([], V(3, 6), [["W", V(3, 2)]])
	check("M4", game.enemies[0]["intent"] == "move" and game.enemies[0]["dir"] == V(0, 1), "졸개는 플레이어 쪽(아래)으로 이동 의도")
	acts("U D R")
	check("M4", game.enemies.size() == 1 and game.enemies[0]["pos"] == V(3, 5) and game.hp == 5, "3턴 뒤 졸개가 내 첫 발자국 칸 (3,5)에 서 있음")
	check("M4", fp_is(0, V(3, 5), "U", 1), "다음 턴 메아리가 (3,5)를 밟을 예정")
	acts("U")
	check("M4", kills_are(1, 0, 0) and game.hp == 5, "메아리가 (3,5)를 밟아 졸개 처치(밟기 1), 피해 없음")
	check("M4", game.state == game.State.RESULT and game.result_won, "적 0, 증원 0 → 마지막 층 클리어 → 승리")


func m5_slash() -> void:
	load_floor([], V(3, 6), [["A", V(3, 5)]])
	check("M5", game.enemies[0]["intent"] == "none", "붙어 있는 궁수는 의도 없음(최소 사거리 2)")
	acts("SU W W")
	check("M5", game.enemies.size() == 1 and kills_are(0, 0, 0) and game.hp == 5 and game.turn == 3, "베기 직후 3턴 동안은 아무 일도 없음")
	acts("W")
	check("M5", kills_are(0, 1, 0), "4턴째에 메아리가 대신 베어 궁수 처치(베기 1)")
	check("M5", game.state == game.State.RESULT and game.result_won, "승리")


func m6_wolf_hit_and_dodge() -> void:
	load_floor([], V(3, 6), [["W", V(3, 5)]])
	check("M6", game.enemies[0]["intent"] == "hit" and game.enemies[0]["dir"] == V(0, 1), "붙은 졸개의 의도: 아래로 치기")
	acts("W")
	check("M6", game.hp == 4, "그 칸에 그대로 있으면 피해 1")
	check("M6", game.enemies[0]["intent"] == "hit" and game.enemies[0]["dir"] == V(0, 1), "다음 의도도 아래로 치기")
	acts("L")
	check("M6", game.hp == 4 and game.player == V(2, 6), "공개된 치기를 옆으로 피하면 피해 없음")
	check("M6", game.enemies[0]["pos"] == V(3, 5), "헛친 졸개는 제자리")
	check("M6", game.enemies[0]["intent"] == "move" and game.enemies[0]["dir"] == V(0, 1), "다음 의도: 길 찾기 첫 걸음(아래)")


func m7_archer_and_echo_block() -> void:
	load_floor([], V(3, 3), [["A", V(3, 0)]])
	check("M7", game.enemies[0]["intent"] == "aim" and game.enemies[0]["dir"] == V(0, 1), "사선의 궁수 의도: 아래로 조준")
	acts("D")
	check("M7", game.hp == 4, "사선 위에서 움직이면 화살에 맞음")
	acts("D D")
	check("M7", game.hp == 2 and game.player == V(3, 6), "세 번 맞아 체력 2")
	acts("W")
	check("M7", game.echo_active and game.echo_pos == V(3, 4), "4턴째 메아리가 사선 위 (3,4)에 섬")
	check("M7", game.hp == 2, "메아리가 화살을 막아 피해 없음")
	check("M7", game.enemies[0]["intent"] == "move" and game.enemies[0]["dir"] == V(1, 0), "사선이 막힌 궁수는 사선을 잡으러 이동(오른쪽)")
	acts("W")
	check("M7", game.hp == 2 and game.enemies[0]["pos"] == V(4, 0), "이동한 턴에는 쏘지 않음, 궁수 (4,0)")


func m8_friendly_fire() -> void:
	load_floor([], V(3, 6), [["W", V(2, 4)], ["A", V(3, 0)]])
	check("M8", game.enemies[0]["intent"] == "move" and game.enemies[0]["dir"] == V(1, 0), "졸개(id 0) 의도: 오른쪽으로 이동(사선 안으로)")
	check("M8", game.enemies[1]["intent"] == "aim" and game.enemies[1]["dir"] == V(0, 1), "궁수(id 1) 의도: 아래로 조준")
	acts("W")
	check("M8", kills_are(0, 0, 1) and game.hp == 5, "먼저 움직인 졸개가 화살에 맞음(오사 1), 플레이어 피해 없음")
	check("M8", game.enemies.size() == 1 and game.enemies[0]["kind"] == "A" and game.enemies[0]["id"] == 1, "남은 적은 궁수(id 1)")


func m11_pressure_and_turn_limit() -> void:
	# 졸개는 (0,0)에 갇혀 있고, 증원 칸 (3,0)도 벽으로 막혀 있어 플레이어는 안전하다
	load_floor([V(1, 0), V(0, 1), V(2, 0), V(4, 0), V(3, 1)], V(3, 6), [["W", V(0, 0)]])
	waits(29)
	check("M11", game.turn == 29 and game.enemies.size() == 1 and game.spawns_pending == 0, "29턴까지 증원 없음")
	waits(1)
	check("M11", game.enemies.size() == 1 and game.spawns_pending == 1, "30턴이 끝나면 증원 예고 1")
	waits(1)
	check("M11", game.enemies.size() == 2 and game.enemies[1]["kind"] == "W" and game.enemies[1]["pos"] == V(3, 0), "31턴이 끝나면 (3,0)에 졸개 등장")
	check("M11", game.enemies[1]["id"] == 1, "증원의 id는 다음 번호")
	waits(3)
	check("M11", game.turn == 34 and game.enemies.size() == 2 and game.spawns_pending == 1, "(3,0)이 막혀 있으면 다음 증원은 미뤄짐")
	waits(25)
	check("M11", game.turn == 59 and game.state == game.State.PLAY and game.hp == 5, "59턴까지 진행 중")
	waits(1)
	check("M11", game.state == game.State.RESULT and not game.result_won and game.hp == 5, "60턴이 끝나면 패배(메아리 붕괴)")


func m10_defeat_and_restart() -> void:
	load_floor([], V(3, 6), [["W", V(3, 5)]])
	waits(4)
	check("M10", game.hp == 1 and game.state == game.State.PLAY, "네 번 맞아 체력 1")
	waits(1)
	check("M10", game.hp == 0 and game.state == game.State.RESULT and not game.result_won, "체력 0 → 결과 화면, 패배")
	check("M10", not game.debug_act("W"), "결과 화면에서는 행동 불가")
	game.debug_tap(Vector2(270, 480))
	check("M10", game.state == game.State.PLAY and game.floor_index == 0 and game.floor_count == 3, "탭하면 기본 3개 층으로 새 런")
	check("M10", game.hp == 5 and game.turn == 0 and kills_are(0, 0, 0) and game.enemies.size() == 2, "체력 5, 턴 0, 처치 0, 1층 적 2")
