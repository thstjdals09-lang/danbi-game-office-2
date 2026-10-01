extends SceneTree
## 기획서 must_work 항목을 헤드리스로 확인한다.
## 실행: godot --headless --path games/first-lantern --script res://tests/smoke.gd

var game: Node
var frame := 0
var failures: Array[String] = []


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		3:
			check("M1", game.state == game.State.TITLE, "타이틀 화면에서 시작")
			game.debug_tap(Vector2(270, 700))
		4:
			check("M2", game.state == game.State.PLAY, "탭하면 플레이 시작")
			game.debug_spawn(Vector2(270, 480))
			game.debug_tap(Vector2(290, 500))
		5:
			check("M3", game.score == 1, "등불을 누르면 점수 +1")
			game.debug_spawn(Vector2(100, 300))
		6:
			game.lanterns[-1].age = game.LANTERN_LIFE
		8:
			check("M4", game.lives == game.LIVES - 1, "놓친 등불은 목숨 -1")
			game.lives = 0
		10:
			check("M5", game.state == game.State.RESULT, "목숨이 0이면 결과 화면")
			check("M5", game.best >= 1, "최고 기록 갱신")
			game.debug_tap(Vector2(270, 640))
		11:
			check("M6", game.state == game.State.PLAY and game.score == 0, "결과 화면에서 탭하면 재시작")
		12:
			for f in failures:
				printerr("SMOKE FAIL ", f)
			print("SMOKE %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
			quit(0 if failures.is_empty() else 1)
	return false


func check(id: String, ok: bool, label: String) -> void:
	print("[%s] %s %s" % [id, "ok  " if ok else "FAIL", label])
	if not ok:
		failures.append("%s %s" % [id, label])
