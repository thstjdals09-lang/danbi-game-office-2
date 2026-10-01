extends SceneTree
## 같은 하루 — 첫 빌드 검사 (기획실 작성, 기획 v1)
## design/spec.json 의 must_work M1~M12 를 design/FIRST_BUILD.md "테스트 인터페이스"만 써서 확인한다.
## 기대값은 design/first_build_replay.py (기준 구현 design/sim/sim.py)로 계산했다. 장면 MINI 도 그 스크립트가 만든 것이다.
## 빌드실은 이 파일을 바꾸지 않는다. 틀렸다고 판단되면 반송한다.
## 실행: python tools/smoke.py games/loop-village

# 탐험 바퀴(빵집에서 30틱까지)가 남기는 수첩 — replay 2번
const NOTES1 := ["N_slip", "N_slipfall", "N_dough", "N_nowood", "N_burnt"]

# 규칙 장면(replay 9번). 형식은 FIRST_BUILD.md "콘텐츠". 장소 a–b(2틱), 주민 하나(b), 줍기(1틱), 고치기(3틱, 9틱까지), 10틱 사건 late(fixed 가 없으면)
const MINI := '{"ticks":90,"tick_seconds":2.0,"fast_seconds":0.5,"start":"a","max_items":2,"max_queue":3,"places":[{"id":"a","name":"가"},{"id":"b","name":"나"}],"edges":[["a","b",2]],"npcs":[{"id":"n1","name":"하나"}],"itinerary":[{"npc":"n1","t0":0,"t1":89,"loc":"b","need":[],"forbid":[]}],"events":[{"t":10,"set":["late"],"need":[],"forbid":["fixed"]}],"scenes":[{"note":"S_ok","who":"n1","loc":["b"],"t0":10,"t1":12,"text":"고쳐졌다","need":["fixed"],"forbid":[]},{"note":"S_late","who":"n1","loc":["b"],"t0":10,"t1":12,"text":"늦었다","need":["late"],"forbid":[]}],"actions":[{"id":"pick","label":"돌을 줍는다","loc":"a","t0":0,"t1":89,"know":[],"items":[],"npc":"","dur":1,"take":[],"give":["stone"],"set":[],"text":"돌을 줍는다","need":[],"forbid":[]},{"id":"fix","label":"고친다","loc":"b","t0":0,"t1":9,"know":[],"items":["stone"],"npc":"n1","dur":3,"take":["stone"],"give":[],"set":["fixed"],"text":"3틱 걸려 고친다","need":[],"forbid":[]}],"goal":["fixed"],"goal_name":"작은 장면","item_names":{"stone":"돌"}}'

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
	m1_title_starts_first_morning()
	m2_time()
	m3_walking()
	m4_default_day()
	m5_witness()
	m6_action_timing()
	m7_notebook_opens_choices()
	m8_two_loops_solve()
	m9_missing_or_late()
	m10_reset_keeps_notebook()
	m11_queue()
	m12_timetable()


# ---------------------------------------------------------------- 도우미

func check(id: String, ok: bool, label: String) -> void:
	print("[%s] %s %s" % [id, "ok  " if ok else "FAIL", label])
	if not ok:
		failures.append("%s %s" % [id, label])


## 배열을 "a,b,c" 로. 타입이 다른 배열끼리 비교하지 않으려고 글자로 비교한다.
func j(arr: Array) -> String:
	var out: Array[String] = []
	for x in arr:
		out.append(str(x))
	return ",".join(out)


func has(arr: Array, x: String) -> bool:
	return arr.has(x)


## 기본 콘텐츠로 처음부터 시작해 첫 아침(0틱)에 선다.
func start() -> void:
	game.debug_reset()
	game.debug_tap(Vector2(270, 480))


func until(t: int) -> void:
	game.debug_tick(t - game.tick)


func npc(id: String) -> String:
	return game.debug_npc_place(id)


## 정답의 앞부분: (wait틱 기다린 뒤) 대장간에서 장작을 들고 빵집에 선다.
func fetch_wood(wait: int) -> void:
	game.debug_tick(wait)
	game.debug_go("smithy")
	game.debug_tick(5)
	game.debug_do("wood_take")
	game.debug_tick(1)
	game.debug_go("bakery")
	game.debug_tick(5)


## 탐험 바퀴: 빵집으로 가서 30틱까지 지켜본다.
func explore_bakery() -> void:
	game.debug_go("bakery")
	until(30)


