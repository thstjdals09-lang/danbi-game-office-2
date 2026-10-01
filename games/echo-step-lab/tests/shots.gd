extends SceneTree
## 화면 캡처(빌드실·개발실 작성). SCREENS.md 의 화면 3개와 핵심 순간을 찍는다.
## 01~13: 1차 / 14~22: 2차(칼 하나, 방패병, 밀치기, 으깨기, 튕김, 층 클리어 발자국)
## 실행: python tools/screenshot.py games/<slug>  →  shots/*.png

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
			game.debug_press("slash")             # 칼이 손에 있을 때(베기를 쓰기 전)에 켠다
		74:
			shot("05-slash-mode")                 # 베기 토글 켜짐 (2차: 칼 하나 때문에 베기를 쓴 뒤에는 켜지지 않으므로 앞으로 옮김)
			game.debug_press("slash")
			acts("U SU R")
		130:
			shot("03-footprints")                 # 발자국 ①②③ (②는 베기 표시). 2차: 칼이 없어 버튼이 "칼 ②"
			game._press(Vector2(270, 820))
			game._drag(Vector2(270, 750))
		134:
			shot("04-preview-move")               # 누른 채 위로 민 미리보기: 도착 칸 윤곽 + ③
			game._release(Vector2(270, 818))      # 되돌려 떼기 = 취소
		138:
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
			# ---- 2차 ----
			game.debug_load_floors([Content.FLOORS[3]])
		690:
			shot("14-floor4-shield")              # 4층 시작: 방패병(막대 = 바라보는 쪽, 체력 점 2), 플레이어의 칼 선
			acts("U SU")
		750:
			shot("15-sword-out")                  # 칼 없음: 버튼 "칼 ③", 굵은 발자국, 플레이어 칼 선 없음, 안내 문구
			game.debug_press("slash")
		756:
			shot("16-sword-press-flash")          # 칼 없이 베기를 누름: 버튼 흔들림, 칼이 실린 발자국 깜빡임
			acts("W W W")
		820:
			shot("17-sword-back")                 # 칼이 돌아옴: 버튼 "베기", 칼 선 다시
			one_floor([], V(3, 3), [["S", V(3, 6)], ["W", V(0, 0)]])
			acts("D R W")
		880:
			shot("18-shield-faces-me")            # 방패병이 오른쪽(나)을 봄 + 치기 의도, 다음 턴 메아리가 (3,4)를 밟을 예정
			acts("U")
		899:
			shot("19-push")                       # 옆에서 밟힘: "밟기!", 한 칸 밀림, 체력 점 1
		940:
			shot("19b-push-after")                # 밀린 뒤의 정지 화면
			one_floor([V(2, 3)], V(3, 3), [["S", V(3, 6)], ["W", V(6, 0)]])
			acts("R L U U")
		1000:
			acts("U")
		1026:
			shot("20-crush")                      # 벽에 막혀 으깨짐: 납작, "으깨기!"
		1060:
			one_floor([], V(3, 6), [["S", V(3, 3)], ["W", V(0, 0)]])
			acts("SU W L")
		1120:
			acts("W")
		1140:
			shot("21-deflect")                    # 정면 베기: 방패 번쩍, "튕김"
		1180:
			game.debug_load_floors([{"walls": [], "start": V(3, 6), "enemies": [["W", V(3, 2)]], "spawns": []}, Content.FLOORS[3]])
			acts("U D R")
		1240:
			acts("U")                             # 밟기 처치로 층 클리어
		1272:
			shot("22-floor-clear-glow")           # 층 클리어: 발자국이 빛나며 사라짐
		1330:
			game.debug_load_floors([{"walls": [], "start": V(3, 6), "enemies": [["S", V(3, 5)]], "spawns": []}])
			acts("W W W W W")
		1390:
			shot("23-result-lose-shield")         # 패배 원인: 방패병의 치기, 처치 두 줄
			quit(0)
	return false
