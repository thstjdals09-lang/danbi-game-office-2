extends SceneTree
## SPEC.md의 must_work 항목마다 check("M<n>", ...)를 하나 이상 둔다.
## 실행: python tools/smoke.py games/<slug>

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
			game.debug_tap(Vector2(game.W / 2, game.H / 2))
		4:
			check("M2", game.state == game.State.PLAY, "탭하면 플레이 시작")
		5:
			for f in failures:
				printerr("SMOKE FAIL ", f)
			print("SMOKE %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
			quit(0 if failures.is_empty() else 1)
	return false


func check(id: String, ok: bool, label: String) -> void:
	print("[%s] %s %s" % [id, "ok  " if ok else "FAIL", label])
	if not ok:
		failures.append("%s %s" % [id, label])