# ---------------------------------------------------------------- 검사

func m1_title_starts_first_morning() -> void:
	check("M1", game.state == game.State.TITLE, "실행 직후 타이틀")
	game.debug_tap(Vector2(270, 480))
	check("M1", game.state == game.State.DAY and game.loop == 1 and game.tick == 0, "탭하면 첫 아침: 1번째 하루, 0틱")
	check("M1", game.place == "inn" and game.walk_left == 0 and game.acting == "", "여관에 서 있다")
	check("M1", game.items.is_empty() and game.flags.is_empty() and game.notes.is_empty(), "빈손, 표지 없음, 빈 수첩")
	check("M1", game.queue.is_empty() and game.choices.is_empty() and not game.solved, "예약·선택지·도장 없음")
	check("M1", npc("bori") == "bakery" and npc("darae") == "inn" and npc("musoe") == "smithy" and npc("sori") == "post",
		"0틱: 보리 빵집, 다래 여관, 무쇠 대장간, 소리 우체국")


func m2_time() -> void:
	start()
	game.debug_step(1.0)
	check("M2", game.tick == 0, "1.0초 뒤 아직 0틱")
	game.debug_step(1.5)
	check("M2", game.tick == 1, "2.5초 뒤 1틱")
	game.debug_press("fast_down")
	check("M2", game.fast, "흘려보내기를 누르는 중")
	game.debug_step(1.0)
	check("M2", game.tick == 4, "흘려보내며 1.0초(쌓인 0.5초 포함)에 3틱 → 4틱")
	game.debug_press("fast_up")
	check("M2", not game.fast, "떼면 원래대로")
	game.debug_step(1.9)
	check("M2", game.tick == 4, "1.9초 뒤 아직 4틱")
	game.debug_step(0.2)
	check("M2", game.tick == 5, "2.1초 뒤 5틱")
	game.debug_press("notebook")
	check("M2", game.state == game.State.NOTEBOOK, "수첩을 열었다")
	game.debug_step(5.0)
	game.debug_tick(3)
	check("M2", game.tick == 5, "수첩이 열려 있으면 시간이 멈춘다")
	game.debug_press("close")
	check("M2", game.state == game.State.DAY and game.tick == 5, "닫으면 하루로")
	until(89)
	check("M2", game.state == game.State.DAY and game.tick == 89, "89틱은 아직 하루")
	game.debug_step(2.5)
	check("M2", game.state == game.State.RESULT and game.tick == 89, "89틱에서 한 틱 더 가면 오늘의 결과")


func m3_walking() -> void:
	start()
	check("M3", game.debug_dist("inn", "smithy") == 5 and game.debug_dist("inn", "dock") == 6, "거리: 여관→대장간 5, 여관→나루터 6")
	check("M3", game.debug_dist("tower", "dock") == 7 and game.debug_dist("post", "tower") == 2 and game.debug_dist("bakery", "inn") == 1,
		"거리: 종탑→나루터 7, 우체국→종탑 2, 빵집→여관 1")
	check("M3", not game.debug_go("inn") and not game.debug_go("nowhere") and game.walk_left == 0, "제자리와 없는 장소는 거절")
	check("M3", game.debug_go("smithy"), "대장간으로 출발")
	check("M3", game.place == "" and game.walk_from == "inn" and game.walk_to == "smithy" and game.walk_left == 5 and game.tick == 0,
		"걷는 중: 어느 장소에도 없다, 5틱 남음")
	game.debug_tick(4)
	check("M3", game.place == "" and game.walk_left == 1 and game.tick == 4, "4틱 뒤 아직 길 위(1틱 남음)")
	game.debug_tick(1)
	check("M3", game.place == "smithy" and game.walk_left == 0 and game.walk_to == "" and game.tick == 5, "5틱에 대장간 도착")
	start()
	game.debug_tap(game.debug_place_pos("bakery") + Vector2(30, 0))
	check("M3", game.walk_to == "bakery" and game.walk_left == 1, "장소 중심에서 30px 옆을 탭해도 간다")
	game.debug_tick(1)
	check("M3", game.place == "bakery" and game.tick == 1, "1틱에 빵집 도착")
	start()
	until(88)
	check("M3", not game.debug_go("plaza") and game.place == "inn", "88틱에 광장(2틱)은 오늘 안에 못 닿아 거절")
	check("M3", game.debug_go("bakery"), "88틱에 빵집(1틱)은 간다")
	game.debug_tick(1)
	check("M3", game.place == "bakery" and game.tick == 89 and game.state == game.State.DAY, "89틱에 도착")


