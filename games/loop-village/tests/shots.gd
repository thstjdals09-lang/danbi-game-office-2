extends SceneTree
## 화면 캡처(빌드실). SCREENS.md 의 화면마다 한 장 이상 + 핵심 순간.
## 실행: python tools/screenshot.py games/loop-village  →  games/loop-village/shots/*.png
## 찍는 동안 실시간으로 틱이 넘어가지 않게, 단계마다 쌓인 시간을 0으로 돌린다(틱은 debug_tick 으로만 넘긴다).

var game: Node
var steps: Array = []
var wait := 10
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


func until(t: int) -> void:
	game.debug_tick(t - game.tick)


func add(frames: int, f: Callable) -> void:
	steps.append([frames, f])


func _plan() -> void:
	add(10, func(): shot("01-title"))
	add(2, tap)
	add(6, func(): shot("02-first-morning"))
	# 1바퀴: 빵집에서 지켜본다
	add(2, func(): game.debug_go("bakery"))
	add(4, func(): shot("03-walking-to-bakery"))
	add(2, func(): until(8))
	add(6, func(): shot("04-bakery-t8-new-note"))
	add(2, func(): until(9))
	add(6, func(): shot("05-bakery-t9-choice-from-notebook"))
	add(2, func(): until(12))
	add(6, func(): shot("06-bakery-t12-no-wood"))
	add(2, func(): until(24))
	add(6, func(): shot("07-bakery-t24-burnt"))
	add(2, func(): until(30))
	add(2, func(): game.debug_press("notebook"))
	add(6, func(): shot("08-notebook-timetable"))
	add(2, func(): game.debug_press("close"))
	add(2, func(): game.debug_press("sleep"))
	add(40, func(): shot("09-result-loop1-new-notes"))
	# 2바퀴: 정답을 예약으로
	add(2, tap)
	add(6, func(): shot("10-loop2-morning-expected-positions"))
	add(2, func(): game.debug_go("smithy"); game.debug_do("wood_take"); game.debug_go("bakery"); game.debug_do("wood_give"))
	add(2, func(): until(2))
	add(6, func(): shot("11-loop2-walking-with-queue"))
	add(2, func(): until(5); game.debug_do("slip"))
	add(6, func(): shot("12-smithy-taking-wood"))
	add(2, func(): until(11))
	add(6, func(): shot("13-bakery-t11-giving-wood"))
	add(2, func(): until(13))
	add(6, func(): shot("14-bakery-t13-after-slip"))
	add(2, func(): until(28))
	add(2, func(): game.debug_press("fast_down"))
	add(6, func(): shot("15-fast-forward"))
	add(2, func(): game.debug_press("fast_up"); until(50); game.debug_go("inn"); until(51))
	add(6, func(): shot("16-inn-t51-lunch"))
	add(2, func(): game.debug_tick(100))
	add(40, func(): shot("17-result-solved-stamp"))
	# 3바퀴: 여관에서 연기, 늦은 장작
	add(2, tap)
	add(2, func(): until(4); game.debug_go("smithy"); game.debug_do("wood_take"); game.debug_go("bakery"); game.debug_do("wood_give"))
	add(2, func(): until(15))
	add(6, func(): shot("18-late-wood-missed-and-late-choice"))
	add(2, func(): game.debug_go("inn"); until(24))
	add(6, func(): shot("19-inn-t24-smoke-signal"))
	add(2, func(): game.debug_go("inn"))
	add(4, func(): shot("20-rejected-same-place-hint"))
	add(2, func(): until(52); game.debug_press("notebook"))
	add(6, func(): shot("21-notebook-later"))
	add(2, func(): game.debug_press("close"); game.debug_tick(100))
	add(40, func(): shot("22-result-late-knot"))
	add(2, func(): quit(0))


func _process(_delta: float) -> bool:
	game.acc = 0.0
	wait -= 1
	if wait <= 0 and idx < steps.size():
		(steps[idx][1] as Callable).call()
		idx += 1
		if idx < steps.size():
			wait = steps[idx][0]
	return false
