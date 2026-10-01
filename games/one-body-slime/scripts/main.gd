extends Node2D
## 몸 하나로 — 몸의 크기가 체력이자 탄약이자 열쇠인 슬라임 로그라이크
## Builder가 SPEC.md의 must_work 항목을 기준으로 채운다.

enum State { TITLE, PLAY, RESULT }

const W := 540.0
const H := 960.0

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
	draw_string(font, Vector2(0, H * 0.4), "몸 하나로", HORIZONTAL_ALIGNMENT_CENTER, W, 40, Color("edf4ff"))


# 테스트용 훅: tests/smoke.gd가 입력을 흉내 낼 때 쓴다
func debug_tap(pos: Vector2) -> void:
	_tap(pos)