func m4_default_day() -> void:
	start()
	until(6)
	check("M4", npc("darae") == "inn" and game.flags.is_empty(), "6틱: 다래 여관, 표지 없음")
	until(7)
	check("M4", npc("darae") == "bakery", "7틱: 다래가 빵집에")
	until(8)
	check("M4", j(game.flags) == "slip_on_counter", "8틱: 쪽지가 계산대에")
	until(9)
	check("M4", j(game.flags) == "slip_fallen,slip_on_counter" and npc("darae") == "inn", "9틱: 쪽지가 떨어지고 다래는 여관으로")
	until(14)
	check("M4", npc("bori") == "bakery", "14틱: 보리 아직 빵집")
	until(15)
	check("M4", npc("bori") == "", "15틱: 보리가 길 위")
	until(19)
	check("M4", npc("bori") == "" and npc("sori") == "", "19틱: 보리·소리 길 위")
	until(20)
	check("M4", npc("bori") == "smithy" and npc("musoe") == "smithy", "20틱: 보리 대장간")
	until(22)
	check("M4", npc("sori") == "bakery", "22틱: 소리 빵집")
	until(23)
	check("M4", not has(game.flags, "burnt") and game.notes.is_empty(), "23틱: 아직 타지 않았다, 수첩 0개")
	until(24)
	check("M4", j(game.flags) == "burnt,slip_fallen,slip_on_counter" and npc("sori") == "inn", "24틱: 빵이 탄다, 소리 여관")
	check("M4", j(game.notes) == "C_smoke", "24틱: 여관에서 굴뚝 연기를 본다(먼 신호)")
	until(25)
	check("M4", npc("bori") == "", "25틱: 보리 길 위")
	until(28)
	check("M4", npc("musoe") == "" and npc("bori") == "", "28틱: 무쇠 길 위")
	until(29)
	check("M4", npc("bori") == "bakery", "29틱: 보리 빵집으로 돌아옴")
	until(30)
	check("M4", npc("musoe") == "dock" and npc("sori") == "smithy", "30틱: 무쇠 나루터, 소리 대장간")
	until(37)
	check("M4", npc("sori") == "tower", "37틱: 소리 종탑")
	until(40)
	check("M4", npc("sori") == "post", "40틱: 소리 우체국")
	until(49)
	check("M4", j(game.notes) == "C_smoke", "49틱: 수첩 1개")
	until(50)
	check("M4", not has(game.flags, "lunch") and j(game.notes) == "C_smoke,N_nolunch", "50틱: 점심이 없다")
	until(75)
	check("M4", j(game.notes) == "C_smoke,N_nolunch", "75틱: 수첩 2개")
	until(89)
	check("M4", j(game.flags) == "burnt,slip_fallen,slip_on_counter", "89틱: 표지 3개")
	check("M4", j(game.notes) == "C_smoke,N_nolunch,C_evening" and j(game.new_notes) == "C_smoke,N_nolunch,C_evening", "89틱: 수첩 3개")
	check("M4", game.done.is_empty() and game.place == "inn", "아무것도 하지 않았다")


