extends SceneTree
## 화면 캡처. 빌드실이 작성한다(검사 파일이 아니므로 자유롭게 고쳐도 된다).
## SCREENS.md 의 화면마다 한 장 이상, 핵심 순간(피드백)도 찍는다.
## 실행: python tools/screenshot.py games/<slug>  →  games/<slug>/shots/*.png

var game: Node
var frame := 0


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


## 지금 화면을 res://shots/<name>.png 로 저장한다. 장면을 바꾼 뒤 최소 2프레임 지나서 부른다.
func shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	root.get_texture().get_image().save_png("res://shots/%s.png" % name)
	print("SHOT ", name)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			shot("01-title")
			game.debug_tap(Vector2(game.W / 2, game.H / 2))
		20:
			shot("02-play")
			quit(0)
	return false
