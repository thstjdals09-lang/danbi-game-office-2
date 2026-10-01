extends SceneTree
## 화면 캡처(빌드실). SCREENS.md 의 화면마다 한 장 이상 + 핵심 순간.
## 실행: python tools/screenshot.py games/backdraft-crew  →  games/backdraft-crew/shots/*.png

const GOLD_A := "U U U L L L CU D P U R R D D D U U U U U U U L L L U U L L P R R D D R R D D D D D D D"
const GOLD_B := "U L L L U L P R X SD P D R R D SU U U R R R U U U P D X SD P D X SD P D L L D D U L L U U U U U U L L P R R D D D D D D R R D"
const GOLD_C := "U U U U U U R U U D U U U R R R D D D D U D CU R SD SL P L L X SD P D L L CR D D D D D D U U U U U U U U U U R R R D P U L L L D D D D D D D D D D U U U U U U U U U U L L L L P R R R D D D D D D D D D D"

var game: Node
var frame := 0
var steps: Array = []      # [기다릴 프레임 수, Callable]
var wait := 8
var idx := 0


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_plan()


func shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	root.get_texture().get_image().save_png("res://shots/%s.png" % name)
	print("SHOT ", name)


func tap() -> void:
	game.debug_tap(Vector2(270, 480))


## 정답 순서의 앞 n개를 한다. stop_on 이 있으면 그 일이 일어난 행동에서 멈춘다. 한 행동 수를 돌려준다.
func play(seq: String, n: int, stop_on := "") -> int:
	var done := 0
	for a in seq.split(" ", false):
		if done >= n:
			break
		game.debug_act(a)
		done += 1
		if stop_on != "":
			for e in game.rules.ev:
				if e["e"] == stop_on:
					return done
	return done


func add(frames: int, f: Callable) -> void:
	steps.append([frames, f])


func _plan() -> void:
	add(10, func(): shot("01-title"))
	add(2, tap)
	add(40, func(): shot("02-play-a-start"))
	add(2, func(): play(GOLD_A, 9))
	add(40, func(): shot("03-a-carrying"))
	add(2, func(): play(GOLD_A.substr(18), 99))        # 앞 9개(18글자) 뒤의 나머지
	add(40, func(): shot("04-a-at-exit-retreat-button"))
	add(2, func(): game.debug_act("Q"))
	add(40, func(): shot("05-result-all-saved"))
	add(2, tap)
	add(40, func(): shot("06-b-start-backdraft-signs"))
	add(2, func(): game.debug_press("water"))
	add(10, func(): shot("07-b-water-mode-preview"))
	add(2, func(): game.debug_press("water"))
	add(2, func(): play(GOLD_B, 99, "burst"))
	add(4, func(): shot("08-b-burst-hold"))
	add(12, func(): shot("09-b-burst-flame"))
	add(40, func(): shot("10-b-after-burst-forecast"))
	add(2, func(): game.debug_act("W"))
	add(2, func(): game.debug_act("W"))
	add(40, func(): shot("11-b-fire-spreading"))
	add(2, _walk_into_fire)
	add(5, func(): shot("12-b-hurt"))
	add(2, _die)
	add(40, func(): shot("13-result-dead"))
	add(2, tap)                                        # B 의 결과 → 건물 3
	add(40, func(): shot("14-c-start-carpet-smoke"))
	add(2, func(): play(GOLD_C, 22))
	add(40, func(): shot("15-c-before-close"))
	add(2, func(): game.debug_press("close"))
	add(10, func(): shot("16-c-close-button"))
	# 작은 장면(debug_load)으로 찍는 것: 물 3칸, 젖은 칸, 거절, 문 닫기 미리보기, 붕괴 예고와 잔해, 탄 문
	add(2, func(): game.debug_load(scene({"state": {5: "#####f#####", 4: "#####f#####", 3: "#####f#####"}, "start": 71})))
	add(30, func(): shot("17-scene-three-fires"))
	add(2, func(): game.debug_act("SU"))
	add(4, func(): shot("18-spray-three-cells"))
	add(40, func(): shot("19-wet-cells"))
	add(2, func(): game.debug_swipe(Vector2(270, 300), Vector2(200, 300)))
	add(2, func(): shot("20-reject-shake"))
	add(20, func(): game.debug_load(scene({"door": "/", "start": 60})))
	add(2, func(): game.debug_press("close"))
	add(20, func(): shot("21-close-mode-preview"))
	add(2, func(): game.debug_load(scene({"door": "/", "state": {4: "#########f#"}, "room_hp": 4, "start": 104})))
	add(2, func(): game.debug_act("W"); game.debug_act("W"))
	add(30, func(): shot("22-collapse-warning"))
	add(2, func():
		for i in 6:
			game.debug_act("W"))
	add(40, func(): shot("23-collapsed-rubble"))
	add(2, func(): game.debug_load(scene({"state": {5: "#####f#####"}, "door_hp": 2, "start": 93})))
	add(2, func():
		for i in 4:
			game.debug_act("W"))
	add(30, func(): shot("24-burnt-door"))
	add(2, func(): quit(0))