func m5_witness() -> void:
	start()
	game.debug_go("bakery")
	until(7)
	check("M5", game.place == "bakery" and game.notes.is_empty(), "빵집 7틱: 아직 0개")
	until(8)
	check("M5", j(game.notes) == "N_slip", "8틱: 쪽지를 두고 간다")
	until(9)
	check("M5", j(game.notes) == "N_slip,N_slipfall", "9틱: 쪽지가 날아간다")
	until(10)
	check("M5", j(game.notes) == "N_slip,N_slipfall,N_dough", "10틱: 반죽")
	until(11)
	check("M5", j(game.notes) == "N_slip,N_slipfall,N_dough", "11틱: 그대로")
	until(12)
	check("M5", j(game.notes) == "N_slip,N_slipfall,N_dough,N_nowood", "12틱: 장작이 떨어졌네")
	until(23)
	check("M5", game.notes.size() == 4, "23틱: 4개")
	until(24)
	check("M5", j(game.notes) == "N_slip,N_slipfall,N_dough,N_nowood,N_burnt", "24틱: 빵이 탄다")
	check("M5", j(game.new_notes) == j(game.notes), "전부 이 바퀴에 새로 안 것")
	start()
	until(20)
	check("M5", game.notes.is_empty(), "여관 20틱: 0개")
	game.debug_go("smithy")
	game.debug_tick(5)
	check("M5", game.place == "smithy" and game.tick == 25 and has(game.flags, "burnt"), "25틱 대장간 도착(그 사이 빵이 탔다)")
	check("M5", game.notes.is_empty(), "광장을 지나며 본 연기는 적히지 않는다(길 위)")
	start()
	game.debug_go("plaza")
	until(15)
	check("M5", game.place == "plaza" and game.notes.is_empty(), "광장 15틱: 0개")
	until(16)
	check("M5", j(game.notes) == "C_run", "16틱: 보리가 뛰어간다")
	until(19)
	check("M5", j(game.notes) == "C_run,C_sori", "19틱: 소리가 지나간다")
	until(23)
	check("M5", j(game.notes) == "C_run,C_sori", "23틱: 그대로")
	until(24)
	check("M5", j(game.notes) == "C_run,C_sori,C_smoke", "24틱: 광장에서도 연기가 보인다")
	until(33)
	check("M5", j(game.notes) == "C_run,C_sori,C_smoke,C_sori2", "33틱: 소리가 종탑 쪽으로")


func m6_action_timing() -> void:
	start()
	game.debug_go("smithy")
	game.debug_tick(5)
	check("M6", j(game.choices) == "wood_take", "대장간 5틱: 장작 들기 선택지")
	check("M6", not game.debug_do("slip") and game.acting == "", "여기 없는 선택지는 거절")
	game.debug_press("choice:slip")
	check("M6", game.acting == "" and game.queue.is_empty(), "없는 선택지 단추는 아무 일도 없다")
	game.debug_press("choice:wood_take")
	check("M6", game.acting == "wood_take" and game.items.is_empty() and game.tick == 5 and game.done.is_empty(),
		"단추를 누른 틱: 행동 중, 아직 빈손")
	check("M6", not game.debug_do("wood_take") and game.queue.is_empty(), "하고 있는 행동은 다시 예약되지 않는다")
	game.debug_tick(1)
	check("M6", j(game.items) == "wood" and j(game.flags) == "took" and j(game.done) == "wood_take" and game.acting == "",
		"6틱: 장작이 손에")
	check("M6", game.choices.is_empty() and not game.debug_do("wood_take"), "한 번 든 장작은 다시 못 든다")
	game.debug_load(MINI)
	check("M6", game.state == game.State.DAY and game.tick == 0 and game.place == "a" and j(game.choices) == "pick", "장면 mini: 0틱, 장소 a")
	check("M6", game.debug_do("pick"), "줍기 1")
	game.debug_tick(1)
	check("M6", j(game.items) == "stone" and j(game.choices) == "pick", "1틱: 돌 1개")
	check("M6", game.debug_do("pick"), "줍기 2")
	game.debug_tick(1)
	check("M6", j(game.items) == "stone,stone" and game.choices.is_empty(), "2틱: 돌 2개, 더는 선택지가 없다")
	check("M6", not game.debug_do("pick"), "소지품 2개에서 줍기 거절")
	game.debug_go("b")
	game.debug_tick(2)
	check("M6", game.place == "b" and game.tick == 4 and j(game.choices) == "fix", "4틱: 장소 b, 고치기 선택지")
	until(7)
	check("M6", game.debug_do("fix") and game.acting == "fix", "7틱에 고치기 시작(3틱)")
	game.debug_tick(1)
	check("M6", game.flags.is_empty() and j(game.items) == "stone,stone" and game.acting == "fix", "8틱: 아직 하는 중")
	game.debug_tick(1)
	check("M6", game.flags.is_empty() and game.acting == "fix" and game.notes.is_empty(), "9틱: 아직 하는 중")
	game.debug_tick(1)
	check("M6", j(game.flags) == "fixed" and j(game.items) == "stone" and game.acting == "", "10틱: 결과가 세계 사건보다 먼저 — late 가 서지 않는다")
	check("M6", j(game.notes) == "S_ok" and j(game.done) == "pick,pick,fix", "10틱: 고쳐진 장면을 본다")
	game.debug_load(MINI)
	game.debug_do("pick")
	game.debug_tick(1)
	game.debug_go("b")
	until(8)
	check("M6", game.debug_do("fix"), "8틱에 고치기 시작")
	game.debug_tick(1)
	check("M6", game.flags.is_empty(), "9틱: 표지 없음")
	game.debug_tick(1)
	check("M6", j(game.flags) == "late" and j(game.notes) == "S_late" and j(game.items) == "stone", "10틱: 늦었다(아직 고치는 중)")
	game.debug_tick(1)
	check("M6", j(game.flags) == "fixed,late" and game.items.is_empty() and j(game.notes) == "S_late,S_ok", "11틱: 고치기 결과")
	game.debug_load(MINI)
	game.debug_do("pick")
	game.debug_tick(1)
	game.debug_go("b")
	until(10)
	check("M6", game.place == "b" and game.choices.is_empty() and j(game.late_choices) == "fix", "10틱(창은 9틱까지): 선택지 없음, 늦은 선택지 fix")
	check("M6", not game.debug_do("fix") and game.acting == "", "늦은 선택지는 할 수 없다")


