extends SceneTree
## 화면 캡처(빌드실 작성). SCREENS.md 의 화면 3개와 핵심 순간을 찍는다.
## 실행: python tools/screenshot.py games/echo-step-tactics  →  shots/*.png

const Content := preload("res://scripts/content.gd")

var game: Node
var frame := 0


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)


func shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	root.get_texture().get_image().save_png("res://shots/%s.png" % name)
	print("SHOT ", name)


func V(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


func one_floor(walls: Array, start: Vector2i, enemies: Array, spawns: Array = []) -> void:
	game.debug_load_floors([{"walls": walls, "start": start, "enemies": enemies, "spawns": spawns}])


func acts(seq: String) -> void:
	for a in seq.split(" ", false):
		game.debug_act(a)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			shot("01-title")
			game.debug_tap(Vector2(270, 480))
		70:
			shot("02-play-floor1-start")          # 1층 시작: 졸개 2, 이동 의도, 증원 예고
			acts("U SU R")
		130:
			shot("03-footprints")                 # 발자국 ①②③ (②는 베기 표시)
			game._press(Vector2(270, 820))
			game._drag(Vector2(270, 750))
		134:
			shot("04-preview-move")               # 누른 채 위로 민 미리보기: 도착 칸 윤곽 + ③
			game._release(Vector2(270, 818))      # 되돌려 떼기 = 취소
			game.debug_press("slash")
		138:
			shot("05-slash-mode")                 # 베기 토글 켜짐
			game.debug_press("slash")
			game.debug_load_floors([Content.FLOORS[1]])
		200:
			shot("06-archer-aim")                 # 2층: 궁수 조준 사선(빗금)과 "!"
			game.debug_load_floors([Content.FLOORS[2]])
			acts("U R")
		260:
			shot("07-floor3-intents")             # 3층: 궁수 2, 졸개, 증원 예고가 함께 보이는 순간
			one_floor([], V(3, 6), [["W", V(3, 2)], ["W", V(0, 0)]])
			acts("U D R")
		320:
			acts("U")                             # 메아리가 (3,5)를 밟아 졸개 처치
		344:
			shot("08-stomp-hit")                  # 명중 직후: 메아리 불투명, 조각, "밟기!"
			one_floor([], V(3, 3), [["A", V(3, 0)], ["W", V(0, 6)]])
			acts("D D D")
		400:
			acts("W")                             # 메아리가 화살을 막는 턴
		432:
			shot("09-echo-blocks-arrow")          # 화살, "막음", 체력 2(하트 3칸 비어 있음)
			one_floor([], V(3, 6), [["W", V(3, 5)]])
		480:
			shot("10-fist-intent")                # 치기 의도: 주먹 + 굵은 테두리
			acts("W")
		506:
			shot("11-hurt")                       # 피격: 붉은 테두리, 깨진 외곽
			acts("W W W W")
		570:
			shot("12-result-lose")                # 결과(패배): 원인 한 줄
			one_floor([], V(3, 6), [["A", V(3, 5)]])
			acts("SU W W W")
		630:
			shot("13-result-win")                 # 결과(승리)
			quit(0)
	return false
