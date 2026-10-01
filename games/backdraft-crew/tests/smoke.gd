extends SceneTree
## 불길 속으로 — 첫 빌드 검사 (기획실 작성, 기획 v1)
## design/spec.json 의 must_work M1~M12 를 design/FIRST_BUILD.md "테스트 인터페이스"만 써서 확인한다.
## 기대값은 design/first_build_replay.py (기준 구현 design/sim/sim.py)로 계산했다. 장면(SCENES)도 그 스크립트가 만든 것이다.
## 빌드실은 이 파일을 바꾸지 않는다. 틀렸다고 판단되면 반송한다.
## 실행: python tools/smoke.py games/backdraft-crew

# 정답 순서(first_build_replay.py 2번): 건물 A doorman, B rusher, C doorman
const GOLD_A := "U U U L L L CU D P U R R D D D U U U U U U U L L L U U L L P R R D D R R D D D D D D D"
const GOLD_B := "U L L L U L P R X SD P D R R D SU U U R R R U U U P D X SD P D X SD P D L L D D U L L U U U U U U L L P R R D D D D D D R R D"
const GOLD_C := "U U U U U U R U U D U U U R R R D D D D U D CU R SD SL P L L X SD P D L L CR D D D D D D U U U U U U U U U U R R R D P U L L L D D D D D D D D D D U U U U U U U U U U L L L L P R R R D D D D D D D D D D"

# 규칙 장면. 형식은 FIRST_BUILD.md "건물 데이터 형식". 뼈대: 세로 복도(x=5, 방 0) + 오른쪽 3×3 방(x 7~9, y 4~6, 방 1), 문 (6,5)
const SCENES := {
	"heat": '{"name":"scene","title":"","water":8,"floor":["###########","#####.#####","#####.#####","#####.#####","#####.#...#","#####.+...#","#####.#...#","#####.#####","#####.#####","#####.#####","#####.#####","#####.#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","     f     ","           ","           ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[]}',
	"stand": '{"name":"scene","title":"","water":8,"floor":["###########","#####.#####","#####.#####","#####.#####","#####.#...#","#####.+...#","#####.#...#","#####.#####","#####.#####","#####.#####","#####.#####","#####.#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","     f     ","           ","           ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":49}',
	"ash": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_/...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","       f   ","           ","           ","           ","           ","           ","           ","           "],"heat":{"63":1},"fuel":{"62":2},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[]}',
	"seal": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","        f  ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[]}',
	"revive": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","       ooo ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":0,"gas":2,"smolder":true,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":60}',
	"reclose": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","       ooo ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":0,"gas":2,"smolder":true,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":60}',
	"backdraft": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","       ooo ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":0,"gas":5,"smolder":true,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":60}',
	"dodge": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","       ooo ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":0,"gas":5,"smolder":true,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":60}',
	"bd_close": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","       ooo ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":0,"gas":5,"smolder":true,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":60}',
	"water": '{"name":"scene","title":"","water":2,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","     f     ","     f     ","     f     ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{"38":9,"49":9,"60":9},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":71}',
	"carry": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","           ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[[104,12]],"start":115,"air":100}',
	"firewalk": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####.#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","           ","           ","           ","     f     ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[[71,12]],"start":71}',
	"smoke": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####.#####","#####_#####","#####_#...#","#####_/...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","     f     ","           ","           ","           ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[[63,12]]}',
	"smoke_cut": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####.#####","#####_#####","#####_#...#","#####_/...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","     f     ","           ","           ","           ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[[63,12]],"start":60}',
	"burn": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_/...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","       f   ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[[63,3]]}',
	"doorburn": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####.+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","     f     ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{"61":2},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":82}',
	"collapse": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_/...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","         f ","           ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":2,"collapsed":false}],"victims":[[75,12]],"start":62}',
	"air": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####_#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","           ","           ","           ","           ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":38,"air":2}',
	"death": '{"name":"scene","title":"","water":8,"floor":["###########","#####_#####","#####_#####","#####_#####","#####_#...#","#####_+...#","#####_#...#","#####_#####","#####.#####","#####_#####","#####_#####","#####_#####","#####E#####"],"room":["           ","     0     ","     0     ","     0     ","     0 111 ","     0 111 ","     0 111 ","     0     ","     0     ","     0     ","     0     ","     0     ","           "],"state":["           ","           ","           ","           ","           ","           ","           ","           ","     f     ","           ","           ","           ","           "],"heat":{},"fuel":{},"doors":{},"rooms":[{"air":11,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false},{"air":9,"gas":0,"smolder":false,"front":-1,"hp":30,"collapsed":false}],"victims":[],"start":82,"hp":1}',
}

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
	m1_title_starts_first_building()
	m11_golden_replay()
	m2_legal_actions_and_input()
	m3_beat()
	m4_heat_ignite_forecast()
	m5_sealed_room_smolders()
	m6_revive_and_reclose()
	m7_backdraft()
	m8_water()
	m9_carry_and_rescue()
	m10_breath_and_smoke()
	m12_door_burn_collapse_air_death()