func m7_notebook_opens_choices() -> void:
	start()
	fetch_wood(0)
	check("M7", game.place == "bakery" and game.tick == 11 and j(game.items) == "wood", "빈 수첩으로 11틱 빵집, 장작")
	check("M7", j(game.choices) == "wood_give", "빈 수첩: 장작 주기만 보인다")
	check("M7", not game.debug_do("slip") and game.acting == "", "쪽지 줍기는 거절")
	start()
	game.debug_set_notes(["N_slipfall"])
	fetch_wood(0)
	check("M7", j(game.choices) == "wood_give,slip", "쪽지가 떨어지는 걸 본 수첩: 쪽지 줍기가 생긴다")
	start()
	game.debug_go("bakery")
	until(8)
	check("M7", game.choices.is_empty(), "빵집 8틱: 선택지 없음")
	until(9)
	check("M7", j(game.choices) == "slip", "9틱: 떨어지는 걸 본 그 틱부터 쪽지 줍기")
	until(14)
	check("M7", j(game.choices) == "slip", "14틱: 그대로")
	until(15)
	check("M7", game.choices.is_empty() and game.late_choices.is_empty(), "15틱: 보리가 없으면 선택지가 없다")
	until(28)
	check("M7", game.choices.is_empty(), "28틱: 아직 없다")
	until(29)
	check("M7", j(game.choices) == "slip", "29틱: 보리가 돌아오면 다시")


func m8_two_loops_solve() -> void:
	start()
	explore_bakery()
	check("M8", game.tick == 30 and j(game.notes) == j(NOTES1), "1바퀴: 빵집에서 30틱까지, 수첩 5개")
	game.debug_press("sleep")
	check("M8", game.state == game.State.RESULT, "잠들기 → 오늘의 결과")
	check("M8", not game.result_solved and not game.solved and j(game.result_new) == j(NOTES1) and game.result_late.is_empty(),
		"결과: 안 풀림, 새로 안 것 5개")
	game.debug_tap(Vector2(270, 480))
	check("M8", game.state == game.State.DAY and game.loop == 2 and game.tick == 0 and game.place == "inn", "2바퀴째 아침")
	game.debug_go("smithy")
	game.debug_tick(5)
	check("M8", game.place == "smithy" and j(game.choices) == "wood_take", "5틱 대장간")
	check("M8", game.debug_do("wood_take"), "장작 들기")
	game.debug_tick(1)
	check("M8", j(game.items) == "wood" and game.tick == 6, "6틱 장작")
	game.debug_go("bakery")
	game.debug_tick(5)
	check("M8", game.place == "bakery" and game.tick == 11 and j(game.choices) == "wood_give,slip" and npc("bori") == "bakery", "11틱 빵집")
	check("M8", game.debug_do("wood_give"), "장작 주기")
	game.debug_tick(1)
	check("M8", game.items.is_empty() and j(game.flags) == "slip_fallen,slip_on_counter,took,wood" and j(game.choices) == "slip", "12틱: 장작을 줬다")
	check("M8", game.debug_do("slip"), "쪽지 줍기")
	game.debug_tick(1)
	check("M8", j(game.flags) == "order,slip_fallen,slip_on_counter,took,wood" and j(game.done) == "wood_take,wood_give,slip", "13틱: 쪽지를 줬다")
	check("M8", game.choices.is_empty() and not game.debug_do("slip"), "한 일은 다시 뜨지 않는다")
	until(15)
	check("M8", npc("bori") == "bakery", "15틱: 보리가 빵집을 비우지 않는다")
	until(23)
	check("M8", not has(game.flags, "bread"), "23틱: 아직 굽는 중")
	until(24)
	check("M8", has(game.flags, "bread") and not has(game.flags, "burnt"), "24틱: 빵이 구워졌다(타지 않았다)")
	until(27)
	check("M8", npc("bori") == "" and not has(game.flags, "inn_bread"), "27틱: 보리가 여관으로 가는 길")
	until(28)
	check("M8", has(game.flags, "inn_bread") and npc("bori") == "inn", "28틱: 빵이 여관에")
	until(31)
	check("M8", npc("bori") == "bakery", "31틱: 보리 빵집으로")
	until(49)
	check("M8", not has(game.flags, "lunch"), "49틱: 아직")
	until(50)
	check("M8", j(game.flags) == "bread,inn_bread,lunch,order,slip_fallen,slip_on_counter,took,wood", "50틱: 점심이 차려진다")
	check("M8", game.new_notes.is_empty() and j(game.notes) == j(NOTES1), "이 바퀴에 새로 안 것은 없다")
	game.debug_tick(100)
	check("M8", game.state == game.State.RESULT and game.result_solved and game.solved, "하루 끝: 풀림, 도장")
	check("M8", game.result_new.is_empty() and game.result_late.is_empty(), "결과: 새로 안 것 0, 늦은 매듭 0")
	game.debug_tap(Vector2(270, 480))
	check("M8", game.loop == 3 and game.solved and game.flags.is_empty(), "3바퀴째: 도장은 남고 표지는 사라진다")


