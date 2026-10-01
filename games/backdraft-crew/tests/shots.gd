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
	add(2, func(): play(GOLD_C.substr(game.last_action.length()), 0))
	add(2, _c_spray)
	add(5, func(): shot("17-c-spray"))
	add(40, func(): shot("18-c-wet-cells"))
	add(2, func(): game.debug_swipe(Vector2(270, 300), Vector2(200, 300)))
	add(3, func(): shot("19-reject-shake"))
	add(2, func(): quit(0))


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