## 작은 장면: 세로 복도(x=5, 방 0) + 오른쪽 방(x 7~9, y 4~6, 방 1) + 왼쪽 방(x 1~3, 방 2). 문은 (6,5)와 (4,5).
## opts: door("+" 닫힘 / "/" 열림), state({줄 번호: 11글자, # 은 그대로 둠}), room_hp(방 1의 버팀), door_hp(문 (6,5)의 버팀), start(칸 번호)
func scene(opts: Dictionary) -> String:
	var d: String = opts.get("door", "+")
	var fl: Array = []
	var rm: Array = []
	var st: Array = []
	for y in 13:
		if y == 0:
			fl.append("###########")
		elif y == 12:
			fl.append("#####E#####")
		elif y == 5:
			fl.append("#..." + d + "." + d + "...#")
		elif y == 4 or y == 6:
			fl.append("#...#.#...#")
		else:
			fl.append("#####.#####")
		rm.append(" 222 0 111 " if y >= 4 and y <= 6 else ("     0     " if y >= 1 and y <= 11 else "           "))
		var row := "           "
		if (opts.get("state", {}) as Dictionary).has(y):
			row = (opts["state"][y] as String).replace("#", " ")
		st.append(row)
	var doors := {}
	if opts.has("door_hp"):
		doors["61"] = opts["door_hp"]
	var b := {"name": "scene", "title": "장면", "water": 8, "floor": fl, "room": rm, "state": st, "heat": {}, "fuel": {}, "doors": doors,
		"rooms": [{"air": 11, "gas": 0, "smolder": false, "front": -1, "hp": 30, "collapsed": false},
			{"air": 9, "gas": 0, "smolder": false, "front": -1, "hp": opts.get("room_hp", 30), "collapsed": false},
			{"air": 9, "gas": 0, "smolder": false, "front": -1, "hp": 30, "collapsed": false}],
		"victims": [], "start": opts.get("start", 137)}
	return JSON.stringify(b)


## 불 칸을 찾아 그 옆까지는 못 가더라도, 지금 자리에서 네 방향 중 불이 있는 칸으로 걸어 들어간다. 없으면 기다린다.
func _walk_into_fire() -> void:
	for k in 60:
		var p: Vector2i = game.pos
		var dirs := {"U": Vector2i(0, -1), "R": Vector2i(1, 0), "D": Vector2i(0, 1), "L": Vector2i(-1, 0)}
		for d in dirs:
			if game.debug_cell(p + dirs[d])["fire"] == 1 and game.debug_act(d):
				return
		game.debug_act("W")
		if game.state != game.State.PLAY:
			return


func _die() -> void:
	for k in 20:
		if game.state != game.State.PLAY:
			return
		game.debug_act("W")


func _c_spray() -> void:
	for d in ["SU", "SR", "SD", "SL"]:
		if game.debug_act(d):
			return


func _process(_delta: float) -> bool:
	frame += 1
	wait -= 1
	if wait <= 0 and idx < steps.size():
		(steps[idx][1] as Callable).call()
		idx += 1
		if idx < steps.size():
			wait = steps[idx][0]
	return false