func m9_missing_or_late() -> void:
	start()
	fetch_wood(0)
	check("M9", game.debug_do("wood_give"), "빈 수첩: 장작만 준다")
	game.debug_tick(1)
	check("M9", game.items.is_empty() and j(game.flags) == "slip_fallen,slip_on_counter,took,wood" and game.choices.is_empty(), "12틱: 줬다, 더 할 일이 없다")
	until(24)
	check("M9", has(game.flags, "bread") and not has(game.flags, "burnt"), "24틱: 빵은 구워진다")
	until(28)
	check("M9", not has(game.flags, "inn_bread") and npc("bori") == "bakery", "28틱: 주문을 모르는 보리는 여관에 가지 않는다")
	until(50)
	check("M9", not has(game.flags, "lunch"), "50틱: 점심 없음")
	game.debug_tick(100)
	check("M9", game.state == game.State.RESULT and not game.result_solved and not game.solved, "결과: 안 풀림")
	check("M9", game.result_new.is_empty() and game.result_late.is_empty(), "빵집에서는 새로 안 것도 늦은 것도 없다")
	start()
	game.debug_set_notes(NOTES1)
	fetch_wood(4)
	check("M9", game.place == "bakery" and game.tick == 15 and npc("bori") == "", "4틱 늦게 출발: 15틱 빵집, 보리는 나갔다")
	check("M9", game.choices.is_empty() and j(game.late_choices) == "wood_give", "선택지 없음, 늦은 선택지 wood_give")
	check("M9", not game.debug_do("wood_give") and j(game.items) == "wood", "줄 수 없다")
	until(24)
	check("M9", has(game.flags, "burnt") and not has(game.flags, "bread"), "24틱: 빵이 탄다")
	until(29)
	check("M9", j(game.choices) == "slip" and j(game.late_choices) == "wood_give", "29틱: 보리가 돌아와도 장작은 늦었다")
	game.debug_tick(100)
	check("M9", game.state == game.State.RESULT and not game.result_solved and j(game.result_late) == "wood_give", "결과: 늦은 매듭 wood_give")
	start()
	game.debug_set_notes(NOTES1)
	fetch_wood(3)
	check("M9", game.tick == 14 and j(game.choices) == "wood_give,slip" and game.late_choices.is_empty(), "3틱 늦게 출발: 14틱 도착은 된다")
	check("M9", game.debug_do("wood_give") and game.debug_do("slip") and j(game.queue) == "slip", "장작 주기 시작, 쪽지는 예약")
	until(16)
	check("M9", j(game.done) == "wood_take,wood_give,slip", "16틱: 둘 다 끝")
	until(50)
	check("M9", has(game.flags, "lunch"), "50틱: 점심")


