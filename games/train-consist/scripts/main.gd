extends Node2D
## 칸칸 열차 — 화물칸을 한 줄로 이어 열차를 편성한다. 역에 설 때마다 칸들이 앞에서 뒤로 차례로 작동해 서로의 효과를 키우고, 역마다 새 칸 하나를 골라 끼워 넣는다. 칸의 순서가 곧 엔진이 되는 로그라이크 빌드 게임.
## Builder가 SPEC.md의 must_work 항목을 기준으로 채운다.

enum State { TITLE, PLAY, RESULT }

const W := 960.0
const H := 540.0

var state: State = State.TITLE
var score := 0
var font: Font


func _ready() -> void:
	font = load("res://assets/fonts/NotoSansKR-Medium.ttf")


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tap(event.position)


func _tap(_pos: Vector2) -> void:
	match state:
		State.TITLE, State.RESULT:
			state = State.PLAY
			score = 0
		State.PLAY:
			pass


func _draw() -> void:
	draw_string(font, Vector2(0, H * 0.4), "칸칸 열차", HORIZONTAL_ALIGNMENT_CENTER, W, 40, Color("edf4ff"))


# 테스트용 훅: tests/smoke.gd가 입력을 흉내 낼 때 쓴다
func debug_tap(pos: Vector2) -> void:
	_tap(pos)