# ---------------------------------------------------------------- 도우미

func check(id: String, ok: bool, label: String) -> void:
	print("[%s] %s %s" % [id, "ok  " if ok else "FAIL", label])
	if not ok:
		failures.append("%s %s" % [id, label])


func V(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


func scene(key: String) -> void:
	game.debug_load(SCENES[key])


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


func fire(x: int, y: int) -> int:
	return game.debug_cell(V(x, y))["fire"]


func heat(x: int, y: int) -> int:
	return game.debug_cell(V(x, y))["heat"]


func fuel(x: int, y: int) -> int:
	return game.debug_cell(V(x, y))["fuel"]


func room(id: int) -> Dictionary:
	return game.debug_room(id)


func door(x: int, y: int) -> Dictionary:
	return game.debug_door(V(x, y))


func vic(i: int) -> Dictionary:
	return game.victims[i]


func breaths() -> Array:
	var out: Array = []
	for v in game.victims:
		out.append(v["breath"])
	return out


# ---------------------------------------------------------------- 검사

func m1_title_starts_first_building() -> void:
	check("M1", game.state == game.State.TITLE, "실행 직후 타이틀")
	game.debug_tap(Vector2(270, 480))
	check("M1", game.state == game.State.PLAY and game.building_index == 0 and game.building_count == 3, "탭하면 출동: 건물 1/3")
	check("M1", game.clock == 0 and game.beat == 0 and game.pos == V(5, 12), "행동 0, 박자 0, 출구 칸 (5,12)")
	check("M1", game.hp == 4 and game.air == 140 and game.water == 8 and not game.carrying and game.saved == 0, "체력 4, 공기 140, 물 8")
	check("M1", game.victims.size() == 2 and vic(0)["pos"] == V(3, 10) and vic(1)["pos"] == V(1, 3), "사람 2명: (3,10), (1,3)")
	check("M1", vic(0)["breath"] == 12 and vic(0)["state"] == "in" and vic(1)["breath"] == 12 and vic(1)["state"] == "in", "둘 다 숨 12, 안에 있음")
	check("M1", fire(7, 1) == 2 and fire(9, 3) == 2 and fire(7, 4) == 0, "오른쪽 위 방의 윗줄 셋이 숨죽은 불")
	check("M1", room(3)["smolder"] and room(3)["gas"] == 4 and room(3)["air"] == 0 and room(3)["hp"] == 25 and room(3)["sealed"], "방 3: 숨죽음, 가스 4, 공기 0, 버팀 25, 밀폐")
	check("M1", not door(6, 2)["open"] and door(6, 2)["sign"] == "smolder" and door(6, 2)["hp"] == 10, "문 (6,2): 닫힘, 징후 smolder")
	check("M1", door(3, 8)["open"] and door(3, 8)["sign"] == "none" and not door(4, 5)["open"] and door(4, 5)["sign"] == "none", "문 (3,8)은 열려 있고, 불 없는 방의 문 (4,5)는 징후 없음")
	check("M1", game.debug_cell(V(0, 9))["kind"] == "V" and game.debug_cell(V(5, 12))["kind"] == "E" and game.debug_cell(V(6, 2))["kind"] == "D", "깨진 창 (0,9), 출구 (5,12), 문 (6,2)")
	check("M1", not room(2)["sealed"] and room(0)["full"] == 11 and room(1)["full"] == 21, "깨진 창이 있는 방 2는 밀폐 아님. 복도 11칸, 방 1은 21칸")
	check("M1", game.last_action == "" and game.mode == "" and game.forecast.is_empty(), "시작: 마지막 행동 없음, 방향 대기 없음, 예보 없음")


func m11_golden_replay() -> void:
	# M1 직후: 건물 A, 행동 0
	check("M11", acts(GOLD_A), "건물 A 정답 43입력이 모두 가능한 행동")
	check("M11", game.state == game.State.PLAY and game.clock == 62 and game.beat == 31 and game.pos == V(5, 12), "A: 62행동, 31박자, 출구 칸")
	check("M11", game.hp == 4 and game.water == 8 and game.saved == 2 and game.air == 140, "A: 체력 4, 물 8, 2명 구조, 공기 140")
	check("M11", vic(0)["state"] == "saved" and vic(1)["state"] == "saved" and breaths() == [12, 12], "A: 둘 다 구조됨, 숨 12·12")
	check("M11", not door(3, 8)["open"], "A: 문 (3,8)을 닫았다")
	check("M11", game.debug_act("Q") and game.state == game.State.RESULT, "출구에서 철수 → 결과")
	check("M11", game.result_stars == 3 and game.result_cause == "retreat", "전원 구조 ★★★, 철수")
	check("M11", not game.debug_act("W"), "결과 화면에서는 행동 불가")
	game.debug_tap(Vector2(270, 480))
	check("M11", game.state == game.State.PLAY and game.building_index == 1 and game.clock == 0 and game.beat == 0, "탭 → 건물 2, 행동 0")
	check("M11", game.hp == 4 and game.air == 140 and game.water == 9 and game.saved == 0 and game.victims.size() == 3, "B: 체력 4, 물 9, 사람 3명")
	check("M11", vic(0)["pos"] == V(7, 7) and vic(1)["pos"] == V(1, 5) and vic(2)["pos"] == V(2, 10), "B: 사람 (7,7), (1,5), (2,10)")
	check("M11", door(4, 11)["sign"] == "backdraft" and room(2)["gas"] == 8 and room(4)["gas"] == 9, "B: 문 (4,11) 징후 backdraft, 방 2 가스 8, 방 4 가스 9")
	check("M11", acts(GOLD_B), "건물 B 정답 61입력이 모두 가능한 행동")
	check("M11", game.state == game.State.PLAY and game.clock == 84 and game.beat == 42 and game.pos == V(5, 12), "B: 84행동, 42박자, 출구 칸")
	check("M11", game.hp == 2 and game.water == 5 and game.saved == 3, "B: 체력 2, 물 5, 3명 구조")
	check("M11", breaths() == [8, 8, 7], "B: 구조된 사람의 숨 8·8·7")
	check("M11", game.debug_act("Q") and game.result_stars == 3, "B: 철수 ★★★")
	game.debug_tap(Vector2(270, 480))
	check("M11", game.state == game.State.PLAY and game.building_index == 2 and game.water == 10 and game.hp == 4, "탭 → 건물 3, 물 10, 체력 4(이어지지 않음)")
	check("M11", vic(0)["pos"] == V(9, 5) and vic(1)["pos"] == V(2, 2) and vic(2)["pos"] == V(8, 3) and door(6, 2)["open"], "C: 사람 (9,5), (2,2), (8,3). 문 (6,2)는 열려 있음")
	check("M11", acts(GOLD_C), "건물 C 정답 99입력이 모두 가능한 행동")
	check("M11", game.state == game.State.PLAY and game.clock == 137 and game.beat == 68 and game.pos == V(5, 12), "C: 137행동, 68박자, 출구 칸")
	check("M11", game.hp == 4 and game.water == 7 and game.saved == 3 and breaths() == [7, 12, 6], "C: 체력 4, 물 7, 3명 구조, 숨 7·12·6")
	check("M11", game.debug_act("Q") and game.result_stars == 3 and game.result_cause == "retreat", "C: 철수 ★★★")
	game.debug_tap(Vector2(270, 480))
	check("M11", game.state == game.State.TITLE, "마지막 건물의 결과에서 탭 → 타이틀")


func m2_legal_actions_and_input() -> void:
	scene("carry")   # 타일 복도, (5,10)에서 시작, 사람 (5,9), 공기 100
	check("M2", game.state == game.State.PLAY and game.building_count == 1 and game.pos == V(5, 10) and game.air == 100 and game.clock == 0, "debug_load: 장면에서 바로 출동(시작 칸·공기는 장면 값)")
	check("M2", not game.debug_act("R") and not game.debug_act("L"), "벽으로 걷기 거절")
	check("M2", not game.debug_act("X") and not game.debug_act("P"), "업지 않은 내려놓기, 사람 없는 칸의 업기 거절")
	check("M2", not game.debug_act("Q") and not game.debug_act("CU") and not game.debug_act("SR"), "출구가 아닌 철수, 문이 없는 쪽 닫기, 벽 쪽 물 거절")
	check("M2", game.clock == 0 and game.last_action == "" and game.water == 8, "거절된 행동은 행동 수도 물도 쓰지 않는다")
	check("M2", game.debug_act("D") and game.debug_act("D") and game.pos == V(5, 12) and game.clock == 2, "아래로 두 칸 → 출구 칸")
	check("M2", not game.debug_act("D") and game.clock == 2, "보드 밖으로 걷기 거절")
	check("M2", not game.debug_act("X"), "출구 칸에는 내려놓을 수 없다(업지도 않았다)")
	scene("revive")  # (5,5)에서 시작, 오른쪽에 닫힌 문 (6,5)
	check("M2", game.debug_act("R") and game.pos == V(5, 5) and door(6, 5)["open"] and game.clock == 1 and game.last_action == "R", "닫힌 문 쪽 걷기 = 문 열기(자리 그대로, 1행동)")
	check("M2", game.debug_act("CR") and not door(6, 5)["open"] and game.clock == 2 and game.last_action == "CR", "문 닫기")
	check("M2", not game.debug_act("CR") and game.clock == 2, "닫힌 문은 다시 닫을 수 없다")
	# 실제 입력 경로
	scene("revive")
	game.debug_swipe(Vector2(270, 300), Vector2(280, 300))
	check("M2", game.clock == 0 and game.pos == V(5, 5), "24px 미만으로 밀면 아무 일도 없음")
	game.debug_swipe(Vector2(270, 300), Vector2(310, 304))
	check("M2", game.last_action == "R" and door(6, 5)["open"] and game.clock == 1 and game.pos == V(5, 5), "오른쪽으로 밀기 = 오른쪽 걷기(문 열기)")
	game.debug_press("close")
	check("M2", game.last_action == "CR" and not door(6, 5)["open"] and game.clock == 2 and game.mode == "", "문 닫기 버튼: 닫을 문이 하나면 즉시 닫는다")
	game.debug_press("close")
	check("M2", game.clock == 2 and game.mode == "", "닫을 문이 없으면 아무 일도 없다")
	game.debug_press("water")
	check("M2", game.mode == "water" and game.clock == 2, "물 버튼 → 방향 대기")
	game.debug_press("water")
	check("M2", game.mode == "", "다시 누르면 취소")
	game.debug_press("water")
	game.debug_swipe(Vector2(270, 300), Vector2(268, 250))
	check("M2", game.last_action == "SU" and game.water == 7 and game.clock == 3 and game.mode == "" and game.pos == V(5, 5), "물 버튼 뒤 위로 밀기 = 위로 물(제자리), 대기 풀림")
	game.debug_swipe(Vector2(270, 300), Vector2(270, 250))
	check("M2", game.last_action == "U" and game.pos == V(5, 4) and game.clock == 4, "대기가 풀렸으니 위로 밀면 걷기")
	game.debug_press("wait")
	check("M2", game.last_action == "W" and game.clock == 5 and game.pos == V(5, 4), "기다리기 버튼")
	game.debug_press("retreat")
	check("M2", game.state == game.State.PLAY and game.clock == 5, "출구가 아니면 철수 버튼은 아무 일도 없다")


func m3_beat() -> void:
	scene("heat")
	check("M3", game.clock == 0 and game.beat == 0, "시작: 행동 0, 박자 0")
	waits(1)
	check("M3", game.clock == 1 and game.beat == 0 and heat(5, 4) == 0, "행동 1번: 불은 아직 움직이지 않음")
	waits(1)
	check("M3", game.clock == 2 and game.beat == 1 and heat(5, 4) == 1, "행동 2번: 불 1박자")
	waits(6)
	check("M3", game.clock == 8 and game.beat == 4, "행동 8번: 4박자")
	scene("carry")
	acts("U P")
	check("M3", game.clock == 2 and game.beat == 1 and game.carrying, "한 칸 걷고 업기: 2행동")
	acts("D")
	check("M3", game.clock == 4 and game.beat == 2 and game.pos == V(5, 10), "업고 한 칸 = 2행동(불 1박자)")
	scene("heat")
	waits(599)
	check("M3", game.state == game.State.PLAY and game.clock == 599, "599행동까지 진행 중")
	waits(1)
	check("M3", game.state == game.State.RESULT and game.result_cause == "limit" and game.clock == 600 and game.beat == 300, "600행동이면 끝(limit)")
	check("M3", game.hp == 4 and game.result_stars == 0, "출구 칸에서 기다렸으니 체력 4, 구한 사람이 없어 ★ 0")


func m4_heat_ignite_forecast() -> void:
	scene("heat")    # 나무 복도 (5,3)에 불
	check("M4", fire(5, 3) == 1 and fuel(5, 3) == 12 and game.forecast.is_empty(), "시작: (5,3) 불, 탈 것 12, 예보 없음")
	waits(2)
	check("M4", heat(5, 2) == 1 and heat(5, 4) == 1 and heat(5, 5) == 0 and fuel(5, 3) == 11, "1박자: 옆 칸 열 1, 불 칸 탈 것 11")
	waits(2)
	check("M4", heat(5, 2) == 2 and heat(5, 4) == 2 and fire(5, 4) == 0, "2박자: 열 2, 아직 안 붙음")
	check("M4", game.forecast == [V(5, 2), V(5, 4)], "예보: 다음 박자에 (5,2)와 (5,4)가 붙는다")
	waits(2)
	check("M4", fire(5, 2) == 1 and fire(5, 4) == 1 and fuel(5, 3) == 9, "3박자: 나무(T 3)는 3박자 뒤에 붙는다")
	waits(2)
	check("M4", heat(5, 5) == 1 and fuel(5, 4) == 11, "4박자: 새로 붙은 칸이 다음 칸을 데우기 시작")
	scene("stand")   # 같은 불, 소방관이 (5,4)에 서 있다
	waits(4)
	check("M4", game.forecast == [V(5, 2)], "예보에 내가 선 칸은 없다")
	waits(4)
	check("M4", fire(5, 4) == 0 and heat(5, 4) == 3 and game.hp == 4 and game.beat == 4, "소방관이 선 칸은 열 3에서 붙지 않고 머문다. 불 옆에 서 있는 것만으로는 다치지 않음")
	acts("D")
	check("M4", game.pos == V(5, 5) and fire(5, 4) == 0 and game.forecast == [V(5, 4)], "비키면 다음 박자에 붙는다고 예보")
	waits(1)
	check("M4", fire(5, 4) == 1 and game.beat == 5, "다음 박자에 붙음")
	scene("ash")     # 타일 복도, 열린 문, 방 안 (7,5) 불 탈 것 2
	waits(2)
	check("M4", fire(7, 5) == 1 and fuel(7, 5) == 1 and heat(7, 4) == 1 and heat(8, 5) == 2, "1박자: 탈 것 1")
	waits(2)
	check("M4", fire(7, 5) == 0 and game.debug_cell(V(7, 5))["ash"] and fuel(7, 5) == 0, "2박자: 탈 것이 다해 재가 됨")
	check("M4", fire(8, 5) == 1 and heat(7, 4) == 2, "그 박자에 열 3이 된 (8,5)는 붙고, (7,4)는 열 2")
	waits(2)
	check("M4", heat(7, 4) == 1, "열이 끊긴 칸은 박자마다 1씩 식는다")
	waits(2)
	check("M4", heat(7, 4) == 0 and fire(7, 5) == 0 and game.debug_cell(V(7, 5))["ash"], "0까지 식고, 재는 다시 타지 않는다")
	check("M4", heat(5, 5) == 0 and fire(5, 5) == 0, "타일 복도는 타지 않는다")


func m5_sealed_room_smolders() -> void:
	scene("seal")    # 문 닫힌 9칸 방, (8,5) 불
	check("M5", room(1)["sealed"] and room(1)["air"] == 9 and room(1)["full"] == 9 and door(6, 5)["sign"] == "burning", "밀폐, 공기 9/9, 문 징후 burning")
	waits(2)
	check("M5", room(1)["air"] == 8 and room(1)["hp"] == 29, "1박자: 불 한 칸이 공기 1을 씀. 방 버팀 29")
	waits(4)
	check("M5", room(1)["air"] == 6 and fire(7, 5) == 1 and door(6, 5)["hp"] == 10, "3박자: 공기 6, 옆 칸 넷이 붙음")
	waits(2)
	check("M5", room(1)["air"] == 1 and door(6, 5)["hp"] == 9 and not room(1)["smolder"], "4박자: 불 다섯 칸이 공기 5를 써서 1. 문 버팀 9")
	waits(2)
	check("M5", room(1)["air"] == 0 and room(1)["smolder"] and fire(8, 5) == 2 and fire(7, 5) == 2, "5박자: 공기 0 → 숨죽음, 불이 전부 불씨로")
	check("M5", door(6, 5)["sign"] == "smolder" and room(1)["gas"] == 0 and room(1)["hp"] == 26, "문 징후 smolder, 가스 0, 방 버팀 26")
	waits(2)
	check("M5", room(1)["gas"] == 1 and fuel(8, 5) == 8 and room(1)["hp"] == 26 and door(6, 5)["hp"] == 9, "6박자: 가스 1. 숨죽은 불은 타지 않고(탈 것 그대로) 방도 문도 깎지 않는다")
	waits(6)
	check("M5", room(1)["gas"] == 4 and door(6, 5)["sign"] == "smolder", "9박자: 가스 4, 아직 smolder")
	waits(2)
	check("M5", room(1)["gas"] == 5 and door(6, 5)["sign"] == "backdraft", "10박자: 가스 5 → 문 징후 backdraft")
	check("M5", room(1)["smoke"] and not room(0)["smoke"], "숨죽은 방은 연기 속, 문이 닫혀 복도는 연기 없음")


func m6_revive_and_reclose() -> void:
	scene("revive")  # 숨죽은 방(가스 2), 불씨 (7,5)(8,5)(9,5). 소방관 (5,5)
	check("M6", door(6, 5)["sign"] == "smolder" and room(1)["gas"] == 2 and fire(7, 5) == 2, "시작: 가스 2, 불씨 셋")
	acts("R")
	check("M6", door(6, 5)["open"] and not room(1)["sealed"] and fire(7, 5) == 2 and room(1)["front"] == -1, "문을 연 직후: 아직 그대로")
	waits(1)
	check("M6", game.beat == 1 and room(1)["front"] == 0 and room(1)["air"] == 2 and fire(7, 5) == 2 and room(1)["smolder"], "흡입 박자: 공기 +2, 아무것도 되살아나지 않음")
	waits(2)
	check("M6", fire(7, 5) == 1 and fire(8, 5) == 2 and fire(9, 5) == 2, "그 다음 박자: 문 안쪽 1칸만 되살아남")
	check("M6", room(1)["front"] == 1 and room(1)["gas"] == 0 and not room(1)["smolder"] and room(1)["air"] == 4, "front 1, 가스 0, 숨죽음 풀림, 공기 4")
	waits(2)
	check("M6", fire(8, 5) == 1 and fire(9, 5) == 2 and room(1)["front"] == 2, "한 박자에 한 칸씩: 2칸째")
	waits(2)
	check("M6", fire(9, 5) == 1 and room(1)["front"] == 3 and fuel(7, 5) == 9, "3칸째. 먼저 되살아난 칸은 그만큼 더 탔다")
	scene("revive")
	acts("R W W W")
	check("M6", fire(7, 5) == 1 and fire(8, 5) == 2 and game.clock == 4, "1칸 되살아난 뒤")
	acts("CR")
	check("M6", not door(6, 5)["open"] and room(1)["sealed"] and game.clock == 5, "다시 닫음")
	waits(1)
	check("M6", fire(8, 5) == 2 and fire(9, 5) == 2 and room(1)["front"] == -1 and room(1)["air"] == 3, "닫으면 거기서 멈춘다. 되살아난 불이 공기를 다시 쓴다(4 → 3)")
	check("M6", door(6, 5)["hp"] == 9 and door(6, 5)["sign"] == "burning", "문 옆의 불이 문을 깎는다(9). 징후 burning")
	waits(2)
	check("M6", fire(8, 5) == 2 and room(1)["air"] == 2 and door(6, 5)["hp"] == 8, "다음 박자: 공기 2, 문 8, 불씨는 그대로")


func m7_backdraft() -> void:
	scene("backdraft")   # 가스 5, 소방관 (5,5), 문 (6,5)
	check("M7", door(6, 5)["sign"] == "backdraft" and room(1)["gas"] == 5, "시작: 징후 backdraft")
	acts("R W")
	check("M7", game.beat == 1 and game.hp == 4 and room(1)["gas"] == 5 and room(1)["front"] == 0, "흡입 박자: 아직 폭발 전")
	acts("W W")
	check("M7", game.beat == 2 and game.hp == 2, "다음 박자에 역류: 문 앞 (5,5)에 서 있으면 체력 −2")
	check("M7", fire(7, 5) == 1 and fire(8, 5) == 1 and fire(9, 5) == 2, "문 안쪽 2칸까지 한꺼번에 되살아남, 3칸째는 불씨")
	check("M7", room(1)["gas"] == 0 and room(1)["front"] == 2 and not room(1)["smolder"], "가스 0, front 2")
	check("M7", fire(5, 5) == 0, "타일 칸은 화염이 지나가도 붙지 않는다")
	scene("dodge")
	acts("R U W W")
	check("M7", game.beat == 2 and game.pos == V(5, 4) and game.hp == 4 and fire(7, 5) == 1 and room(1)["gas"] == 0, "열고 한 칸 비켜서면 맞지 않는다(폭발은 일어남)")
	scene("bd_close")
	acts("R CR")
	check("M7", game.beat == 1 and not door(6, 5)["open"] and room(1)["gas"] == 6 and game.hp == 4, "흡입 박자 안에 다시 닫으면 폭발하지 않는다. 가스는 계속 참(6)")
	waits(4)
	check("M7", game.beat == 3 and room(1)["gas"] == 8 and fire(7, 5) == 2 and game.hp == 4 and door(6, 5)["sign"] == "backdraft", "닫아 둔 채로 가스 8, 불씨 그대로")


func m8_water() -> void:
	scene("water")   # (5,6)에서 시작, (5,5)(5,4)(5,3) 불, 물 2
	check("M8", fire(5, 5) == 1 and fire(5, 4) == 1 and fire(5, 3) == 1 and game.water == 2, "시작: 불 세 칸, 물 2")
	check("M8", game.debug_act("SU") and game.water == 1 and game.clock == 1 and game.pos == V(5, 6), "위로 물: 물 1, 1행동, 제자리")
	check("M8", fire(5, 5) == 0 and fire(5, 4) == 0 and fire(5, 3) == 0, "3칸의 불이 꺼짐")
	check("M8", heat(5, 5) == -2 and heat(5, 4) == -2 and heat(5, 3) == -2 and fuel(5, 5) == 9, "맞은 칸 열 −2(젖음), 탈 것은 남는다")
	waits(1)
	check("M8", game.beat == 1 and heat(5, 5) == -1, "1박자 뒤 −1")
	waits(2)
	check("M8", game.beat == 2 and heat(5, 5) == 0 and heat(5, 3) == 0, "2박자 뒤 0(마름)")
	waits(1)
	check("M8", not game.debug_act("SR") and game.water == 1 and game.clock == 5, "벽 쪽으로는 뿌릴 수 없다(물을 쓰지 않음)")
	check("M8", game.debug_act("SU") and game.water == 0 and game.beat == 3 and heat(5, 5) == -1, "마지막 물. 이 행동에 박자가 지나 젖음이 −2에서 −1로")
	check("M8", not game.debug_act("SU") and game.clock == 6, "물 0이면 거절")


func m9_carry_and_rescue() -> void:
	scene("carry")   # 사람 (5,9) 숨 12, 소방관 (5,10), 공기 100
	acts("U")
	check("M9", game.pos == V(5, 9) and not game.carrying and vic(0)["state"] == "in", "사람이 있는 칸으로 걸어 들어갈 수 있다")
	check("M9", game.debug_act("P") and game.carrying and vic(0)["state"] == "carried" and game.clock == 2, "업기(1행동)")
	check("M9", not game.debug_act("SU") and not game.debug_act("P") and game.water == 8, "업은 동안에는 물을 못 뿌리고, 또 업을 수도 없다")
	check("M9", game.debug_act("X") and not game.carrying and vic(0)["state"] == "in" and vic(0)["pos"] == V(5, 9), "내려놓기")
	check("M9", game.debug_act("SU") and game.water == 7, "내려놓으면 뿌릴 수 있다")
	acts("P D")
	check("M9", game.pos == V(5, 10) and game.clock == 7 and vic(0)["pos"] == V(5, 10) and game.air == 93, "다시 업고 한 칸(2행동). 업힌 사람의 칸 = 내 칸. 공기 93")
	acts("D D")
	check("M9", game.pos == V(5, 12) and game.clock == 11, "출구 칸 도착")
	check("M9", vic(0)["state"] == "saved" and game.saved == 1 and not game.carrying and game.air == 140, "구조 완료, 공기가 다시 140")
	check("M9", game.debug_act("Q") and game.result_stars == 3 and game.result_cause == "retreat", "1/1 구조 후 철수 → ★★★")
	scene("firewalk")    # 사람과 같은 칸 (5,6)에서 시작, 가는 길 (5,8)에 불
	acts("P D")
	check("M9", game.pos == V(5, 7) and game.hp == 4 and game.clock == 3, "불 앞 칸까지")
	acts("D")
	check("M9", game.pos == V(5, 8) and game.hp == 2 and vic(0)["breath"] == 8 and game.clock == 5, "불 칸을 업고 밟음(2행동 동안 그 칸): 체력 −2, 업힌 사람 숨 −4")
	acts("D D D D")
	check("M9", game.pos == V(5, 12) and game.hp == 2 and vic(0)["state"] == "saved" and vic(0)["breath"] == 8 and game.clock == 13, "빠져나와 구조. 불 칸을 벗어나면 더 다치지 않는다")


func m10_breath_and_smoke() -> void:
	scene("smoke")   # 방 (8,5)의 사람, 문 열림, 복도 (5,2)에 불(멀다)
	check("M10", room(1)["smoke"] and room(0)["smoke"] and vic(0)["breath"] == 12, "열린 문으로 이어져 방도 연기 속")
	waits(8)
	check("M10", game.beat == 4 and vic(0)["breath"] == 12, "4박자까지 숨 12")
	waits(2)
	check("M10", game.beat == 5 and vic(0)["breath"] == 11, "5박자째 연기로 −1")
	waits(8)
	check("M10", game.beat == 9 and vic(0)["breath"] == 11, "9박자까지 11")
	waits(2)
	check("M10", game.beat == 10 and vic(0)["breath"] == 10, "10박자째 −1")
	scene("smoke_cut")   # 같은 장면, 소방관이 문 옆 (5,5)
	acts("CR")
	check("M10", not door(6, 5)["open"] and room(1)["sealed"] and not room(1)["smoke"] and room(0)["smoke"], "문을 닫으면 방은 연기에서 끊긴다")
	waits(21)
	check("M10", game.beat == 11 and vic(0)["breath"] == 12 and vic(0)["state"] == "in", "11박자가 지나도 숨 12")
	scene("burn")    # 방 (8,5) 사람 숨 3, 옆 칸 (7,5)에 불
	waits(2)
	check("M10", vic(0)["breath"] == 2 and fire(8, 5) == 0, "옆 칸의 불: 박자마다 −1")
	waits(2)
	check("M10", vic(0)["breath"] == 1 and vic(0)["state"] == "in", "숨 1")
	waits(2)
	check("M10", fire(8, 5) == 1 and vic(0)["state"] == "dead" and vic(0)["breath"] == 0, "자기 칸에 불이 붙은 박자: −2 → 사망(숨은 0으로 표시)")


func m12_door_burn_collapse_air_death() -> void:
	scene("doorburn")    # 닫힌 문 (6,5) 버팀 2, 복도 (5,5)에 불. 소방관 (5,7)
	waits(2)
	check("M12", door(6, 5)["hp"] == 1 and not door(6, 5)["open"] and room(1)["sealed"], "1박자: 문 버팀 1")
	waits(2)
	check("M12", door(6, 5)["open"] and door(6, 5)["burnt"] and door(6, 5)["hp"] == 0 and not room(1)["sealed"], "2박자: 문이 타서 열림(영구)")
	waits(2)
	check("M12", heat(7, 5) == 1, "탄 문으로 열이 넘어간다")
	acts("U U")
	check("M12", game.pos == V(5, 5) and game.hp == 3, "불 칸에 들어가면 체력 −1")
	check("M12", not game.debug_act("CR") and game.clock == 8, "탄 문은 닫을 수 없다")
	scene("collapse")    # 방 버팀 2, (9,4) 불, 사람 (9,6), 소방관이 방 안 (7,5)
	waits(2)
	check("M12", room(1)["hp"] == 1 and not room(1)["collapsed"] and game.hp == 4, "1박자: 방 버팀 1")
	waits(2)
	check("M12", room(1)["collapsed"] and room(1)["hp"] == 0, "2박자: 방이 무너짐")
	check("M12", game.hp == 2 and vic(0)["state"] == "dead", "안에 있던 소방관 체력 −2, 바닥의 사람 사망")
	check("M12", game.debug_cell(V(7, 5))["rubble"] and game.debug_cell(V(9, 4))["rubble"] and fire(9, 4) == 0 and fuel(9, 4) == 0, "방 전체가 잔해, 불은 꺼짐")
	acts("L L")
	check("M12", game.pos == V(5, 5) and game.clock == 6, "잔해에서 나가는 것은 1행동씩(문 칸, 복도)")
	acts("R")
	check("M12", game.pos == V(6, 5) and game.clock == 7, "문 칸까지 1행동")
	acts("R")
	check("M12", game.pos == V(7, 5) and game.clock == 10 and game.beat == 5, "잔해 칸으로 들어가는 걷기는 3행동")
	scene("air")     # 공기 2에서 시작
	waits(2)
	check("M12", game.air == 0 and game.hp == 4, "공기 0")
	waits(5)
	check("M12", game.air == -5 and game.hp == 4, "0 아래로 5까지는 버틴다")
	waits(1)
	check("M12", game.air == -6 and game.hp == 3 and game.clock == 8, "−6에서 체력 −1")
	waits(6)
	check("M12", game.air == -12 and game.hp == 2 and game.clock == 14, "−12에서 또 −1")
	scene("death")   # 체력 1, 아래 칸 (5,8)에 불
	check("M12", game.hp == 1 and game.state == game.State.PLAY, "체력 1로 시작")
	check("M12", game.debug_act("D"), "불 칸으로 걸어 들어감")
	check("M12", game.hp == 0 and game.state == game.State.RESULT and game.result_cause == "dead" and game.result_stars == 0, "체력 0 → 결과(순직), ★ 0")
	check("M12", not game.debug_act("W") and game.clock == 1, "결과 화면에서는 행동 불가")
	game.debug_tap(Vector2(270, 480))
	check("M12", game.state == game.State.TITLE, "장면으로 시작한 출동의 결과에서 탭 → 타이틀")