func m10_reset_keeps_notebook() -> void:
	start()
	explore_bakery()
	game.debug_go("smithy")
	game.debug_tick(5)
	game.debug_do("wood_take")
	game.debug_tick(1)
	game.debug_go("inn")
	game.debug_go("bakery")
	check("M10", game.tick == 36 and j(game.items) == "wood" and game.walk_to == "inn" and j(game.queue) == "bakery", "36틱: 장작을 들고 걷는 중, 예약 1개")
	game.debug_press("sleep")
	check("M10", game.state == game.State.RESULT and j(game.result_new) == j(NOTES1), "걷는 중에도 잠들 수 있다")
	check("M10", not game.debug_go("bakery") and not game.debug_do("wood_take"), "결과 화면에서는 가기·행동이 안 된다")
	game.debug_tick(3)
	game.debug_step(5.0)
	check("M10", game.state == game.State.RESULT and game.tick == 36, "결과 화면에서는 시간이 가지 않는다")
	game.debug_tap(Vector2(270, 480))
	check("M10", game.state == game.State.DAY and game.loop == 2 and game.tick == 0, "탭: 2번째 하루 0틱")
	check("M10", game.place == "inn" and game.walk_left == 0 and game.walk_to == "" and game.acting == "", "여관에 서 있다")
	check("M10", game.items.is_empty() and game.flags.is_empty() and game.queue.is_empty() and game.done.is_empty(), "소지품·표지·예약·한 일이 사라졌다")
	check("M10", j(game.notes) == j(NOTES1) and game.new_notes.is_empty(), "수첩 5개는 남고, 새로 안 것은 0개")
	check("M10", game.debug_expected("darae") == "inn" and game.debug_expected("bori") == "", "0틱: 다래는 여관에서 봤다, 보리는 본 적 없다")
	game.debug_tick(1)
	check("M10", game.debug_expected("bori") == "bakery" and game.debug_expected("musoe") == "", "1틱: 보리는 빵집에서 봤다, 무쇠는 본 적 없다")
	until(7)
	check("M10", game.debug_expected("darae") == "bakery" and npc("darae") == "bakery", "7틱: 다래는 빵집에서 봤다(지금은 여관에 서 있어도)")
	until(15)
	check("M10", game.debug_expected("bori") == "", "15틱: 보리가 떠난 뒤는 본 적 없다")
	until(22)
	check("M10", game.debug_expected("sori") == "bakery", "22틱: 소리는 빵집에서 봤다")


func m11_queue() -> void:
	start()
	check("M11", game.debug_go("plaza") and game.queue.is_empty(), "한가할 때는 바로 출발(예약 아님)")
	check("M11", game.debug_go("post") and game.debug_go("tower") and game.debug_go("smithy"), "걷는 중 예약 3개")
	check("M11", j(game.queue) == "post,tower,smithy", "예약 줄: 우체국, 종탑, 대장간")
	check("M11", not game.debug_go("dock") and game.queue.size() == 3, "네 번째는 거절")
	game.debug_tick(2)
	check("M11", game.tick == 2 and game.place == "" and game.walk_from == "plaza" and game.walk_to == "post" and game.walk_left == 2,
		"2틱: 광장에 닿자마자 우체국으로 출발")
	check("M11", j(game.queue) == "tower,smithy", "예약 2개 남음")
	game.debug_tick(2)
	check("M11", game.tick == 4 and game.walk_from == "post" and game.walk_to == "tower" and j(game.queue) == "smithy", "4틱: 종탑으로")
	game.debug_press("clear")
	check("M11", game.queue.is_empty() and game.walk_to == "tower" and game.walk_left == 2, "예약 지우기: 지금 걸음은 그대로")
	game.debug_tick(2)
	check("M11", game.place == "tower" and game.tick == 6 and game.walk_left == 0, "6틱: 종탑에 서 있다")
	start()
	game.debug_set_notes(NOTES1)
	game.debug_go("smithy")
	check("M11", j(game.choices) == "wood_take", "걷는 중: 도착할 곳(대장간)의 선택지를 예약할 수 있다")
	check("M11", game.debug_do("wood_take") and game.debug_go("bakery"), "장작 들기와 빵집을 예약")
	check("M11", j(game.choices) == "wood_give,slip", "끝 장소가 빵집: 그곳의 선택지(수첩 조건 포함)")
	check("M11", game.debug_do("wood_give") and j(game.queue) == "wood_take,bakery,wood_give", "예약 3개")
	check("M11", not game.debug_do("slip"), "가득 차면 거절")
	game.debug_tick(5)
	check("M11", game.tick == 5 and game.place == "smithy" and game.acting == "wood_take" and j(game.queue) == "bakery,wood_give",
		"5틱: 도착한 틱에 장작 들기 시작")
	check("M11", game.debug_do("slip") and j(game.queue) == "bakery,wood_give,slip", "자리가 나면 쪽지도 예약")
	game.debug_tick(1)
	check("M11", game.tick == 6 and j(game.items) == "wood" and game.walk_to == "bakery" and game.walk_left == 5 and j(game.queue) == "wood_give,slip",
		"6틱: 장작을 들자마자 빵집으로 출발")
	game.debug_tick(5)
	check("M11", game.tick == 11 and game.place == "bakery" and game.acting == "wood_give" and j(game.queue) == "slip", "11틱: 도착한 틱에 장작 주기")
	game.debug_tick(1)
	check("M11", game.acting == "slip" and game.queue.is_empty() and has(game.flags, "wood"), "12틱: 쪽지 줍기 시작")
	game.debug_tick(1)
	check("M11", j(game.done) == "wood_take,wood_give,slip" and has(game.flags, "order") and game.last_missed == "", "13틱: 예약만으로 정답과 같은 틱에 끝")
	until(50)
	check("M11", has(game.flags, "lunch"), "50틱: 점심")
	start()
	game.debug_go("bakery")
	check("M11", j(game.choices) == "wood_give", "빈 수첩으로 빵집에 가는 중: 장작 주기는 예약할 수 있다(소지품은 도착해서 본다)")
	check("M11", game.debug_do("wood_give") and game.debug_go("inn") and j(game.queue) == "wood_give,inn", "장작 주기와 여관을 예약")
	check("M11", not game.debug_go("inn"), "끝 장소와 같은 곳은 예약되지 않는다")
	game.debug_tick(1)
	check("M11", game.tick == 1 and game.last_missed == "wood_give" and game.acting == "" and game.done.is_empty(), "1틱: 장작이 없어 예약이 버려진다")
	check("M11", game.place == "" and game.walk_from == "bakery" and game.walk_to == "inn" and game.walk_left == 1 and game.queue.is_empty(),
		"뒤의 예약(여관)은 같은 틱에 출발")


func m12_timetable() -> void:
	start()
	explore_bakery()
	game.debug_press("notebook")
	check("M12", game.state == game.State.NOTEBOOK, "수첩 화면")
	var rows: Array = game.debug_timetable()
	check("M12", rows.size() == 4 and rows[0]["who"] == "bori" and rows[1]["who"] == "darae" and rows[2]["who"] == "musoe" and rows[3]["who"] == "sori",
		"주민 4명의 줄: 보리, 다래, 무쇠, 소리")
	var bori: Array = rows[0]["entries"]
	var ids: Array = []
	var times: Array = []
	for e in bori:
		ids.append(e["note"])
		times.append(int(e["t0"]))
	check("M12", j(ids) == "N_slipfall,N_dough,N_nowood,N_burnt" and j(times) == "9,10,12,24", "보리 줄: 본 장면 4개가 시각 순으로")
	var darae: Array = rows[1]["entries"]
	check("M12", darae.size() == 1 and darae[0]["note"] == "N_slip" and int(darae[0]["t0"]) == 8 and str(darae[0]["text"]).length() > 0, "다래 줄: 8틱 쪽지")
	check("M12", (rows[2]["entries"] as Array).is_empty() and (rows[3]["entries"] as Array).is_empty(), "무쇠·소리 줄은 비어 있다")
	game.debug_press("close")
	check("M12", game.state == game.State.DAY and game.tick == 30, "닫으면 하루로, 30틱 그대로")
	game.debug_reset()
	check("M12", game.state == game.State.TITLE and game.loop == 0, "debug_reset: 타이틀")
	game.debug_tap(Vector2(270, 480))
	game.debug_press("notebook")
	var empty: Array = game.debug_timetable()
	check("M12", empty.size() == 4 and (empty[0]["entries"] as Array).is_empty() and game.notes.is_empty(), "처음부터 다시 하면 수첩이 비어 있다")
